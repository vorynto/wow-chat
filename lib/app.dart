import 'package:flutter/material.dart';
import 'features/stealth/stealth_gate.dart';
import 'features/auth/auth_gate.dart';

/// Root widget. The app has no launcher icon and is reached only via the secret dial code
/// (or a dev launcher). On open it locks behind biometrics/PIN, then routes to the app.
class WowChatApp extends StatelessWidget {
  const WowChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'wow-chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const AppLockGate(),
    );
  }
}

/// Requires biometric / device-credential unlock before revealing anything. This is the
/// second line of defense after the app being hidden; a found, unlocked phone still can't
/// open wow-chat without the user's biometric or PIN.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key});
  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  bool _unlocked = false;
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    _unlock();
  }

  Future<void> _unlock() async {
    final ok = await StealthGate.instance.authenticate();
    if (mounted) setState(() { _unlocked = ok; _tried = true; });
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return const AuthGate();
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 16),
            Text(_tried ? 'Locked' : 'Unlocking…'),
            const SizedBox(height: 16),
            if (_tried)
              FilledButton(onPressed: _unlock, child: const Text('Unlock')),
          ],
        ),
      ),
    );
  }
}
