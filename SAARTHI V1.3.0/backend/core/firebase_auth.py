"""Firebase Admin SDK setup and ID-token verification.

The Flutter app signs users in through Firebase and sends the resulting ID token as
an `Authorization: Bearer <token>` header. This module verifies those tokens so the
backend never handles a password itself.

Verification is *cryptographic*, not a lookup: the token is a JWT signed by Google,
and the Admin SDK checks the signature against Google's rotating public keys plus
the expiry, audience and issuer. That is why a client-supplied uid can never be
trusted on its own — anyone can claim a uid, but only Firebase can sign for one.
"""

import os

import firebase_admin
from dotenv import load_dotenv
from firebase_admin import auth as firebase_auth_admin
from firebase_admin import credentials

load_dotenv()

FIREBASE_CREDENTIALS_PATH = os.getenv(
    "FIREBASE_CREDENTIALS_PATH", "./secrets/firebase-service-account.json"
)


class FirebaseNotConfigured(RuntimeError):
    """Raised when the service-account key is missing or unreadable."""


def _initialize() -> None:
    """Initialize the default Firebase app exactly once.

    `firebase_admin.initialize_app()` raises if called twice, and uvicorn's reloader
    re-imports modules freely, so guard on the existing app list rather than on a
    module-level flag.
    """
    if firebase_admin._apps:
        return

    if not os.path.exists(FIREBASE_CREDENTIALS_PATH):
        raise FirebaseNotConfigured(
            f"Firebase service-account key not found at "
            f"'{FIREBASE_CREDENTIALS_PATH}'. Download it from the Firebase console "
            f"(Project Settings -> Service Accounts -> Generate new private key) and "
            f"save it there, or point FIREBASE_CREDENTIALS_PATH at it."
        )

    cred = credentials.Certificate(FIREBASE_CREDENTIALS_PATH)
    firebase_admin.initialize_app(cred)


def verify_firebase_token(id_token: str) -> dict:
    """Verify a Firebase ID token and return its decoded claims.

    Returns the claim dict, which always carries `uid` and usually `email`,
    `name` and `email_verified`.

    Raises `FirebaseNotConfigured` if the key is missing (a server misconfiguration,
    which callers should surface as a 503), or `firebase_admin.auth` errors such as
    `ExpiredIdTokenError` and `InvalidIdTokenError` for a bad token (a client
    problem, which callers should surface as a 401).
    """
    _initialize()
    return firebase_auth_admin.verify_id_token(id_token)
