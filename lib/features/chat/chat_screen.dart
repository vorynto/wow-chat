import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

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

  Widget _bubbleContent(ChatMessage m, bool mine) {
    if (m.decryptFailed) return const Text('[unable to decrypt]');

    // Media message: body is JSON with the file name/type/key.
    if (m.mediaPath != null && m.text != null) {
      String name = 'file';
      String caption = '';
      try {
        final meta = jsonDecode(m.text!) as Map<String, dynamic>;
        name = meta['name'] as String? ?? 'file';
        caption = meta['caption'] as String? ?? '';
      } catch (_) {}
      return InkWell(
        onTap: () => _openMedia(m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.insert_drive_file, size: 20),
              const SizedBox(width: 6),
              Flexible(child: Text(name)),
              const SizedBox(width: 6),
              const Icon(Icons.download, size: 16),
            ]),
            if (caption.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(caption),
            ),
          ],
        ),
      );
    }

    return Text(m.text ?? (mine ? '[sent]' : '…'));
  }

  Future<void> _attach() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    if (f.bytes == null) return;
    setState(() => _sending = true);
    try {
      final repo = ref.read(chatRepositoryProvider);
      final ttl = (await ref.read(privacyRepositoryProvider).load()).defaultMsgTtlSec;
      await repo.sendMedia(
        conversationId: widget.conversationId,
        otherUserId: widget.otherUserId,
        otherDeviceId: widget.otherDeviceId,
        fileName: f.name,
        mimeType: _mimeFor(f.extension),
        bytes: f.bytes!,
        ttlSec: ttl,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Attach failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _mimeFor(String? ext) => switch ((ext ?? '').toLowerCase()) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        'mp4' => 'video/mp4',
        'pdf' => 'application/pdf',
        _ => 'application/octet-stream',
      };

  Future<void> _openMedia(ChatMessage m) async {
    if (m.text == null || m.mediaPath == null) return;
    try {
      final repo = ref.read(chatRepositoryProvider);
      final (name, _, bytes) = await repo.downloadMedia(
        mediaPath: m.mediaPath!,
        decryptedBody: m.text!,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes);
      await OpenFilex.open(file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Open failed: $e')));
      }
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
                        child: _bubbleContent(m, mine),
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
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _sending ? null : _attach,
                  ),
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
