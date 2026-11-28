// Plain data models for conversations and (decrypted) messages.
import 'message_content.dart';

class Conversation {
  const Conversation({
    required this.id,
    required this.isGroup,
    this.title,
    required this.createdAt,
  });

  final String id;
  final bool isGroup;
  final String? title; // decrypted client-side for groups
  final DateTime createdAt;

  factory Conversation.fromRow(Map<String, dynamic> r) => Conversation(
        id: r['id'] as String,
        isGroup: r['is_group'] as bool? ?? false,
        title: null, // title_enc is decrypted separately
        createdAt: DateTime.parse(r['created_at'] as String),
      );
}

/// A message after local decryption. `text` is null until decrypted (or if decryption fails).
/// `content` carries the structured 1:1 payload (kind, sticker, media meta, reply reference).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.createdAt,
    this.text,
    this.mediaPath,
    this.expiresAt,
    this.decryptFailed = false,
    this.content,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final DateTime createdAt;
  final String? text;
  final String? mediaPath;
  final DateTime? expiresAt;
  final bool decryptFailed;
  final MessageContent? content;
}
