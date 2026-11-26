import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../privacy/privacy_screen.dart';
import '../chat/models.dart';
import '../chat/new_chat_screen.dart';
import '../calls/call_service.dart';
import '../calls/call_screen.dart';

/// Main app shell once signed in + onboarded. Chats / Calls / Settings.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  CallService? _calls;

  static const _pages = [
    _ChatsTab(),
    _CallsTab(),
    PrivacyScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _calls = ref.read(callServiceProvider);
    _calls!.init();
    _calls!.state.addListener(_onCallState);
  }

  void _onCallState() {
    // Surface an incoming call full-screen.
    if (_calls!.state.value == CallState.ringing && mounted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CallScreen(service: _calls!, title: 'Incoming', incoming: true),
      ));
    }
  }

  @override
  void dispose() {
    _calls?.state.removeListener(_onCallState);
    super.dispose();
  }

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

class _ChatsTab extends ConsumerWidget {
  const _ChatsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(chatRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: FutureBuilder<List<Conversation>>(
        future: repo.listConversations(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final convs = snap.data!;
          if (convs.isEmpty) {
            return const Center(child: Text('No conversations yet. Tap + to start one.'));
          }
          return ListView.builder(
            itemCount: convs.length,
            itemBuilder: (_, i) => ListTile(
              leading: const CircleAvatar(child: Icon(Icons.lock)),
              title: Text(convs[i].isGroup ? 'Group' : 'Direct chat'),
              subtitle: Text('Encrypted • ${convs[i].createdAt.toLocal()}'),
              // Opening a conversation needs the other member's device; resolved via NewChat
              // for now. A conversation->member lookup will replace this in the next step.
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NewChatScreen()),
        ),
        child: const Icon(Icons.edit),
      ),
    );
  }
}

class _CallsTab extends StatelessWidget {
  const _CallsTab();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Calls')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Start an encrypted call from inside a chat (phone / video icons). '
              'Incoming calls ring here automatically.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
}
