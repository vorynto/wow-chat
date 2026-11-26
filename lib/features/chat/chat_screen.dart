import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../calls/call_screen.dart';
import 'models.dart';

/// A 1:1 encrypted conversation. Streams messages and sends E2E-encrypted text.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherDeviceId,
    required this.title,
  });

  final String conversationId;
  final String otherUserId;
  final String otherDeviceId;
  final String title;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  bool _sending = false;

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final repo = ref.read(chatRepositoryProvider);
      final ttl = (await ref.read(privacyRepositoryProvider).load()).defaultMsgTtlSec;
      await repo.sendText(
        conversationId: widget.conversationId,
        otherUserId: widget.otherUserId,
        otherDeviceId: widget.otherDeviceId,
        text: text,
        ttlSec: ttl,
      );
      _input.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Send failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startCall({required bool video}) async {
    final calls = ref.read(callServiceProvider);
    await calls.init();
    await calls.startCall(
      conversationId: widget.conversationId,
      peerUserId: widget.otherUserId,
      peerDeviceId: widget.otherDeviceId,
      video: video,
    );
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CallScreen(service: calls, title: widget.title),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.read(supabaseServiceProvider).currentUser?.id;
    final repo = ref.read(chatRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () => _startCall(video: false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () => _startCall(video: true),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: repo.watchMessages(
                conversationId: widget.conversationId,
                otherUserId: widget.otherUserId,
                otherDeviceId: widget.otherDeviceId,
              ),
              builder: (context, snap) {
                final msgs = snap.data ?? const <ChatMessage>[];
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[i];
                    final mine = m.senderId == me;
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: mine ? Colors.teal.shade700 : Colors.grey.shade800,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          m.decryptFailed
                              ? '[unable to decrypt]'
                              : (m.text ?? (mine ? '[sent]' : '…')),
                        ),
                      ),
                    );
                  },
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
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: _sending
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                    onPressed: _sending ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
