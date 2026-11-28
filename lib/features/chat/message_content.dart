import 'dart:convert';

/// A quoted reply reference (WhatsApp-style "tagged reply").
class ReplyRef {
  const ReplyRef({required this.id, required this.preview, required this.sender});
  final String id;
  final String preview; // short snippet of the quoted message
  final String sender; // sender id of the quoted message

  Map<String, dynamic> toJson() => {'id': id, 'preview': preview, 'sender': sender};
  factory ReplyRef.fromJson(Map<String, dynamic> j) =>
      ReplyRef(id: j['id'] as String, preview: j['preview'] as String? ?? '', sender: j['sender'] as String? ?? '');
}

/// The decrypted content of a message. Everything inside is end-to-end encrypted; the server
/// only ever sees the ciphertext envelope. `kind` selects how it renders.
class MessageContent {
  const MessageContent({
    required this.kind, // 'text' | 'sticker' | 'media'
    this.text,
    this.sticker,
    this.mediaName,
    this.mediaType,
    this.mediaKey,
    this.caption,
    this.replyTo,
  });

  final String kind;
  final String? text;
  final String? sticker; // e.g. an emoji glyph
  final String? mediaName;
  final String? mediaType; // MIME
  final String? mediaKey; // media decryption key material
  final String? caption;
  final ReplyRef? replyTo;

  bool get isSticker => kind == 'sticker';
  bool get isMedia => kind == 'media';
  bool get isImageLike =>
      isMedia && (mediaType?.startsWith('image/') ?? false);

  Map<String, dynamic> toJson() => {
        'kind': kind,
        if (text != null) 'text': text,
        if (sticker != null) 'sticker': sticker,
        if (mediaName != null) 'name': mediaName,
        if (mediaType != null) 'type': mediaType,
        if (mediaKey != null) 'key': mediaKey,
        if (caption != null && caption!.isNotEmpty) 'caption': caption,
        if (replyTo != null) 'replyTo': replyTo!.toJson(),
      };

  String encode() => jsonEncode(toJson());

  /// Parse a decrypted body. Accepts the structured JSON envelope, or a bare string (legacy /
  /// group plaintext), which is treated as a text message.
  static MessageContent parse(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map<String, dynamic> && j['kind'] is String) {
        final reply = j['replyTo'] is Map<String, dynamic>
            ? ReplyRef.fromJson(j['replyTo'] as Map<String, dynamic>)
            : null;
        return MessageContent(
          kind: j['kind'] as String,
          text: j['text'] as String?,
          sticker: j['sticker'] as String?,
          mediaName: j['name'] as String?,
          mediaType: j['type'] as String?,
          mediaKey: j['key'] as String?,
          caption: j['caption'] as String?,
          replyTo: reply,
        );
      }
    } catch (_) {
      // not JSON — fall through to plain text
    }
    return MessageContent(kind: 'text', text: body);
  }

  /// A short preview used when THIS message is quoted in a reply.
  String previewText() {
    if (isSticker) return sticker ?? 'Sticker';
    if (isMedia) {
      if (isImageLike) return '📷 Photo';
      return '📎 ${mediaName ?? 'File'}';
    }
    final t = text ?? '';
    return t.length > 80 ? '${t.substring(0, 80)}…' : t;
  }
}
