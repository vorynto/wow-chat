import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

/// Create an account (or sign in) with email + a one-time code. No password.
/// Entering a new email creates the account; the emailed code verifies it.
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
  int _resendIn = 0;
  Timer? _timer;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _resendIn = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() { _busy = true; _error = null; });
    try {
      await action();
    } catch (e) {
      setState(() => _error = _humanize(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _humanize(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('expired') || s.contains('invalid') || s.contains('otp_expired')) {
      return 'That code has expired or was already used. Tap “Resend code” to get a new one, '
          'then enter it promptly (don’t open any link in the email).';
    }
    if (s.contains('rate') || s.contains('limit') || s.contains('429')) {
      return 'Too many attempts. Wait a minute and try again.';
    }
    if (s.contains('email') && s.contains('not') && s.contains('allow')) {
      return 'Sign-ups are disabled for this project. Enable them in Supabase → Auth → Email.';
    }
    return e.toString();
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (!_emailRe.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    await _run(() async {
      await ref.read(authServiceProvider).sendEmailOtp(email);
      setState(() => _codeSent = true);
      _startCooldown();
    });
  }

  Future<void> _verify() async {
    await _run(() async {
      await ref.read(authServiceProvider).verifyEmailOtp(_email.text, _code.text);
      // AuthGate reacts to the auth state change and moves to onboarding automatically.
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: Container(
        width: double.infinity,
        decoration: AppTheme.heroGradient(context),
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _codeSent ? 'Enter the 6-digit code we emailed you' : 'Sign up or sign in with your email',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _codeSent
                  ? 'Sent to ${_email.text.trim()}. New email = new account.'
                  : "We'll email a one-time code. No password needed.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _email,
              enabled: !_codeSent,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                // Supabase OTP length is configurable (6–10 digits); don't cap it.
                decoration: const InputDecoration(
                  labelText: 'Verification code',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : (_codeSent ? _verify : _sendCode),
              child: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_codeSent ? 'Verify & continue' : 'Send code'),
            ),
            if (_codeSent) ...[
              TextButton(
                onPressed: (_busy || _resendIn > 0) ? null : _sendCode,
                child: Text(_resendIn > 0 ? 'Resend code in ${_resendIn}s' : 'Resend code'),
              ),
              TextButton(
                onPressed: _busy ? null : () => setState(() { _codeSent = false; _code.clear(); }),
                child: const Text('Use a different email'),
              ),
            ],
          ],
        ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.1),
        ),
      ),
    );
  }
}
