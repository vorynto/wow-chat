import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';

/// Screenshot / recents protection for the hidden chat. Applied while the vault is open and
/// cleared when the user returns to the To-Do decoy (see VaultShell).
class StealthGate {
  StealthGate._();

  /// Block screenshots and hide content in the app switcher / recents preview.
  static Future<void> enableSecureFlag() async {
    await FlutterWindowManagerPlus.addFlags(FlutterWindowManagerPlus.FLAG_SECURE);
  }

  static Future<void> disableSecureFlag() async {
    await FlutterWindowManagerPlus.clearFlags(FlutterWindowManagerPlus.FLAG_SECURE);
  }
}
