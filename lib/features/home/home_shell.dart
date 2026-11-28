import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../privacy/privacy_screen.dart';
import '../chat/models.dart';
import '../chat/new_chat_screen.dart';
import '../chat/new_group_screen.dart';
import '../chat/group_chat_screen.dart';
import '../calls/call_service.dart';
import '../calls/call_screen.dart';
import '../gallery/gallery_screen.dart';

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
    GalleryScreen(),
    PrivacyScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _calls = ref.read(callServiceProvider);
    _calls!.init();
    _calls!.state.addListener(_onCallState);
    // Process incoming group sender-key distributions as they arrive.
    ref.read(groupRepositoryProvider).startSkdmListener();
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
          NavigationDestination(icon: Icon(Icons.photo_library_outlined), label: 'Gallery'),
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
            itemBuilder: (_, i) {
              final c = convs[i];
              return ListTile(
                leading: CircleAvatar(child: Icon(c.isGroup ? Icons.group : Icons.lock)),
                title: Text(c.isGroup ? 'Group' : 'Direct chat'),
                subtitle: Text('Encrypted • ${c.createdAt.toLocal()}'),
                onTap: c.isGroup
                    ? () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => GroupChatScreen(conversationId: c.id, title: 'Group'),
                        ))
                    // Opening a 1:1 needs the peer's device; use New chat for now.
                    : null,
              );
            },
          );
        },
      ),
      floatingActionButton: Builder(
        builder: (ctx) => FloatingActionButton(
          onPressed: () => showModalBottomSheet<void>(
            context: ctx,
            builder: (_) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.person_add),
                    title: const Text('New chat'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const NewChatScreen()),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.group_add),
                    title: const Text('New group'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const NewGroupScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          child: const Icon(Icons.edit),
        ),
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
