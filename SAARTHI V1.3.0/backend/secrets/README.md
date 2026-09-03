# secrets/

Runtime credentials. **Everything in this directory except this README is
gitignored and dockerignored.** Nothing here should ever appear in a commit, a
Docker image, a screenshot, or a chat message.

## firebase-service-account.json

Required for authentication. The backend uses it to verify the Firebase ID tokens
the Flutter app sends, so protected endpoints return **503** until it is present.

**To obtain it:**

1. Open the [Firebase console](https://console.firebase.google.com/) and select the
   project the Flutter app is configured against — `saarthi-931dd`, per
   `lib/firebase_options.dart`.
2. Go to **Project Settings → Service Accounts**.
3. Click **Generate new private key** and confirm.
4. Save the downloaded file here as exactly `firebase-service-account.json`.

The project must match the app's. A key from a different Firebase project will
verify nothing and every request will 401.

**What this key can do:** act as an administrator of the Firebase project — mint
tokens, read and modify any user. Treat it like a root password. If it is ever
exposed, revoke it immediately in the same console screen and generate a new one.

`docker-compose.yml` mounts this directory into the API container read-only at
`/app/secrets`, rather than copying it into the image, so the key stays out of any
image layer.
