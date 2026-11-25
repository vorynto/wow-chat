import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/crypto/e2e_service.dart';
import '../../core/crypto/signal_store.dart';
import '../../core/supabase/supabase_service.dart';
import 'models.dart';
import 'session_service.dart';

/// Sends and receives end-to-end encrypted messages.
///
/// For a 1:1 conversation we encrypt per-recipient-device with the Double Ratchet. (Group
/// conversations will use Signal sender keys — a later step; this class currently targets 1:1.)
class ChatRepository {
  ChatRepository(this._supabase);
  final SupabaseService _supabase;

  SupabaseClient get _db => _supabase.client;
  SignalProtocolStore? _store;
  E2EService? _e2e;
  SessionService? _sessions;

  /// Plaintext of our own outgoing messages, by message id. The server only holds a copy
  /// encrypted for the recipient, so we can't decrypt our own — we keep the cleartext here.
  /// TODO: persist this in the SQLCipher local DB so sent history survives restarts.
  final Map<String, String> _ownPlaintext = {};

  Future<void> _ensureCrypto() async {
    if (_store != null) return;
    _store = await SignalStoreFactory.build();
    _e2e = E2EService(_store!);
    _sessions = SessionService(_supabase, _store!);
  }

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

  /// Encrypt and send a text message to the other party of a 1:1 conversation.
  Future<void> sendText({
    required String conversationId,
    required String otherUserId,
    required String otherDeviceId,
    required String text,
    int? ttlSec,
  }) async {
    await _ensureCrypto();
    final me = _supabase.currentUser!.id;
    final tenantId = await _supabase.currentTenantId();

    final address = await _sessions!.ensureSession(otherUserId, otherDeviceId);
    final envelope = await _e2e!.encryptText(address, text);

    final inserted = await _db.from('messages').insert({
      'tenant_id': tenantId,
      'conversation_id': conversationId,
      'sender_id': me,
      'body_enc': envelope,
      'expires_at': ttlSec == null || ttlSec == 0
          ? null
          : DateTime.now().toUtc().add(Duration(seconds: ttlSec)).toIso8601String(),
    }).select('id').single();
    _ownPlaintext[inserted['id'] as String] = text;
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
          for (final r in rows) {
            final senderId = r['sender_id'] as String;
            String? text;
            var failed = false;
            if (senderId == me) {
              text = _ownPlaintext[r['id'] as String]; // may be null after a restart (TODO: persist)
            } else {
              try {
                final address = await _sessions!.ensureSession(otherUserId, otherDeviceId);
                text = await _e2e!.decryptText(address, r['body_enc'] as String);
              } catch (_) {
                failed = true;
              }
            }
            out.add(ChatMessage(
              id: r['id'] as String,
              conversationId: conversationId,
              senderId: senderId,
              createdAt: DateTime.parse(r['created_at'] as String),
              text: text,
              mediaPath: r['media_path'] as String?,
              expiresAt: r['expires_at'] == null ? null : DateTime.parse(r['expires_at'] as String),
              decryptFailed: failed,
            ));
          }
          return out;
        });
  }
}
