import 'package:flutter/material.dart';

import 'core/storage/first_run.dart';
import 'core/theme/app_theme.dart';
import 'features/decoy/todo_screen.dart';
import 'features/decoy/vault_shell.dart';
import 'features/onboarding/welcome_screen.dart';

/// Root widget. On the very first launch it shows a one-time welcome that explains the
/// disguised-messenger concept and lets the owner set their secret code, then drops them into
/// signup. On every later launch it opens straight to the "wow todo" decoy; entering the
/// secret code there reveals the hidden chat.
class WowChatApp extends StatelessWidget {
  const WowChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'wow todo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const _RootGate(),
    );
  }
}

class _RootGate extends StatefulWidget {
  const _RootGate();
  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  bool? _done;

  @override
  void initState() {
    super.initState();
    FirstRun.isDone().then((v) => mounted ? setState(() => _done = v) : null);
  }

  Future<void> _finishWelcome() async {
    await FirstRun.markDone();
    if (!mounted) return;
    setState(() => _done = true); // behind the push, the gate now shows the decoy
    // Take the owner straight into signup / account setup.
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VaultShell()));
  }

  @override
  Widget build(BuildContext context) {
    if (_done == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_done!) {
      return WelcomeScreen(onFinished: _finishWelcome);
    }
    return const TodoScreen();
  }
}
