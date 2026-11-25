import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
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
                SwitchListTile(
                  title: const Text('App lock'),
                  subtitle: const Text('Require biometrics / PIN to open'),
                  value: s.appLock,
                  onChanged: (v) => _update(s.copyWith(appLock: v)),
                ),
                ListTile(
                  leading: const Icon(Icons.dialpad),
                  title: const Text('App is hidden'),
                  subtitle: const Text('No launcher icon. Open by dialing your secret code.'),
                  trailing: const Icon(Icons.check_circle, color: Colors.tealAccent),
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
