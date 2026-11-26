import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/storage/access_code.dart';
import '../stealth/stealth_gate.dart';
import 'privacy_settings.dart';

/// The user-facing privacy control panel. Every toggle persists to Supabase (RLS: own row
/// only) and some apply native effects immediately (screenshot block, launcher disguise).
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});
  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  PrivacySettings? _s;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await ref.read(privacyRepositoryProvider).load();
    if (mounted) setState(() => _s = s);
  }

  Future<void> _changeCode() async {
    final controller = TextEditingController();
    final newCode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New secret code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.visiblePassword,
          decoration: const InputDecoration(hintText: 'Enter a new code'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newCode != null && newCode.isNotEmpty) {
      await AccessCodeService.instance.setCode(newCode);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Secret code updated')),
        );
      }
    }
  }

  Future<void> _update(PrivacySettings next) async {
    setState(() => _s = next);
    await ref.read(privacyRepositoryProvider).save(next);
    // Apply native side-effects.
    if (next.blockScreenshots) {
      await StealthGate.enableSecureFlag();
    } else {
      await StealthGate.disableSecureFlag();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const _Section('Visibility'),
                SwitchListTile(
                  title: const Text('Last seen'),
                  subtitle: const Text('Let others see when you were online'),
                  value: s.lastSeenVisible,
                  onChanged: (v) => _update(s.copyWith(lastSeenVisible: v)),
                ),
                SwitchListTile(
                  title: const Text('Read receipts'),
                  value: s.readReceipts,
                  onChanged: (v) => _update(s.copyWith(readReceipts: v)),
                ),
                SwitchListTile(
                  title: const Text('Typing indicators'),
                  value: s.typingIndicators,
                  onChanged: (v) => _update(s.copyWith(typingIndicators: v)),
                ),
                ListTile(
                  title: const Text('Profile photo visible to'),
                  trailing: DropdownButton<PhotoScope>(
                    value: s.profilePhotoScope,
                    onChanged: (v) => v == null ? null : _update(s.copyWith(profilePhotoScope: v)),
                    items: const [
                      DropdownMenuItem(value: PhotoScope.everyone, child: Text('Everyone')),
                      DropdownMenuItem(value: PhotoScope.contacts, child: Text('Contacts')),
                      DropdownMenuItem(value: PhotoScope.nobody, child: Text('Nobody')),
                    ],
                  ),
                ),
                const _Section('Messages'),
                ListTile(
                  title: const Text('Disappearing messages'),
                  subtitle: Text(s.defaultMsgTtlSec == 0
                      ? 'Off'
                      : 'Delete after ${s.defaultMsgTtlSec ~/ 3600}h'),
                  trailing: DropdownButton<int>(
                    value: s.defaultMsgTtlSec,
                    onChanged: (v) => v == null ? null : _update(s.copyWith(defaultMsgTtlSec: v)),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Off')),
                      DropdownMenuItem(value: 3600, child: Text('1 hour')),
                      DropdownMenuItem(value: 86400, child: Text('1 day')),
                      DropdownMenuItem(value: 604800, child: Text('1 week')),
                    ],
                  ),
                ),
                const _Section('Device security'),
                SwitchListTile(
                  title: const Text('Block screenshots'),
                  subtitle: const Text('Hide content in screenshots and recents'),
                  value: s.blockScreenshots,
                  onChanged: (v) => _update(s.copyWith(blockScreenshots: v)),
                ),
                const _Section('Access'),
                ListTile(
                  leading: const Icon(Icons.password),
                  title: const Text('Change secret code'),
                  subtitle: const Text('The code typed in the To-Do app to open chat'),
                  onTap: _changeCode,
                ),
                ListTile(
                  leading: const Icon(Icons.lock),
                  title: const Text('Lock now'),
                  subtitle: const Text('Return to the To-Do screen'),
                  onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
                ),
                const _Section('Account'),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign out'),
                  onTap: () => ref.read(authServiceProvider).signOut(),
                ),
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.tealAccent)),
      );
}
