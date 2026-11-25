import 'package:flutter/material.dart';
import 'features/stealth/stealth_gate.dart';
import 'features/auth/auth_gate.dart';

/// Root widget. Shows the decoy calculator unless the app was opened via the secret dial
/// code (or the user has just unlocked). A correct passcode reveals the real app.
class WowChatApp extends StatelessWidget {
  const WowChatApp({super.key, required this.openedViaSecretCode});
  final bool openedViaSecretCode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calculator', // decoy title, shown in recents if FLAG_SECURE is off
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: openedViaSecretCode ? const AuthGate() : const DecoyCalculator(),
      // After decoy unlock or secret-code entry, AuthGate routes to sign-in / onboarding / home.
    );
  }
}

/// A working-looking calculator that doubles as the lock screen. Typing the secret passcode
/// and pressing "=" unlocks the real app instead of computing.
class DecoyCalculator extends StatefulWidget {
  const DecoyCalculator({super.key});
  @override
  State<DecoyCalculator> createState() => _DecoyCalculatorState();
}

class _DecoyCalculatorState extends State<DecoyCalculator> {
  String _display = '0';

  void _tap(String k) {
    setState(() {
      if (k == 'C') {
        _display = '0';
      } else if (k == '=') {
        _tryUnlock();
      } else {
        _display = _display == '0' ? k : _display + k;
      }
    });
  }

  Future<void> _tryUnlock() async {
    final ok = await StealthGate.instance.unlockFromDecoy(_display);
    if (ok && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthGate()),
      );
    } else {
      // Behave like a real calculator on a wrong code so nothing is given away.
      setState(() => _display = '0');
    }
  }

  @override
  Widget build(BuildContext context) {
    const keys = ['7','8','9','C','4','5','6','=','1','2','3','0'];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                alignment: Alignment.bottomRight,
                padding: const EdgeInsets.all(24),
                child: Text(_display, style: const TextStyle(fontSize: 56)),
              ),
            ),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              childAspectRatio: 1.4,
              children: [
                for (final k in keys)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: FilledButton.tonal(
                      onPressed: () => _tap(k),
                      child: Text(k, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

