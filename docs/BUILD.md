# Build & deploy

> Flutter is not installed in the cloud session this scaffold was generated in. Run these on
> your own machine (or any box with the Android SDK + Flutter).

## 1. Prerequisites
- Flutter 3.22+ (`flutter --version`)
- Android SDK + a device/emulator (Android 10–14 tested targets)
- A Supabase project

## 2. Create the Flutter platform scaffolding
This repo contains the Dart/Android source but not the generated Flutter project files
(gradle wrapper, `build.gradle`, mipmaps, etc.). Generate them once, then our files sit on top:

```bash
# from the repo root
flutter create --platforms=android --org com.wowchat --project-name wow_chat .
flutter pub get
```

`flutter create` will not overwrite the files we committed (manifest, Kotlin, lib/). If it
reports conflicts on `AndroidManifest.xml`, keep **ours**.

You also need two launcher icons: `android/app/src/main/res/mipmap-*/ic_decoy.png` (a
calculator) and `ic_launcher.png` (the real icon).

## 3. Set up Supabase
```bash
# with the Supabase CLI
supabase link --project-ref <your-ref>
supabase db push        # applies supabase/migrations/*.sql (schema + RLS)
```
Create a Storage bucket named `media` (private). Media is uploaded as ciphertext.

Enable the auth method you want (email OTP / phone / anonymous). Each user's `profiles` row
must be created with the correct `tenant_id` at sign-up (do this in a secure Edge Function or
a trigger so the client can't set an arbitrary tenant).

## 4. Configure secrets at build time (never commit them)
```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=ACCESS_CODE=4729 \
  --dart-define=ICE_SERVERS='[{"urls":"stun:stun.l.google.com:19302"}]'
```

`ACCESS_CODE` is only the **initial** secret code (seeded on first run, stored salted-hashed).
Users change it in Privacy → Change secret code. No native gradle placeholders are needed for
stealth anymore — the app is a normal launcher app ("wow todo") and the unlock is pure Dart.

## 5. Build the APK (sideload)
```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=ACCESS_CODE=4729
```
Output: `build/app/outputs/flutter-apk/app-release.apk`. Install with `adb install`.

## 6. Using the app
- It installs and appears as **"wow todo"** — an ordinary to-do app. Add/check/delete tasks.
- To open the hidden chat: type the **secret code** in the "Add a task" box and submit.
- Inside chat: **Privacy → Lock now** returns to the to-do screen; **Change secret code** sets
  a new one.

## 7. Production release signing (optional)
The CI release APK is signed with the debug key so it installs for testing. For a real
release, create a keystore and wire it up:
```bash
keytool -genkey -v -keystore ~/wowchat.jks -keyalg RSA -keysize 2048 -validity 10000 -alias wowchat
```
Add `android/key.properties` (git-ignored) and a `signingConfigs.release` in
`android/app/build.gradle`, then build with `flutter build apk --release`. In CI, store the
keystore + passwords as repository secrets and decode them in a step before the release build.

## 8. iOS (normal, non-hidden client)
iOS **cannot** hide the app icon or disguise itself, so on iOS wow-chat is a normal messenger:
the "wow todo" screen + secret-code gate still work as an in-app lock, but the app is visible
on the Home Screen and subject to App Store review (which forbids the Android-style stealth).
To build iOS (needs macOS + Xcode):
```bash
flutter create --platforms=ios .
```
Add these keys to `ios/Runner/Info.plist` (required by WebRTC calls + file picking):
```xml
<key>NSCameraUsageDescription</key><string>Video calls</string>
<key>NSMicrophoneUsageDescription</key><string>Voice and video calls</string>
<key>NSPhotoLibraryUsageDescription</key><string>Attach photos and files</string>
```
Then `flutter build ipa`. Everything except the hiding/stealth is identical to Android.

## Known limits
- No Google Play distribution — a disguised app with hidden functionality violates Play policy.
  Sideload (APK) or private MDM only.
- The decoy is camouflage, not a crypto boundary. Real protection is the E2E encryption +
  encrypted local DB. The app is still listed in Settings → Apps as "wow todo".
- Works on all modern Android (11–14), unrooted — no special permissions required for the
  decoy/unlock.
