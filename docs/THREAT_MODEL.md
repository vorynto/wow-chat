# wow-chat threat model

## What we protect
- **Message/call content** — text, media, documents, audio/video.
- **Who talks to whom is minimized**, but routing metadata (tenant, conversation, sender,
  timestamp) is necessarily visible to the server to deliver messages. This is the same
  limitation Signal has; we reduce it (random handles, no phone number required) but do not
  claim to hide it.
- **The fact a chat app exists on the device** — via the "wow todo" decoy + secret code.

## Adversaries & mitigations

| Adversary | Threat | Mitigation |
|---|---|---|
| Network eavesdropper | Read messages/calls in transit | TLS to Supabase; E2E Double Ratchet on message bodies; DTLS-SRTP on calls. Server sees only ciphertext. |
| Compromised/curious server | Read stored content | Zero-knowledge storage: ciphertext + metadata only. Private keys never uploaded. |
| Cross-tenant attacker | Read another tenant's data with a leaked anon key | Row-Level Security keyed on `tenant_id` + membership on every table. |
| Someone who picks up the unlocked phone | Find/open the chat | The chat hides behind the "wow todo" decoy and opens only with the secret code; `FLAG_SECURE` blocks screenshots/recents while it is open. |
| Forensic/offline attacker with the device | Pull the local DB | Local DB encrypted (SQLCipher) with a key held in Android Keystore (hardware-backed where available). Optional decoy PIN + panic wipe. |
| Carrier / "on another call" leakage | Learn a call is happening / block the phone line | Calls are VoIP over data — the carrier never sees them and the cellular line stays free. |

## Explicit non-goals (be honest with users)
- **Not hidden on iOS.** The decoy pattern can be ported, but iOS review/sideloading differs; Android is the target.
- **Not on Google Play.** Hidden-icon / secret-launch behavior violates Play policy.
- **Metadata is not fully hidden** from the server (delivery requires routing data). For
  stronger metadata privacy you'd need sealed-sender + a different trust model — a later phase.
- **Not a tool to monitor other people.** Covert installation on someone else's device is
  out of scope and unsupported.
- A determined attacker with a **rooted device + your unlocked screen + your PIN** can read
  anything. No app defeats that.

## Key handling rules (do not violate)
1. Private keys are generated on-device and stored only in Keystore-backed secure storage.
2. The server receives **public** keys/prekeys only.
3. Use vetted crypto (`libsignal_protocol_dart`). **Never hand-roll primitives.**
4. Encrypt media client-side *before* upload; Storage holds ciphertext only.
5. Encrypt SDP/ICE signaling payloads client-side too.
