import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/storage/access_code.dart';
import '../../core/theme/app_theme.dart';

/// One-time first-run welcome. Explains the disguised-messenger concept to the owner and lets
/// them set their own secret code (and optional panic code). Shown only on first launch; after
/// this the app opens straight to the "wow todo" decoy.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onFinished});
  final VoidCallback onFinished;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _code = TextEditingController();
  final _confirm = TextEditingController();
  final _panic = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _finish() async {
    final code = _code.text.trim();
    final confirm = _confirm.text.trim();
    final panic = _panic.text.trim();

    if (code.length < 4) {
      setState(() => _error = 'Choose a secret code of at least 4 characters.');
      return;
    }
    if (code != confirm) {
      setState(() => _error = 'The secret codes do not match.');
      return;
    }
    if (panic.isNotEmpty && panic == code) {
      setState(() => _error = 'The panic code must be different from your secret code.');
      return;
    }

    setState(() { _busy = true; _error = null; });
    try {
      await AccessCodeService.instance.setCode(code);
      if (panic.isNotEmpty) {
        await AccessCodeService.instance.setPanicCode(panic);
      }
      widget.onFinished();
    } catch (e) {
      setState(() { _error = e.toString(); _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Container(
        decoration: AppTheme.heroGradient(context),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Icon(Icons.shield_moon_outlined, size: 56, color: AppTheme.accent)
                    .animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.6, 0.6)),
                const SizedBox(height: 16),
                Text('Welcome to wow todo', style: t.headlineSmall)
                    .animate().fadeIn(delay: 150.ms, duration: 400.ms).slideY(begin: 0.2),
                const SizedBox(height: 12),
                Text(
                  'On the outside this is an ordinary to-do app. Hidden behind it is your private, '
                  'end-to-end encrypted messenger, calls and photo vault.',
                  style: t.bodyMedium,
                ).animate().fadeIn(delay: 250.ms, duration: 400.ms),
                const SizedBox(height: 20),
                const _Step(
                  n: '1',
                  title: 'Set a secret code',
                  body: 'Only you know it. You will type it into the “Add a task” box to open the '
                      'hidden app. Pick something you will remember — there is no recovery.',
                ).animate().fadeIn(delay: 350.ms).slideX(begin: 0.15),
                const _Step(
                  n: '2',
                  title: 'Create your account',
                  body: 'Next you will sign up with your email and a one-time code, then join or '
                      'create a workspace.',
                ).animate().fadeIn(delay: 450.ms).slideX(begin: 0.15),
                const _Step(
                  n: '3',
                  title: 'Get back in anytime',
                  body: 'Open wow todo, type your secret code in the “Add a task” box, and submit. '
                      'To outsiders it just looks like a to-do list.',
                ).animate().fadeIn(delay: 550.ms).slideX(begin: 0.15),
                const SizedBox(height: 20),
              TextField(
                controller: _code,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Secret code',
                  helperText: 'At least 4 characters. Digits or text.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm secret code',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _panic,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Panic code (optional)',
                  helperText: 'Typing this later silently wipes everything. Leave blank to skip.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _finish,
                  child: _busy
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Set code & continue'),
                ),
              ).animate().fadeIn(delay: 650.ms).slideY(begin: 0.3),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title, required this.body});
  final String n;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 14, child: Text(n)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleMedium),
                const SizedBox(height: 2),
                Text(body, style: t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
