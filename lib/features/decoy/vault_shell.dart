import 'package:flutter/material.dart';

import '../stealth/stealth_gate.dart';
import '../auth/auth_gate.dart';

/// Wraps the hidden chat app. Turns on screenshot protection (FLAG_SECURE) while the vault is
/// open and clears it when the user returns to the To-Do decoy, so the decoy itself looks
/// like an ordinary app (a to-do app that blocks screenshots would be a tell).
class VaultShell extends StatefulWidget {
  const VaultShell({super.key});
  @override
  State<VaultShell> createState() => _VaultShellState();
}

class _VaultShellState extends State<VaultShell> {
  @override
  void initState() {
    super.initState();
    StealthGate.enableSecureFlag();
  }

  @override
  void dispose() {
    StealthGate.disableSecureFlag();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Back from the vault returns to the decoy (pops this route).
    return const AuthGate();
  }
}
