import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

import '../../core/providers.dart';
import '../calls/call_screen.dart';
import 'gif_picker_screen.dart';
import 'giphy_service.dart';
import 'message_content.dart';
import 'models.dart';

/// Built-in sticker set (large emoji glyphs; no art assets required, sent E2E as text).
const _stickers = [
  '😀','😂','😍','😎','😭','😡','👍','👎','🙏','👏','🔥','🎉','❤️','💔','💯','🤔',
  '🥳','😴','🤯','😅','🙈','🤝','💪','✌️','👀','🫶','😇','🤗','😏','🥲','🤩','😤',
];

/// A 1:1 encrypted conversation with emoji, stickers, GIFs and tagged replies.
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
  bool _showEmoji = false;
  ReplyRef? _replyTo;

  Future<int> get _ttl async =>
      (await ref.read(privacyRepositoryProvider).load()).defaultMsgTtlSec;

  void _setReply(ChatMessage m) {
    final preview = m.content?.previewText() ?? (m.text ?? '');
    setState(() => _replyTo = ReplyRef(id: m.id, preview: preview, sender: m.senderId));
  }

  void _clearReply() => setState(() => _replyTo = null);

  Future<void> _run(Future<void> Function(ReplyRef? reply, int ttl) action) async {
    final reply = _replyTo;
    setState(() => _sending = true);
    try {
      await action(reply, await _ttl);
      _clearReply();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final repo = ref.read(chatRepositoryProvider);
    await _run((reply, ttl) async {
      await repo.sendText(
        conversationId: widget.conversationId,
        otherUserId: widget.otherUserId,
        otherDeviceId: widget.otherDeviceId,
        text: text,
        replyTo: reply,
        ttlSec: ttl,
      );
      _input.clear();
    });
  }

  Future<void> _sendSticker(String sticker) async {
    final repo = ref.read(chatRepositoryProvider);
    await _run((reply, ttl) => repo.sendSticker(
          conversationId: widget.conversationId,
          otherUserId: widget.otherUserId,
          otherDeviceId: widget.otherDeviceId,
          sticker: sticker,
          replyTo: reply,
          ttlSec: ttl,
        ));
  }

  Future<void> _attach() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    if (res == null || res.files.isEmpty || res.files.first.bytes == null) return;
    final f = res.files.first;
    final repo = ref.read(chatRepositoryProvider);
    await _run((reply, ttl) => repo.sendMedia(
          conversationId: widget.conversationId,
          otherUserId: widget.otherUserId,
          otherDeviceId: widget.otherDeviceId,
          fileName: f.name,
          mimeType: _mimeFor(f.extension),
          bytes: f.bytes!,
          replyTo: reply,
          ttlSec: ttl,
        ));
  }

  Future<void> _sendGif() async {
    final url = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const GifPickerScreen()),
    );
    if (url == null) return;
    final repo = ref.read(chatRepositoryProvider);
    await _run((reply, ttl) async {
      final bytes = await GiphyService().download(url);
      await repo.sendMedia(
        conversationId: widget.conversationId,
        otherUserId: widget.otherUserId,
        otherDeviceId: widget.otherDeviceId,
        fileName: 'animated.gif',
        mimeType: 'image/gif',
        bytes: bytes,
        replyTo: reply,
        ttlSec: ttl,
      );
    });
  }

  Future<void> _pickSticker() async {
    final s = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: GridView.count(
          crossAxisCount: 6,
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          children: [
            for (final s in _stickers)
              InkWell(
                onTap: () => Navigator.of(context).pop(s),
                child: Center(child: Text(s, style: const TextStyle(fontSize: 30))),
              ),
          ],
        ),
      ),
    );
    if (s != null) await _sendSticker(s);
  }

  String _mimeFor(String? ext) => switch ((ext ?? '').toLowerCase()) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'mp4' => 'video/mp4',
        'pdf' => 'application/pdf',
        _ => 'application/octet-stream',
      };

  Future<void> _openFile(ChatMessage m) async {
    final c = m.content;
    if (c == null || m.mediaPath == null || c.mediaKey == null) return;
    try {
      final repo = ref.read(chatRepositoryProvider);
      final bytes = await repo.mediaBytes(m.id, m.mediaPath!, c.mediaKey!);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${c.mediaName ?? m.id}');
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

  // ───────────────────────── rendering ─────────────────────────
  Widget _replyQuote(ReplyRef r, String? me) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        border: const Border(left: BorderSide(color: Colors.tealAccent, width: 3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${r.sender == me ? 'You' : widget.title}: ${r.preview}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Colors.white70),
      ),
    );
  }

  Widget _mediaInline(ChatMessage m) {
    final c = m.content!;
    final repo = ref.read(chatRepositoryProvider);
    if (c.isImageLike) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220, maxWidth: 240),
        child: FutureBuilder<Uint8List>(
          future: repo.mediaBytes(m.id, m.mediaPath!, c.mediaKey!),
          builder: (_, snap) => snap.hasData
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true))
              : const SizedBox(height: 120, width: 120, child: Center(child: CircularProgressIndicator())),
        ),
      );
    }
    return InkWell(
      onTap: () => _openFile(m),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.insert_drive_file, size: 20),
        const SizedBox(width: 6),
        Flexible(child: Text(c.mediaName ?? 'File')),
        const SizedBox(width: 6),
        const Icon(Icons.download, size: 16),
      ]),
    );
  }

  Widget _body(ChatMessage m, bool mine, String? me) {
    if (m.decryptFailed) return const Text('[unable to decrypt]');
    final c = m.content;
    final reply = c?.replyTo;

    Widget main;
    if (c != null && c.isSticker) {
      main = Text(c.sticker ?? '', style: const TextStyle(fontSize: 48));
    } else if (c != null && c.isMedia) {
      main = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _mediaInline(m),
        if ((c.caption ?? '').isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(c.caption!)),
      ]);
    } else {
      main = Text(m.text ?? (mine ? '[sent]' : '…'));
    }

    if (reply == null) return main;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_replyQuote(reply, me), main]);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.read(supabaseServiceProvider).currentUser?.id;
    final repo = ref.read(chatRepositoryProvider);
    final stickerIsBubbleless = true;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(icon: const Icon(Icons.call), onPressed: () => _startCall(video: false)),
          IconButton(icon: const Icon(Icons.videocam), onPressed: () => _startCall(video: true)),
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
                    final bubbleless = stickerIsBubbleless && (m.content?.isSticker ?? false);
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: () => _setReply(m),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: bubbleless
                              ? EdgeInsets.zero
                              : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: bubbleless
                              ? null
                              : BoxDecoration(
                                  color: mine ? Colors.teal.shade700 : Colors.grey.shade800,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                          child: _body(m, mine, me),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_replyTo != null)
            Container(
              color: Colors.black26,
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(children: [
                const Icon(Icons.reply, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Replying: ${_replyTo!.preview}',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: _clearReply),
              ]),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(_showEmoji ? Icons.keyboard : Icons.emoji_emotions_outlined),
                    onPressed: () => setState(() => _showEmoji = !_showEmoji),
                  ),
                  IconButton(icon: const Icon(Icons.gif_box_outlined), onPressed: _sending ? null : _sendGif),
                  IconButton(icon: const Icon(Icons.sticky_note_2_outlined), onPressed: _sending ? null : _pickSticker),
                  IconButton(icon: const Icon(Icons.attach_file), onPressed: _sending ? null : _attach),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      onTap: () => setState(() => _showEmoji = false),
                      decoration: const InputDecoration(hintText: 'Message', border: OutlineInputBorder()),
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
          if (_showEmoji)
            SizedBox(
              height: 256,
              child: EmojiPicker(
                textEditingController: _input,
                config: const Config(height: 256),
              ),
            ),
        ],
      ),
    );
  }
}
