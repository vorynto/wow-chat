import 'package:flutter/material.dart';
import 'features/decoy/todo_screen.dart';

/// Root widget. On the surface this is "wow todo", an ordinary to-do app. Entering the secret
/// code inside it opens the hidden chat (see TodoScreen -> VaultShell -> AuthGate).
class WowChatApp extends StatelessWidget {
  const WowChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'wow todo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const TodoScreen(),
    );
  }
}
