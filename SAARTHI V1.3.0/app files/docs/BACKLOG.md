# Backlog

Known issues and follow-up work, newest first. Each entry records what was
observed, what actually causes it, and the options considered — so the next
person does not have to re-derive the diagnosis.

---

## 1. Onboarding re-runs on every sign-in — FIXED

**Was.** The gate was `profile.isOnboardingComplete`, held only in
`SharedPreferences`, which `_signOut()` deliberately wipes (correctly — the keys
are not namespaced per user, and leaving them let the next person signing in
inherit the previous user's name and skip onboarding). Nothing about "I have
already set this up" belonged to the account, so every sign-in rebuilt it.

**Now.** Routing is decided from account state:

- **Onboarded?** `splash_screen.dart` loads `GET /schedule/commitments`.
  Onboarding cannot finish without at least one fixed weekly slot, and those are
  per-account server data, so their presence answers the question in a way no
  amount of clearing local storage can lose. If that request fails, the device's
  cached flag is used rather than marching a returning user back through setup.
- **Name?** Written to the Firebase account via `updateDisplayName()` when
  onboarding completes. `displayName` survives sign-out, reinstalls and a second
  device.
- **Older accounts** whose name only ever existed on the device are backfilled
  onto the account at splash, if the local copy is still there.
- **Accounts where the name is gone entirely** get `NameCaptureScreen` — one
  screen asking only for the name, rather than the whole flow, because the fixed
  schedule they already have is on the server.

**Still open.** The backend user record has `full_name` and `username`
(`schemas.py`), but there is no `GET /me` to read them, and the app never calls
`POST /register` — it authenticates with Firebase — so those columns are never
populated from here. A real user-profile endpoint would let the name come from
the same place as everything else, and would remove the need for
`NameCaptureScreen` and the Firebase `displayName` round-trip.

---

## 2. Planned work

Requested, not yet started.

1. **Password reset / forgot password**, over email. Firebase Auth already has
   `sendPasswordResetEmail()`, so this is a login-screen affordance plus the
   template configuration in the Firebase console rather than backend work.
2. **New background for the login and onboarding screens.** Those still use the
   plain scaffold with two `SoftBlob`s; the rest of the app has moved to the
   animated `FluidMorphBackground` and frosted panels, so the entry flow now
   looks like it belongs to an older version of the product.
3. **Google Calendar link-up.** Worth deciding early whether imported events
   become `FixedCommitment`s (immovable, the scheduler works around them) or a
   third block type, because the CP-SAT solver and the timeline both key off
   that distinction.
4. **Transitions and button-press animations.** No route transitions are
   customised anywhere, and taps have only the default ink response.
5. **Randomised greeting** in place of the fixed "Hello, {name}" in the app bar.

---

## 3. Password reset — shipped, but the email and reset page are Firebase's

**Shipped.** A "Forgot password?" link on the login screen (login mode only)
opens `forgot_password_screen.dart`, which calls Firebase's
`sendPasswordResetEmail()`. `AuthService` swallows `user-not-found` and the
confirmation says "If an account exists for…", so the screen cannot be used to
test which addresses are registered.

**What is left is not in the Flutter app.** Both remaining complaints are
properties of Firebase's hosted flow:

- **The email looks unbranded and lands in spam.** "saarthi-931dd" appears in
  the subject, body and sign-off because that is the project's *public-facing
  name* (Project Settings). The sender is `noreply@saarthi-931dd.firebaseapp.com`
  — a shared, unauthenticated domain, which is why Gmail flags it. Console alone
  fixes the naming, subject, body, sender name and reply-to; the local part of
  the from-address can change but the domain cannot. Deliverability only
  improves with **custom SMTP** (Auth → Templates → SMTP settings) on a domain
  you own, with SPF, DKIM and DMARC.
- **The reset page has no confirm-password field, and cannot be given one.** It
  is served by Google from `firebaseapp.com`. The only fix is a **custom action
  URL** pointing at a page we host, which reads `oobCode` from the query string
  and calls `verifyPasswordResetCode()` then `confirmPasswordReset()` via the
  Firebase JS SDK. That page would also let the password rules match the app's
  (min 6 characters, currently enforced only at sign-up).

**Groundwork already in place.** The backend has `firebase-admin` initialised
with a service account (`core/firebase_auth.py`), so it can call
`generate_password_reset_link()` and own the whole flow if wanted. It has **no
mailer** of any kind, so sending our own branded email means a new dependency.
Such an endpoint must be unauthenticated — the user is locked out — so it needs
rate limiting and should always answer 200, or it becomes the enumeration oracle
the app screen was careful not to be.

**Also note.** The link opens in the browser and never returns to the app. There
is no `ActionCodeSettings`, no deep-link package, and no in-app handling.
Routing it into the app needs universal links (Firebase Dynamic Links was shut
down in 2025), which in turn needs a real bundle id — it is still
`com.example.saarthi`, the untouched Flutter template default, which will also
block App Store submission.

---

## 4. Further suggestions

Observations from working in the code, roughly by value.

- **A day that fails to load is no longer abandoned — FIXED (partly).**
  `ensureDay` added the date to `_attempted` before fetching and never removed
  it on failure, so an errored day was never retried and stayed blank for the
  rest of the session. It now re-opens that gate after a backoff (8s in the app,
  injectable for tests), covered by `test/core/schedule_slot_store_test.dart`.
  **Still open:** a failed day and a day with nothing scheduled still render
  identically, so a persistent failure is silent. The store knows the
  difference — it has `error` and `isDayLoaded` — the timeline just does not
  show it.
- **One HTTP request per day scrolled.** Flicking through a month fires roughly
  thirty `GET /schedule/day` calls. A ranged endpoint — `GET /schedule/range`
  taking `from` and `to` — would collapse that into one, and would also make
  prefetching neighbours cheap.
- **The day cache never evicts.** `_cache` grows for every day visited until
  something invalidates it. Bounded in practice by patience, but a window around
  the visible date would be tidier.
- **Days are assumed to be exactly 24 hours.** `_dayHeight` is a constant, so on
  a daylight-saving transition the column is the wrong height and every block
  after the change is offset by an hour. Rare, but silently wrong when it hits.
- **The timeline's top inset is a magic 110.** It has to match the week strip's
  real height (72 plus its padding); nothing links them, so changing the strip
  will quietly misalign the timeline. Worth deriving from the strip itself.
- **Test coverage stops at the dashboard.** The timeline now carries real
  arithmetic — block/grid alignment, marker centring, day indexing across the
  centre sliver, the cache's generation guard — and all of it was verified by
  eye. That logic is cheap to unit test and expensive to debug visually.
- **`UserProfile.primaryTask` is dead.** Onboarding always writes `''` and
  nothing reads it. It is still persisted and passed around.
- **The whole timeline rebuilds every 30 seconds.** `_minuteTicker` calls
  `setState` on `TimelineView` to move the now-line, which now rebuilds every
  visible day column rather than one. Lifting the now-line into its own
  animated widget would confine it.
- **No screen-reader support on the timeline.** Blocks are tappable `InkWell`s
  with no `Semantics`, so a session announces nothing useful.

---

## 5. Smaller items found but not addressed

- **Date pill overlaps the first task block.** `_datePill` is pinned at
  `top: 110, right: 18` over the scrolling timeline content, so it sits on top
  of any block in that region.
- **Snackbar covers the button stack.** `SnackBarBehavior.floating` reserves no
  room for the two 56pt circles bottom-right, so a message rises over them.
- **Short sessions overhang their end line.** `_blockGeometry` clamps height to a
  26px minimum, so a session under roughly 21 minutes is drawn taller than its
  true duration and breaks the block/grid alignment everything else now keeps.
- **The plan button's glyph is low contrast.** White on `kNowAccent`
  (`#FF8FA3`) measures about 2.2:1. Its neighbour, white on `#007AFF`, is about
  4:1 and clears the 3:1 bar for non-text UI. Darkening the button's pink alone,
  leaving the now-line as is, would fix it without breaking the pairing.
- **`test/widget_test.dart` fails, and did before any recent work.** It pumps
  `SaarthiApp()` with no `Firebase.initializeApp()`, giving
  `[core/no-app] No Firebase App '[DEFAULT]' has been created`. It is the stock
  template test, never updated after Firebase landed.
- **Commitments are fetched twice at startup.** Splash now loads them to decide
  routing, and `HomeScreen._loadEverything` loads them again. Harmless but
  wasteful; worth a `hasLoaded` guard that does not break refresh-on-return.
- **There is no way to change your name after onboarding.** `NameCaptureScreen`
  only appears when the name is missing entirely. A settings screen would be the
  natural home for editing it.
- **The app still ships the stock Flutter icon.** Every platform's icon set is
  the untouched template artwork — there is no `assets/` directory, nothing
  declared in `pubspec.yaml`, and `flutter_launcher_icons` is not set up, so no
  icon has ever been authored. The app does already have a mark to build on:
  `MorphingSparkle` draws a four-petal sparkle for the splash, and
  `Icons.auto_awesome` echoes it on the Plan button. Whatever the artwork ends
  up being, it needs a 1024x1024 master plus an Android adaptive foreground and
  background. Blocks release alongside the `com.example.saarthi` bundle id.
- **The macOS build cannot reach the network.** `macos/Runner/*.entitlements`
  enable `app-sandbox` but never declare
  `com.apple.security.network.client`, so every outbound socket is denied —
  Google Fonts, Firebase auth and all API calls. iOS and the simulator are
  unaffected. Adding that one key to both entitlements files fixes it.
