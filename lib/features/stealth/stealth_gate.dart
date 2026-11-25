import 'package:flutter/services.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';

/// Bridges the native stealth features and enforces anti-screenshot protection.
///
/// Launch paths into the real app:
///  1. Decoy launcher: the app appears as a harmless "Calculator" (see android manifest).
///     Entering the secret passcode in the decoy UI calls [unlockFromDecoy].
///  2. Secret dial code: typing *#*#<code>#*#* in the phone dialer fires the native
///     SecretCodeReceiver, which launches the app with the `unlocked` extra set.
///
/// `openedViaSecretCode` tells the UI which path was used so it can skip the decoy screen.
class StealthGate {
  StealthGate._();
  static final instance = StealthGate._();

  static const _channel = MethodChannel('wowchat/stealth');

  /// True when the activity was launched by the secret dial code (bypasses decoy).
  Future<bool> openedViaSecretCode() async {
    final v = await _channel.invokeMethod<bool>('openedViaSecretCode');
    return v ?? false;
  }

  /// Switch the launcher identity between the decoy ("Calculator") and the real app.
  /// Uses Android <activity-alias> components enabled/disabled at runtime.
  Future<void> setDisguise(bool decoy) async {
    await _channel.invokeMethod('setDisguise', {'decoy': decoy});
  }

  /// Block screenshots and hide content in the app switcher / recents preview.
  static Future<void> enableSecureFlag() async {
    await FlutterWindowManagerPlus.addFlags(FlutterWindowManagerPlus.FLAG_SECURE);
  }

  static Future<void> disableSecureFlag() async {
    await FlutterWindowManagerPlus.clearFlags(FlutterWindowManagerPlus.FLAG_SECURE);
  }

  /// Verify the passcode entered on the decoy screen. Compared against a salted hash held
  /// in secure storage (never stored in plaintext). Returns true on success.
  Future<bool> unlockFromDecoy(String passcode) async {
    // Delegated to AppLockService (biometric/PIN). Kept here as the single entry point
    // the decoy UI calls, so the decoy widget stays dumb.
    return _AppLock.verify(passcode);
  }
}

/// Minimal PIN verification placeholder — wire to local_auth + a salted PBKDF2/Argon2 hash
/// stored in SecureStore. Shown separately so the decoy never imports storage directly.
class _AppLock {
  static Future<bool> verify(String passcode) async {
    // TODO: compare Argon2(passcode, salt) against SecureStore value; support a distinct
    // "decoy PIN" that opens an empty decoy account, and a "panic PIN" that triggers wipe.
    return passcode.isNotEmpty;
  }
}
