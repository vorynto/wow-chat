import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// A genuinely working local to-do list. This is the decoy surface: it behaves like a real
/// app so nothing hints at the hidden chat. Data is plain (non-secret) local JSON.
class TodoItem {
  TodoItem({required this.id, required this.title, this.done = false});
  final String id;
  String title;
  bool done;

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'done': done};
  factory TodoItem.fromJson(Map<String, dynamic> j) =>
      TodoItem(id: j['id'] as String, title: j['title'] as String, done: j['done'] as bool? ?? false);
}

class TodoStore {
  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/todos.json');
  }

  Future<List<TodoItem>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return _seed();
      final raw = await f.readAsString();
      return (jsonDecode(raw) as List)
          .map((e) => TodoItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return _seed();
    }
  }

  Future<void> save(List<TodoItem> items) async {
    final f = await _file();
    await f.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  // A believable starter list on first launch.
  List<TodoItem> _seed() => [
        TodoItem(id: 'a', title: 'Buy groceries'),
        TodoItem(id: 'b', title: 'Pay electricity bill'),
        TodoItem(id: 'c', title: 'Call the plumber'),
        TodoItem(id: 'd', title: 'Finish monthly report', done: true),
      ];
}
