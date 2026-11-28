import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'group_chat_screen.dart';

/// Create a group: name it and pick members from the tenant.
class NewGroupScreen extends ConsumerStatefulWidget {
  const NewGroupScreen({super.key});
  @override
  ConsumerState<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends ConsumerState<NewGroupScreen> {
  final _title = TextEditingController();
  final _selected = <String>{};
  List<Map<String, dynamic>> _contacts = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await ref.read(chatRepositoryProvider).listContacts();
    if (mounted) setState(() { _contacts = c; _loading = false; });
  }

  Future<void> _create() async {
    if (_title.text.trim().isEmpty || _selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      final convId = await ref
          .read(groupRepositoryProvider)
          .createGroup(_title.text.trim(), _selected.toList());
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => GroupChatScreen(conversationId: convId, title: _title.text.trim()),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New group'),
        actions: [
          IconButton(
            icon: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            onPressed: _busy ? null : _create,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _title,
                    decoration: const InputDecoration(labelText: 'Group name'),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final c in _contacts)
                        CheckboxListTile(
                          value: _selected.contains(c['id']),
                          title: Text(c['display_name'] as String? ?? (c['handle'] as String? ?? '?')),
                          subtitle: Text('@${c['handle']}'),
                          onChanged: (v) => setState(() {
                            final id = c['id'] as String;
                            if (v == true) {
                              _selected.add(id);
                            } else {
                              _selected.remove(id);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
