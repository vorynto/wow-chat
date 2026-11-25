import 'package:flutter/services.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:local_auth/local_auth.dart';

/// Native stealth bridge + screenshot protection + app-lock.
///
/// The app has NO launcher icon. The only entry points are:
///  1. the secret dial code (native SecretCodeReceiver), and
///  2. in dev builds, the DevLauncher alias / `adb shell am start`.
///
/// Once open, [authenticate] gates the UI behind biometrics / device credential so a found
/// phone still can't read chats.
class StealthGate {
  StealthGate._();
  static final instance = StealthGate._();

  static const _channel = MethodChannel('wowchat/stealth');
  final _auth = LocalAuthentication();

  /// True when the activity was launched by the secret dial code.
  Future<bool> openedViaSecretCode() async {
    try {
      return await _channel.invokeMethod<bool>('openedViaSecretCode') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Block screenshots and hide content in the app switcher / recents preview.
  static Future<void> enableSecureFlag() async {
    await FlutterWindowManagerPlus.addFlags(FlutterWindowManagerPlus.FLAG_SECURE);
  }

  static Future<void> disableSecureFlag() async {
    await FlutterWindowManagerPlus.clearFlags(FlutterWindowManagerPlus.FLAG_SECURE);
  }

  /// App-lock: require biometrics or device credential (PIN/pattern) before showing the app.
  /// Returns true on success. If the device has no biometrics/credential enrolled, this
  /// returns true (nothing to check) so the user isn't locked out — the hidden-entry + secret
  /// code are still the outer defense.
  Future<bool> authenticate() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return true;
      return await _auth.authenticate(
        localizedReason: 'Unlock',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
