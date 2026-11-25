import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// First run after sign-in: either create a new tenant (workspace) or join one with an
/// invite code. On success we publish the device's Signal keys and enter the app.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _joining = true; // join vs create
  final _slug = TextEditingController();
  final _invite = TextEditingController();
  final _name = TextEditingController();
  final _handle = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      final auth = ref.read(authServiceProvider);
      if (_joining) {
        await auth.joinTenant(
          slug: _slug.text.trim(),
          inviteCode: _invite.text.trim(),
          handle: _handle.text.trim(),
        );
      } else {
        await auth.createTenant(
          slug: _slug.text.trim(),
          name: _name.text.trim(),
          handle: _handle.text.trim(),
        );
      }
      if (mounted) setState(() {}); // AuthGate re-evaluates hasProfile()
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Join')),
                ButtonSegment(value: false, label: Text('Create')),
              ],
              selected: {_joining},
              onSelectionChanged: (s) => setState(() => _joining = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _slug,
              decoration: const InputDecoration(labelText: 'Tenant code (slug)'),
            ),
            if (_joining)
              TextField(
                controller: _invite,
                decoration: const InputDecoration(labelText: 'Invite code'),
              )
            else
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Workspace name'),
              ),
            TextField(
              controller: _handle,
              decoration: const InputDecoration(labelText: 'Your handle'),
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_joining ? 'Join tenant' : 'Create tenant'),
            ),
          ],
        ),
      ),
    );
  }
}
