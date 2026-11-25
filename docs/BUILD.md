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
  --dart-define=SECRET_DIAL_CODE=7469 \
  --dart-define=ICE_SERVERS='[{"urls":"stun:stun.l.google.com:19302"}]'
```

Wire the secret code and the iconless/dev-icon toggle into `android/app/build.gradle`. The
native receiver reads `SECRET_DIAL_CODE` from `BuildConfig`; the manifest reads the two
placeholders:
```gradle
android {
    buildFeatures { buildConfig true }
    defaultConfig {
        def secretCode = project.findProperty('SECRET_DIAL_CODE') ?: '7469'
        buildConfigField "String", "SECRET_DIAL_CODE", "\"${secretCode}\""
        // Manifest placeholders:
        manifestPlaceholders = [
            // host for the *#*#<code>#*#* SECRET_CODE intent-filter
            secretDialCode : secretCode,
            // false in release => NO launcher icon. Pass -PshowLauncherIcon=true for dev.
            showLauncherIcon: (project.findProperty('showLauncherIcon') ?: 'false')
        ]
    }
}
```

Release build is iconless. For a dev build you can open from the drawer:
```bash
flutter build apk --debug -PshowLauncherIcon=true --dart-define=...
```
or always open via `adb shell am start -n com.wowchat/.MainActivity`.

> Read `docs/STEALTH.md` first: the stock-dialer code path is reliable only on Android ≤ 9.
> On Android 10+ it's restricted; robust entry there needs the default-dialer approach.

## 5. Build the APK (sideload)
```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=SECRET_DIAL_CODE=7469
```
Output: `build/app/outputs/flutter-apk/app-release.apk`. Install with `adb install`.

## 6. Using the stealth features
- The app appears in the drawer as **Calculator**. Open it, type the passcode, press `=`.
- Or dial `*#*#7469#*#*` in the **system phone app**. Grant the outgoing-call permission on
  first use. (This path is Android-only and not available through Google Play.)

## Known limits
- No Google Play distribution (policy). Sideload or private MDM only.
- No iOS stealth (platform-impossible). An iOS client would be a normal, visible messenger.
- The secret-dial-code path depends on `NEW_OUTGOING_CALL`, which newer Android versions
  increasingly restrict; test on your target OS versions.
