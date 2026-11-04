# Google sign-in and Drive backup: OAuth setup

Finanzas IA signs in with Google (`google_sign_in` 7.x, Credential Manager on Android) and stores backups in the hidden app folder of
the user's Drive (`appDataFolder`, scope `https://www.googleapis.com/auth/drive.appdata`). Google is optional: without this setup the
app works, and the sign-in button reports a configuration error.

This setup cannot be automated: it needs the maintainer's Google account.

| Item | Value |
|---|---|
| Android package | `com.yosoyepa.finanzas` (`applicationId` in `android/app/build.gradle`) |
| Scope | `https://www.googleapis.com/auth/drive.appdata` |
| Drive folder | `appDataFolder` (hidden from the Drive UI; deleted when the app is uninstalled or the user removes its data) |

## 1. Project and API

1. Open the [Google Cloud console](https://console.cloud.google.com/) and create (or pick) a project.
2. Enable the **Google Drive API**: *APIs & Services > Library > Google Drive API > Enable*.
3. Configure the [Google Auth Platform](https://support.google.com/cloud/answer/15544987): *Get started*, then set the app name and support
   email (*Branding*), the *Audience* (**External**) and the contact email.
4. *Data Access > Add or remove scopes*: add `.../auth/drive.appdata`. It is listed as a non-sensitive scope
   ([Drive appData guide](https://developers.google.com/drive/api/guides/appdata)), so it needs no Google verification.
5. While the app is in *Testing* status, only accounts listed under *Audience > Test users* can sign in. Add the maintainer's Google
   accounts, or publish the app to production.

## 2. SHA-1 fingerprints

Each build signing key needs its own Android OAuth client. A sign-in that works in debug but not in release almost always means the
release SHA-1 is missing ([google_sign_in_android troubleshooting](https://pub.dev/packages/google_sign_in_android#troubleshooting)).

Debug key (PowerShell):

```powershell
keytool -list -v -alias androiddebugkey -keystore "$env:USERPROFILE\.android\debug.keystore" -storepass android
```

Release key (the one in `android/keys/key.properties`):

```powershell
keytool -list -v -alias <keyAlias> -keystore <storeFile>
```

Both, from the project:

```powershell
cd android
.\gradlew signingReport
```

Copy the `SHA1` line of the `debug` and `release` variants. Without `android/keys/key.properties`, release builds are signed with the debug
key (see `android/app/build.gradle`), so the debug SHA-1 is enough for them.

If the app is published with Play App Signing, also register the **app signing key** SHA-1 from the Play Console
(*Release > Setup > App integrity*): it differs from the upload key
([Authenticating your client](https://developers.google.com/android/guides/client-auth)).

## 3. OAuth clients

In *Google Auth Platform > Clients > Create client*:

1. **Android client(s)**: type *Android*, package name `com.yosoyepa.finanzas`, and the SHA-1 of one key. Create one client per SHA-1
   (debug, release, Play App Signing).
2. **Web application client**: type *Web application*, no redirect URIs needed. Its client ID is the `serverClientId` that
   `google_sign_in` 7 requires on Android when the app has no `google-services.json`
   ([google_sign_in_android integration](https://pub.dev/packages/google_sign_in_android#integration);
   [Credential Manager](https://developer.android.com/identity/sign-in/credential-manager-siwg-implementation) calls it the *Web Client ID*).

The Android clients carry no secret and nothing to copy into the app: Google matches package name and signature at runtime.

## 4. Give the web client ID to the app

The app reads the web client ID from a compile-time define (`GOOGLE_SERVER_CLIENT_ID`), so it is not stored in the repository:

```powershell
flutter build apk --release --split-per-abi --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
```

A web client ID is an identifier, not a secret. Never put a client secret in the app.

## 5. Check it

1. Install the APK, open *Settings > Google Drive backup* and tap *Sign in with Google*; accept the Drive permission.
2. Tap *Back up now*. The copy is named `finanzas-yyyyMMdd-HHmmss.db`; the 5 newest are kept.
3. Open *Restore*, pick a copy and confirm.

Typical errors:

- `clientConfigurationError`, or *canceled* right after picking the account: a missing or wrong SHA-1, a wrong package name, or a missing
  or wrong `serverClientId`.
- *access_denied* or a blocked consent screen: the account is not a test user while the app is in *Testing*.
- `403 accessNotConfigured`: the Drive API is not enabled in the project.

## Official references

- [Sign in with Google with Credential Manager](https://developer.android.com/identity/sign-in/credential-manager-siwg)
- [Implementation (`serverClientId` = Web client ID)](https://developer.android.com/identity/sign-in/credential-manager-siwg-implementation)
- [Authenticating your client (SHA-1, `keytool`, `signingReport`)](https://developers.google.com/android/guides/client-auth)
- [Google Auth Platform setup](https://support.google.com/cloud/answer/15544987)
- [Drive: store application-specific data](https://developers.google.com/drive/api/guides/appdata)
- [`google_sign_in_android`](https://pub.dev/packages/google_sign_in_android#integration)
