# Firebase Authentication

## 1. The Big Picture

**Why Firebase?** Building auth from scratch means dealing with password hashing,
session tokens, credential storage and OAuth flows. Firebase handles all of it.
Our app asks one question: *"Is this user signed in, and who are they?"*

**Before:**
`Splash` → check SharedPreferences → `Onboarding` or `Home`

**Now:**
`Splash` → check Firebase for a signed-in user
- no user → `LoginScreen`
- user, onboarding incomplete → `OnboardingFlow`
- user, onboarding complete → `HomeScreen`

And critically — this is what changed in Phase 5/6 — the **backend** now verifies
that same Firebase identity on every request. Firebase no longer only answers
"who are you" for the app's own benefit; it is what makes a user's data theirs.

---

## 2. Core Concepts

### Reactive navigation
The Login button does not route you to Home. It signs you in and sends you back
to `SplashScreen`, which is the app's single routing decision — it re-reads the
auth state and picks the destination. One place makes the choice, so it cannot
disagree with itself.

### Authentication vs. data
Firebase holds the **credential**. It does not hold your tasks.

Your tasks, fixed commitments and scheduled blocks live in **PostgreSQL behind
the AURA backend**, keyed to your Firebase UID. That is what makes them follow
you across devices — and what makes them *not* follow the device to the next
person who signs in on it.

`SharedPreferences` retains only two things now: your display name and the
onboarding-complete flag.

### Password security
Firebase never exposes passwords. It hashes and salts them, and the backend never
sees one at any point — it only ever sees a signed token.

---

## 3. Setup

Integrating Firebase bridges three environments: Google's servers, your terminal,
and the Flutter code.

### Phase A — Firebase Console
1. Created the project `saarthi-931dd`.
2. Enabled the **Email/Password** provider under Build → Authentication.

### Phase B — CLI tools
1. **Firebase CLI** — `firebase login`, so the terminal can talk to Google.
2. **FlutterFire CLI** — `flutterfire configure`. This registered the
   Android/iOS/web apps, pulled the API keys, and generated
   `lib/firebase_options.dart`.
   - *Rule:* never hand-edit `firebase_options.dart`.

### Phase C — Flutter
1. Added `firebase_core` (the engine) and `firebase_auth` (the auth features).
2. `main.dart` runs `Firebase.initializeApp()` **before** `runApp`. Without it,
   the first call to `FirebaseAuth.instance` — which the splash screen makes
   immediately — throws.

### Phase D — the backend side
The FastAPI server needs the **Admin SDK**, which is a different credential from
the client keys:

1. Firebase Console → Project Settings → Service Accounts → *Generate new private
   key*.
2. Save it as `Aura-backend/secrets/firebase-service-account.json`.
3. `docker-compose.yml` mounts `./secrets` read-only at `/app/secrets` rather
   than copying it into the image — `secrets/` is in `.dockerignore`, so the key
   never becomes a layer that travels with the image.

Without that file the backend cannot verify tokens and answers **503** on every
protected endpoint. The app reports this as *"The server is not fully configured
yet"* and deliberately **does not** treat it as a sign-out — otherwise it would
loop trying to re-authenticate against a broken server.

---

## 4. The Code

### The wrapper — `lib/core/services/auth_service.dart`
No Firebase code in the UI. `AuthService` exposes `currentUser`,
`authStateChanges`, `signUpWithEmailPassword`, `signInWithEmailPassword` and
`signOut`.

- **Why:** if we ever move off Firebase, one file changes.
- **Error handling:** Firebase throws codes like `email-already-in-use` and
  `invalid-credential`. `_handleAuthException` translates them into sentences a
  person can read.

### The UI — `lib/features/auth/login_screen.dart`
One screen for both modes, toggled by `_isLoginMode`. Validation (email contains
`@`, password ≥ 6 characters on sign-up) runs **before** any network call, so an
obviously bad input never costs a round trip.

Sign-up deliberately calls `signOut()` afterwards and routes to
`signup_success_screen.dart`, forcing a manual login so the credentials are
proven once.

### The router — `lib/features/splash/splash_screen.dart`
The bouncer. Reads `AuthService().currentUser`, then the local profile, and picks
Login / Onboarding / Home. Its animation runs in parallel with that check, and if
the check has not finished it runs another full lap rather than cutting off.

### The token carrier — `lib/core/api/api_client.dart`
Every request to the backend carries `Authorization: Bearer <ID token>`.

```dart
final user = auth.currentUser;
if (user == null) throw ApiException(401, 'Not signed in.');
return await user.getIdToken();
```

The token is fetched **per request and never cached locally**. `getIdToken()`
already returns a cached value until roughly five minutes before expiry and
refreshes transparently — caching it again would only risk sending a stale one.

If the account is disabled or deleted while the app is open, the refresh throws a
`FirebaseAuthException`; the client turns that into a 401 rather than a crash.

### Sign-out — `home_screen._signOut`
Signing out is not just `AuthService().signOut()`. It also clears `TaskStore`,
`ScheduleSlotStore`, `CommitmentStore` and `UserProfileStore`.

This fixes a **real data leak**. The local profile keys are not namespaced by
user, and sign-out used to leave them in place — so signing in as a different
account on the same device showed the previous person's name and, because
`isOnboardingComplete` was still true, skipped onboarding entirely, dropping the
new user into a home screen greeting someone else.

---

## 5. How the Identity Reaches the Backend

```
1. User signs in to Firebase in the app.
2. Firebase returns a UID and a signed ID token (a JWT).
3. ApiClient attaches that token to every request:
       Authorization: Bearer eyJhbGciOi...
4. core/dependencies.py::get_current_user calls verify_firebase_token().
5. The Admin SDK checks the SIGNATURE against Google's rotating public keys,
   plus expiry, audience and issuer.
6. The verified claims (uid, email, name) are used to find or create the local
   users row.
7. Every query in that request is scoped to that user.
```

**Why verification, not a lookup.** Anyone can *claim* a UID; only Firebase can
*sign* for one. That is why the backend never trusts a client-supplied uid and
why the check is cryptographic rather than a database comparison.

### Auto-provisioning
On the first authenticated request, `_find_or_create_user` creates the local
`users` row from the token's claims. There is **no separate backend registration
step** — signing in to Firebase is enough. Three details:

- `users.username` is unique and NOT NULL, but Firebase has no username concept,
  so one is synthesized from the email's local part (falling back to
  `user_<uid prefix>`), with numeric suffixes on collision.
- An account that predates Firebase — created through the legacy `/register`
  endpoint — is **adopted by email** rather than colliding with the unique email
  index.
- Two concurrent first-requests can race; the loser catches the `IntegrityError`
  and re-reads the row the winner just wrote.

`hashed_password` is `NULL` for Firebase-created users. We hold no credential.

### Status codes and what they mean to the app

| Code | Cause | App behaviour |
|---|---|---|
| **401** | Missing header, or an invalid/expired token | Session expired → sign in again |
| **403** | Account deactivated (`is_active = false`) | Treated as unauthorized |
| **404** | Resource gone — **or it belongs to another user** | The backend returns 404 rather than 403 so it does not leak whether that id exists |
| **503** | Service-account key missing on the server | *"The server is not fully configured yet."* **Never** a sign-out |

FastAPI's `HTTPBearer` rejects a request with no `Authorization` header before
our code runs. On FastAPI 0.138.2 that rejection is a **401**; older versions
returned **403**. The client treats both as "not signed in" rather than relying
on one.

---

## 6. Legacy endpoints

`POST /register` and `POST /login` still exist on the backend, issuing the
server's own HS256 JWTs. **The app does not use them** — Firebase replaced that
path entirely. They remain for scripted testing and for accounts created before
the switch.

---

## 7. Testing auth without a device

`flutter test` cannot boot Firebase (no platform channels), so `ApiClient` has a
second constructor:

```dart
ApiClient.withTokenProvider(() async => token, baseUrl: 'http://localhost:8000')
```

Mint a real token for the integration suite:

```bash
cd ../Aura-backend
docker compose exec -T api python scripts/mint_test_token.py <WEB_API_KEY> <uid> <email> > /tmp/e2e_token.txt
```

`test/api_integration_test.dart` covers that a bad token surfaces as
unauthorized, and that an unreachable backend is distinguishable from an auth
failure — the two must never be confused, because one means "sign in again" and
the other means "start the server".

---

## 8. Not built yet

- **Google Sign-In** — only email/password is enabled.
- **Password reset** — `sendPasswordResetEmail` is not wired up.
- **Email verification** — the claim is read but never enforced.
- **Reactive sign-out** — `authStateChanges` is exposed on `AuthService` but
  nothing listens to it, so a token revoked server-side surfaces as a 401 on the
  next request rather than an immediate redirect.

---

**Last Updated:** September 7, 2026
