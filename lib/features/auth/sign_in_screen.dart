import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Passwordless email OTP sign-in. No password stored anywhere; no phone number required.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() { _busy = true; _error = null; });
    try {
      await action();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _email,
              enabled: !_codeSent,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'One-time code'),
              ),
            ],
            const SizedBox(height: 24),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        if (!_codeSent) {
                          await auth.sendEmailOtp(_email.text);
                          setState(() => _codeSent = true);
                        } else {
                          await auth.verifyEmailOtp(_email.text, _code.text);
                          // AuthGate reacts to the auth state change automatically.
                        }
                      }),
              child: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_codeSent ? 'Verify' : 'Send code'),
            ),
            if (_codeSent)
              TextButton(
                onPressed: _busy ? null : () => setState(() => _codeSent = false),
                child: const Text('Use a different email'),
              ),
          ],
        ),
      ),
    );
  }
}
