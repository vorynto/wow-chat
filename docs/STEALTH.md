# Stealth: iconless app + secret dial code

wow-chat ships with **no launcher icon** and is opened by entering a secret code in the phone
dialer. This document explains exactly what works, on which Android versions, and why.

## How "no icon" works
The app has a single activity (`MainActivity`) with **no `LAUNCHER` intent-filter**, so it
never appears in the app drawer — on any Android version. A dev-only `DevLauncher` alias
(disabled in release via `showLauncherIcon=false`) lets you open it during development.

What this does **not** hide:
- **Settings → Apps** still lists it (and its data/battery usage). Hiding from the app manager
  requires root or device-owner privileges — impossible for a normal sideloaded app.
- First install may briefly surface it in the launcher's "recently installed" on some OEMs.

## How the dial code works — and where it breaks
Two mechanisms are wired in `SecretCodeReceiver`:

| Mechanism | How the user triggers it | Works on |
|---|---|---|
| `SECRET_CODE` broadcast | Dial `*#*#<code>#*#*` in the stock dialer | **Android ≤ 8 reliably.** Android 9+ makes it a **system-only** broadcast — a sideloaded app does **not** receive it. |
| `NEW_OUTGOING_CALL` | Type `<code>` as a number, press call | **Android ≤ 9.** **Deprecated in Android 10**, needs the restricted `PROCESS_OUTGOING_CALLS` permission; often blocked by OEMs. |

**Bottom line:** the "type a code in the *stock* dialer" experience is reliable on **Android 9
and older**. On **Android 10–14** Google closed both paths specifically to stop hidden apps.

## Robust entry on modern Android (10–14)
If you need dependable dial-code entry on current phones, wow-chat must become the
**default phone/dialer app**. As the default dialer it owns the keypad and sees the digits the
user types, so it can intercept the secret code itself — no OS broadcast needed. Trade-off: a
default dialer **has an icon** (it appears as your "Phone" app) and must provide a real
in-call UI. It's a normal-looking icon, not an obvious messenger, but it is not iconless.

This is implemented behind a build flag (not enabled by default). To add it you need:
- an activity with `ACTION_DIAL` / `tel:` intent-filters and `RoleManager.ROLE_DIALER`,
- a minimal `InCallService`,
- keypad input matching for the secret code.

See `TODO(default-dialer)` markers. Ask and I'll wire the full default-dialer path.

## Choosing your target
- **Android ≤ 9 only / custom ROM:** pure iconless + `*#*#code#*#*` works great as-is.
- **Modern phones, iconless is mandatory:** the stock-dialer code is unreliable; use an
  alternate hidden trigger (a Quick Settings tile, an NFC tag, a specific number dialed from a
  contact) or accept the Settings-list visibility and launch via the dev alias.
- **Modern phones, reliable dial-code is mandatory:** become the default dialer (has an icon).

## Opening it during development
Release builds have no icon. To open the app while developing:
```bash
adb shell am start -n com.wowchat/.MainActivity
```
or build with `-PshowLauncherIcon=true` to temporarily enable the `DevLauncher` icon.
