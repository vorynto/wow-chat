import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'chat_screen.dart';

/// Pick a tenant member to start an encrypted 1:1 chat with.
class NewChatScreen extends ConsumerWidget {
  const NewChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(chatRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('New chat')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: repo.listContacts(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final contacts = snap.data!;
          if (contacts.isEmpty) {
            return const Center(child: Text('No other members in your tenant yet.'));
          }
          return ListView.builder(
            itemCount: contacts.length,
            itemBuilder: (_, i) {
              final c = contacts[i];
              final handle = c['handle'] as String? ?? '(unknown)';
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(c['display_name'] as String? ?? handle),
                subtitle: Text('@$handle'),
                onTap: () async {
                  final otherId = c['id'] as String;
                  final deviceId = await repo.primaryDeviceId(otherId);
                  if (deviceId == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('That user has no registered device yet.')),
                      );
                    }
                    return;
                  }
                  final convId = await repo.startDirectConversation(otherId);
                  if (!context.mounted) return;
                  Navigator.of(context).pushReplacement(MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      conversationId: convId,
                      otherUserId: otherId,
                      otherDeviceId: deviceId,
                      title: '@$handle',
                    ),
                  ));
                },
              );
            },
          );
        },
      ),
    );
  }
}
