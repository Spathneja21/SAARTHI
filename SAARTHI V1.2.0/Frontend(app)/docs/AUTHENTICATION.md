# Firebase Authentication Documentation

## 1. The Big Picture
**Why use Firebase?** 
Building authentication from scratch requires dealing with password hashing, database security, session tokens, and OAuth flows. Firebase handles all the complex security automatically. Our app simply asks Firebase: *"Is this user logged in, and who are they?"*

**The App Flow Before:**
`Splash Screen` → `Check SharedPreferences` → `Onboarding or Home`

**The App Flow Now:**
`Splash Screen` → `Check Firebase Auth Token` 
- If no token → `Login Screen`
- If token exists → `Home Screen`

---

## 2. Core Concepts

### Reactive Navigation
In modern app architecture, the Login button doesn't directly route you to the Home screen. Instead, the "root" of the app (our Splash Screen) acts as a router. When you log in, the app state changes, and the router automatically redirects you based on your new auth status.

### Data Persistence vs. Authentication
Firebase currently only handles **Who you are** (Authentication). It does **not** currently save your tasks in the cloud. 
Right now, tasks are saved locally on your phone using `SharedPreferences`. If you switch devices or accounts, your tasks will not follow you until we connect the Python/PostgreSQL backend.

### Password Security
Firebase NEVER exposes user passwords. When a user creates an account, Firebase mathematically scrambles the password (hashing & salting) and stores the scramble. If hacked, the actual passwords remain safe.

---

## 3. The Setup Process

Integrating Firebase requires bridging three different environments: Google's Servers, your Terminal, and your Flutter Code.

### Phase A: Firebase Console (The Server)
1. Created a new Firebase project (`saarthi-931dd`)
2. Enabled the **Email/Password** authentication provider in the Build menu.

### Phase B: CLI Tools (The Bridge)
1. **Firebase CLI:** Allowed our terminal to log into Google (`firebase login`).
2. **FlutterFire CLI:** We ran `flutterfire configure`. This command analyzed our Flutter project, registered Android/iOS/Web apps on Google's servers, downloaded the secret API keys, and auto-generated `lib/firebase_options.dart`. 
   - *Rule:* Never manually edit `firebase_options.dart`.

### Phase C: Flutter Code (The App)
1. **Installed Packages:** Added `firebase_core` (the engine) and `firebase_auth` (the auth features).
2. **Initialization:** Updated `main.dart` to run `Firebase.initializeApp()` before the app boots. Without this, the app crashes when trying to use Firebase services.

---

## 4. The Code Architecture

We implemented the feature using a clean, separated architecture:

### 1. The Wrapper (`lib/core/services/auth_service.dart`)
We didn't write Firebase code directly into our UI. Instead, we created an `AuthService` class.
- **Why?** It keeps our code clean. The UI just calls `AuthService().signIn()`. If we ever switch away from Firebase, we only update this one file.
- **Error Handling:** Firebase throws ugly error codes (e.g., `email-already-in-use`). Our wrapper catches these and translates them into user-friendly English sentences.

### 2. The UI (`lib/features/auth/login_screen.dart`)
- A single screen handles both Login and Sign Up via a simple `_isLoginMode` boolean toggle.
- Form validation ensures passwords are at least 6 characters and emails have an `@` symbol *before* wasting network resources talking to Firebase.
- Added `signup_success_screen.dart` to provide visual confirmation when a new account is created, forcing a manual login afterward to verify credentials.

### 3. The Router (`lib/features/splash/splash_screen.dart`)
- Acts as the bouncer. Checks `AuthService().currentUser`. If the user is null, they are sent to the Login screen. If a user exists, they bypass login entirely.

---

## 5. Connecting to the Future Backend

How this ties into your FastAPI + PostgreSQL backend:

1. User logs into Firebase via the App.
2. Firebase gives the App a unique **UID** (User ID) and a secure session token.
3. The App sends that **UID** to your Python backend when requesting or saving tasks.
4. Your PostgreSQL database uses that UID as a foreign key:
   `user_id: [Firebase UID] | name: Shabd | tasks: [...]`
5. Your Python backend never sees or touches user passwords.
