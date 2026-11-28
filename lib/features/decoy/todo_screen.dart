import 'package:flutter/material.dart';

import '../../core/storage/access_code.dart';
import '../../core/storage/wipe_service.dart';
import 'todo_store.dart';
import 'vault_shell.dart';

/// The decoy: a fully working "wow todo" list. The hidden chat is reached by typing the
/// secret code into the add-task box and submitting — if it matches, the chat opens instead
/// of a task being added. Any other text is added as a normal task. No biometrics involved.
class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});
  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  final _store = TodoStore();
  final _input = TextEditingController();
  List<TodoItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _store.load();
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  Future<void> _submit() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;

    // Panic code: silently wipe everything local, then behave exactly like a normal task add
    // so there is no visible signal that anything happened.
    if (await AccessCodeService.instance.verifyPanic(text)) {
      await WipeService.wipeEverything();
      setState(() {
        _items.add(TodoItem(id: DateTime.now().microsecondsSinceEpoch.toString(), title: text));
        _input.clear();
      });
      await _store.save(_items);
      return;
    }

    // Secret unlock: if the entered text is the access code, open the hidden chat and do NOT
    // store it as a task.
    if (await AccessCodeService.instance.verify(text)) {
      _input.clear();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const VaultShell()),
      );
      return; // back here (the to-do list) after the vault is closed
    }

    setState(() {
      _items.add(TodoItem(id: DateTime.now().microsecondsSinceEpoch.toString(), title: text));
      _input.clear();
    });
    await _store.save(_items);
  }

  Future<void> _toggle(TodoItem it) async {
    setState(() => it.done = !it.done);
    await _store.save(_items);
  }

  Future<void> _delete(TodoItem it) async {
    setState(() => _items.remove(it));
    await _store.save(_items);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('wow todo')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _items.isEmpty
                      ? const Center(child: Text('No tasks yet. Add one below.'))
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final it = _items[i];
                            return Dismissible(
                              key: ValueKey(it.id),
                              onDismissed: (_) => _delete(it),
                              background: Container(color: Colors.red.shade900),
                              child: CheckboxListTile(
                                value: it.done,
                                onChanged: (_) => _toggle(it),
                                title: Text(
                                  it.title,
                                  style: TextStyle(
                                    decoration: it.done ? TextDecoration.lineThrough : null,
                                    color: it.done ? Colors.grey : null,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            decoration: const InputDecoration(
                              hintText: 'Add a task',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.add), onPressed: _submit),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
