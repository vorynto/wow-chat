# wow-chat

A multi-tenant, privacy-first, end-to-end encrypted messenger for Android, built with
**Flutter** and **Supabase**. Users install it on **their own device** to keep **their own**
communications private. It supports text, media and document sharing, and encrypted
audio/video calls over the internet (so calls never touch — or block — the cellular voice line).

> **Scope & intent.** wow-chat is a *private messenger a person installs on their own phone*.
> It is **not** a tool for secretly installing on someone else's device to monitor them. That
> would be stalkerware; this project does not build it and will not help with it.

---

## What's realistic (read this before building the "stealth" parts)

| Requested feature | Reality | What we build |
|---|---|---|
| Hidden from the app list | Hiding a launcher icon is **blocked on Android 10+** for normal apps. Fully invisible only via sideloaded APK; **Google Play bans it**. | A **decoy launcher** (app shows up as e.g. "Calculator"); the real chat UI is unlocked by a secret code. |
| Open via dial-pad code | Android only. A `NEW_OUTGOING_CALL` receiver can catch a secret code like `*#*#7469#*#*` typed in the **real phone dialer** and launch the app. iOS cannot do this. | A `SecretCodeReceiver` (see `android/`). |
| Carrier doesn't detect the call / "I'm on another call" | **Automatic.** Calls are VoIP/WebRTC over data. The carrier never sees a call, the cellular line stays free, incoming regular calls still ring. No evasion needed. | WebRTC + DTLS-SRTP, signaling over Supabase Realtime. |
| Highly secure, no data leaks | The core of the app. | E2E encryption (libsignal Double Ratchet), ciphertext-only backend, encrypted-at-rest local DB, strict RLS, app-lock, panic wipe. |
| iOS | Cannot hide the app or register dial codes. | Out of scope for stealth; a normal private iOS client could be added later. |

**Distribution:** Android APK, sideloaded. Not Play Store (its policies forbid hidden-icon /
secret-launch behavior, and doing it anyway gets the developer account terminated).

---

## Architecture

```
┌─────────────────────────────── Android device ───────────────────────────────┐
│  Decoy launcher (Calculator)  ──secret code──▶  Real wow-chat UI (Flutter)    │
│  Secret dial code receiver    ──*#*#code#*#*─▶  (launches app)                 │
│                                                                               │
│  Flutter app                                                                  │
│   ├─ Crypto: libsignal (X3DH + Double Ratchet)  — private keys never leave    │
│   ├─ Secure store: Android Keystore + encrypted local DB (SQLCipher)          │
│   ├─ Privacy engine: per-user settings, app-lock, FLAG_SECURE, disappearing   │
│   └─ WebRTC: encrypted audio/video calls                                       │
└───────────────────────────────────────────────────────────────────────────────┘
           │ TLS                        │ TLS/Realtime                │ ICE/DTLS-SRTP
           ▼                            ▼                             ▼
  ┌──────────────────┐        ┌──────────────────┐          ┌──────────────────┐
  │ Supabase (Auth,  │        │ Supabase Realtime│          │ TURN/STUN server │
  │ Postgres + RLS,  │        │ (call signaling, │          │ (NAT traversal)  │
  │ Storage=ciphertext)       │  message fanout) │          └──────────────────┘
  └──────────────────┘        └──────────────────┘
```

**The server is zero-knowledge for message content.** Supabase stores only:
- ciphertext blobs (messages, encrypted media in Storage),
- routing metadata (tenant, sender id, recipient/conversation id, timestamp),
- public keys / prekey bundles for the X3DH handshake.

It never sees plaintext, and private keys never leave the device.

**Multi-tenancy.** Every row carries a `tenant_id`. Row-Level Security isolates each tenant so
one tenant's users can never read another's data, even with a stolen anon key.

---

## Repository layout

```
supabase/migrations/   SQL schema + Row-Level Security policies
lib/core/crypto/       Key management + E2E (libsignal) service
lib/core/storage/      Encrypted local storage (Keystore-backed)
lib/core/supabase/     Backend client + repositories
lib/core/config/       App config / env
lib/features/auth/     Sign-in, device registration, key publishing
lib/features/chat/     Conversations, messages, media
lib/features/calls/    WebRTC audio/video
lib/features/privacy/  Privacy settings model + enforcement
lib/features/stealth/  Decoy lock screen + secret-code gate
lib/features/tenant/   Tenant context
android/               Native: secret dial-code receiver, decoy launcher, FLAG_SECURE
docs/                  Threat model, build & deploy guide
```

See `docs/THREAT_MODEL.md` for the security model and `docs/BUILD.md` for build steps.

## Status

Scaffold / foundation. Crypto and WebRTC wire into vetted libraries (`libsignal_protocol_dart`,
`flutter_webrtc`) rather than hand-rolled primitives — hand-rolled crypto is how data leaks
happen, which is the one thing this app must not do.
