# Stealth: the "wow todo" decoy

wow-chat hides behind a **fully working to-do app called "wow todo"**. On the surface it is an
ordinary task list. The hidden chat is opened by typing a **secret code** into the add-task
box — no biometrics, no dialer, no special permissions.

## Why this design
We target **Android 11–14 on users' own (unrooted) phones**. On those, Google blocks the
"iconless app opened by a code in the stock dialer" trick (`SECRET_CODE` is system-only since
Android 9; `NEW_OUTGOING_CALL` is gone since Android 10). A decoy app is the one approach that
works everywhere, unrooted, with no special privileges — which is why real "vault" apps use it.

## How it works
1. The launcher icon + name are an ordinary to-do app ("wow todo").
2. Opening it shows a real, usable task list (`TodoScreen`), persisted locally. Add / check /
   swipe-to-delete all behave normally, so nothing looks off.
3. To open the hidden chat, type the **secret code** into the "Add a task" field and submit.
   - If it matches, the chat opens (`VaultShell` → the encrypted messenger) and the text is
     **not** saved as a task.
   - Anything else is added as a normal task.
4. Inside the chat, **Privacy → Lock now** returns to the to-do screen. Screenshot protection
   (`FLAG_SECURE`) is on only while the chat is open, so the decoy itself looks normal.

## The secret code
- Seeded on first run from the build-time `ACCESS_CODE` (`--dart-define=ACCESS_CODE=...`).
- Stored only as a **salted SHA-256 hash** in Keystore-backed secure storage — never plaintext.
- The user can change it in **Privacy → Change secret code**.
- It can be digits or any text (e.g. a phrase that looks like a real task is good camouflage).

## What this hides — and what it doesn't
- ✅ No visible "chat app"; the icon and app name are a to-do app.
- ✅ Works on all modern Android, unrooted, no suspicious permissions.
- ❌ The app still appears in *Settings → Apps* as "wow todo" (its real package name is
  visible there too; rename the package/label before release if you want).
- ❌ A decoy is camouflage, not a cryptographic boundary. Security comes from the E2E
  encryption + encrypted local DB; the decoy just keeps the chat from being obvious.

## Ideas to harden the decoy later
- A **second "panic" code** that opens an empty/clean chat account.
- A **duress code** that wipes the vault.
- Make the unlock gesture less guessable (e.g. a specific task text, or a long-press flow)
  if typing a bare code feels too discoverable.
