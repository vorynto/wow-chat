import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/crypto/crypto_engine.dart';
import '../../core/crypto/e2e_service.dart';
import '../../core/supabase/supabase_service.dart';
import 'local_message_cache.dart';
import 'message_content.dart';
import 'models.dart';

/// Sends and receives end-to-end encrypted messages.
///
/// For a 1:1 conversation we encrypt per-recipient-device with the Double Ratchet. (Group
/// conversations will use Signal sender keys — a later step; this class currently targets 1:1.)
class ChatRepository {
  ChatRepository(this._supabase);
  final SupabaseService _supabase;

  SupabaseClient get _db => _supabase.client;
  final _crypto = CryptoEngine.instance;

  /// Decrypted message plaintext (sent + received), persisted in the encrypted local DB.
  final _cache = LocalMessageCache();

  Future<void> _ensureCrypto() => _crypto.ensureReady(_supabase);

  /// Tenant members other than me, for starting a new chat. RLS limits this to our tenant.
  Future<List<Map<String, dynamic>>> listContacts() async {
    final me = _supabase.currentUser!.id;
    final rows = await _db.from('profiles').select('id, handle, display_name').neq('id', me);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// The most recently registered device id for a user (1:1 targets a single device for now).
  Future<String?> primaryDeviceId(String userId) async {
    final row = await _db
        .from('device_keys')
        .select('device_id')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row?['device_id'] as String?;
  }

  /// List conversations the caller is a member of.
  Future<List<Conversation>> listConversations() async {
    final rows = await _db
        .from('conversations')
        .select('id, is_group, created_at')
        .order('created_at', ascending: false);
    return (rows as List).map((r) => Conversation.fromRow(r)).toList();
  }

  /// Start (or return) a 1:1 conversation with another member of the tenant.
  Future<String> startDirectConversation(String otherUserId) async {
    final me = _supabase.currentUser!.id;
    final tenantId = await _supabase.currentTenantId();

    final conv = await _db
        .from('conversations')
        .insert({'tenant_id': tenantId, 'is_group': false, 'created_by': me})
        .select('id')
        .single();
    final convId = conv['id'] as String;

    await _db.from('conversation_members').insert([
      {'conversation_id': convId, 'tenant_id': tenantId, 'user_id': me, 'role': 'admin'},
      {'conversation_id': convId, 'tenant_id': tenantId, 'user_id': otherUserId, 'role': 'member'},
    ]);
    return convId;
  }

  /// Core send: encrypt a structured [content] envelope and insert the message.
  Future<void> _send({
    required String conversationId,
    required String otherUserId,
    required String otherDeviceId,
    required MessageContent content,
    String? mediaPath,
    int? ttlSec,
  }) async {
    await _ensureCrypto();
    final me = _supabase.currentUser!.id;
    final tenantId = await _supabase.currentTenantId();

    final body = content.encode();
    final address = await _crypto.sessions.ensureSession(otherUserId, otherDeviceId);
    final envelope = await _crypto.e2e.encryptText(address, body);

    final inserted = await _db.from('messages').insert({
      'tenant_id': tenantId,
      'conversation_id': conversationId,
      'sender_id': me,
      'body_enc': envelope,
      if (mediaPath != null) 'media_path': mediaPath,
      'expires_at': ttlSec == null || ttlSec == 0
          ? null
          : DateTime.now().toUtc().add(Duration(seconds: ttlSec)).toIso8601String(),
    }).select('id').single();
    await _cache.put(inserted['id'] as String, body);
  }

  /// Send a text message (optionally quoting another message).
  Future<void> sendText({
    required String conversationId,
    required String otherUserId,
    required String otherDeviceId,
    required String text,
    ReplyRef? replyTo,
    int? ttlSec,
  }) =>
      _send(
        conversationId: conversationId,
        otherUserId: otherUserId,
        otherDeviceId: otherDeviceId,
        content: MessageContent(kind: 'text', text: text, replyTo: replyTo),
        ttlSec: ttlSec,
      );

  /// Send a sticker (an emoji glyph rendered large), optionally quoting another message.
  Future<void> sendSticker({
    required String conversationId,
    required String otherUserId,
    required String otherDeviceId,
    required String sticker,
    ReplyRef? replyTo,
    int? ttlSec,
  }) =>
      _send(
        conversationId: conversationId,
        otherUserId: otherUserId,
        otherDeviceId: otherDeviceId,
        content: MessageContent(kind: 'sticker', sticker: sticker, replyTo: replyTo),
        ttlSec: ttlSec,
      );

  static const _mediaBucket = 'media';

  /// Encrypt a file client-side, upload only the ciphertext to Storage, and send an E2E
  /// message carrying the filename/type and the decryption key. The server never sees the
  /// plaintext file or its key.
  Future<void> sendMedia({
    required String conversationId,
    required String otherUserId,
    required String otherDeviceId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    String caption = '',
    ReplyRef? replyTo,
    int? ttlSec,
  }) async {
    await _ensureCrypto();
    final tenantId = await _supabase.currentTenantId();

    final (cipher, keyMaterial) = await E2EService.encryptMedia(bytes);
    final objectPath =
        '$tenantId/$conversationId/${DateTime.now().microsecondsSinceEpoch}.bin';
    await _db.storage.from(_mediaBucket).uploadBinary(
          objectPath,
          Uint8List.fromList(cipher),
          fileOptions: const FileOptions(contentType: 'application/octet-stream'),
        );

    await _send(
      conversationId: conversationId,
      otherUserId: otherUserId,
      otherDeviceId: otherDeviceId,
      mediaPath: objectPath,
      ttlSec: ttlSec,
      content: MessageContent(
        kind: 'media',
        mediaName: fileName,
        mediaType: mimeType,
        mediaKey: keyMaterial,
        caption: caption,
        replyTo: replyTo,
      ),
    );
  }

  /// Download + decrypt a media message's bytes. Cached in memory by message id so inline
  /// previews (images/GIFs) don't re-download on every stream emission.
  final Map<String, Uint8List> _mediaBytesCache = {};

  Future<Uint8List> mediaBytes(String messageId, String mediaPath, String keyMaterial) async {
    final cached = _mediaBytesCache[messageId];
    if (cached != null) return cached;
    final cipher = await _db.storage.from(_mediaBucket).download(mediaPath);
    final plain = await E2EService.decryptMedia(cipher, keyMaterial);
    final out = Uint8List.fromList(plain);
    _mediaBytesCache[messageId] = out;
    return out;
  }

  /// Live stream of messages for a conversation (Supabase Realtime), decrypted locally.
  /// The sender's own messages are shown from the cleartext we already have (not re-decrypted).
  Stream<List<ChatMessage>> watchMessages({
    required String conversationId,
    required String otherUserId,
    required String otherDeviceId,
  }) {
    return _db
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at')
        .asyncMap((rows) async {
          await _ensureCrypto();
          final me = _supabase.currentUser!.id;
          final out = <ChatMessage>[];
          final now = DateTime.now().toUtc();
          for (final r in rows) {
            final id = r['id'] as String;
            final senderId = r['sender_id'] as String;
            var failed = false;

            // Hide disappearing messages whose TTL has passed, even if the server cleanup job
            // hasn't deleted them yet.
            final exp = r['expires_at'] == null ? null : DateTime.parse(r['expires_at'] as String);
            if (exp != null && exp.toUtc().isBefore(now)) continue;

            // Read decrypted text from the local cache first; a Double-Ratchet message can be
            // decrypted only once, so we never re-decrypt.
            String? text = await _cache.get(id);
            if (text == null && senderId != me) {
              try {
                final address = await _crypto.sessions.ensureSession(otherUserId, otherDeviceId);
                text = await _crypto.e2e.decryptText(address, r['body_enc'] as String);
                await _cache.put(id, text);
              } catch (_) {
                failed = true;
              }
            }
            final content = text == null ? null : MessageContent.parse(text);
            out.add(ChatMessage(
              id: id,
              conversationId: conversationId,
              senderId: senderId,
              createdAt: DateTime.parse(r['created_at'] as String),
              text: content?.text,
              content: content,
              mediaPath: r['media_path'] as String?,
              expiresAt: r['expires_at'] == null ? null : DateTime.parse(r['expires_at'] as String),
              decryptFailed: failed,
            ));
          }
          return out;
        });
  }
}
