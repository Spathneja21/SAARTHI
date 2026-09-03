import re
import uuid

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from core.database import get_db
from core.firebase_auth import FirebaseNotConfigured, verify_firebase_token
from models.models import User

# auto_error=True (the default) makes FastAPI reject a request with no Authorization
# header before this function ever runs. Verified against FastAPI 0.138.2: that
# rejection is a 401 ("Not authenticated"). Older versions returned 403 here, so a
# client should treat both as "not signed in" rather than relying on one.
bearer = HTTPBearer()


def _username_from_claims(claims: dict) -> str:
    """Derive a candidate username from the token's email or uid.

    `users.username` is unique and NOT NULL, but Firebase has no username concept,
    so one has to be synthesized. Uniqueness is settled by `_find_or_create_user`.
    """
    email = claims.get("email") or ""
    local_part = email.split("@")[0] if "@" in email else ""
    candidate = re.sub(r"[^a-zA-Z0-9_.-]", "", local_part)
    if not candidate:
        candidate = f"user_{claims['uid'][:12]}"
    return candidate[:40]


async def _find_or_create_user(claims: dict, db: AsyncSession) -> User:
    """Return the local User for a verified Firebase account, creating it if needed.

    Auto-provisioning on first authenticated request means the app never needs a
    separate "register with the backend" step — signing in to Firebase is enough.
    """
    firebase_uid: str = claims["uid"]
    email: str | None = claims.get("email")

    existing = await db.execute(select(User).where(User.firebase_uid == firebase_uid))
    user = existing.scalar_one_or_none()
    if user is not None:
        return user

    # An account may predate Firebase (created through /register) or have been seeded
    # by hand. Adopt it by email rather than colliding with the unique email index.
    if email:
        by_email = await db.execute(select(User).where(User.email == email))
        user = by_email.scalar_one_or_none()
        if user is not None:
            user.firebase_uid = firebase_uid
            await db.commit()
            await db.refresh(user)
            return user

    base_username = _username_from_claims(claims)
    username = base_username
    for attempt in range(1, 6):
        taken = await db.execute(select(User).where(User.username == username))
        if taken.scalar_one_or_none() is None:
            break
        username = f"{base_username[:34]}_{attempt}"
    else:
        username = f"user_{uuid.uuid4().hex[:16]}"

    user = User(
        email=email or f"{firebase_uid}@firebase.local",
        username=username,
        hashed_password=None,           # Firebase holds the credential, not us
        firebase_uid=firebase_uid,
        full_name=claims.get("name"),
    )
    db.add(user)

    try:
        await db.commit()
    except IntegrityError:
        # Two concurrent first-requests from the same account can both reach this
        # point; the loser re-reads the row the winner just wrote.
        await db.rollback()
        retry = await db.execute(select(User).where(User.firebase_uid == firebase_uid))
        user = retry.scalar_one_or_none()
        if user is None:
            raise
        return user

    await db.refresh(user)
    return user


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer),
    db: AsyncSession = Depends(get_db),
) -> User:
    token = credentials.credentials

    try:
        claims = verify_firebase_token(token)
    except FirebaseNotConfigured as exc:
        # A server-side misconfiguration, not the client's fault — do not report 401,
        # or the app will loop trying to re-authenticate against a broken server.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        )
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        )

    if not claims.get("uid"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token carries no uid",
        )

    user = await _find_or_create_user(claims, db)

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is deactivated",
        )

    return user
