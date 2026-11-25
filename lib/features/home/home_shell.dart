import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../privacy/privacy_screen.dart';

/// Main app shell once signed in + onboarded. Chats / Calls / Settings.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _pages = [
    _ChatsTab(),
    _CallsTab(),
    PrivacyScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.call_outlined), label: 'Calls'),
          NavigationDestination(icon: Icon(Icons.lock_outline), label: 'Privacy'),
        ],
      ),
    );
  }
}

class _ChatsTab extends StatelessWidget {
  const _ChatsTab();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Chats')),
        body: const Center(child: Text('Conversations list — next build step.')),
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          child: const Icon(Icons.edit),
        ),
      );
}

class _CallsTab extends StatelessWidget {
  const _CallsTab();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Calls')),
        body: const Center(child: Text('Encrypted audio/video calls — next build step.')),
      );
}
