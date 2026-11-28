import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/device_id.dart';
import '../../core/crypto/crypto_engine.dart';
import '../../core/storage/encrypted_db.dart';
import '../../core/supabase/supabase_service.dart';
import 'local_message_cache.dart';
import 'models.dart';

/// Group messaging with Signal sender keys.
///
/// NOTE: like the rest of the crypto, this targets the libsignal_protocol_dart group API and
/// needs on-device verification. The sender distributes a SenderKeyDistributionMessage (SKDM)
/// to each member over the pairwise 1:1 channel, then encrypts each group message once.
class GroupRepository {
  GroupRepository(this._supabase);
  final SupabaseService _supabase;
  final _crypto = CryptoEngine.instance;
  final _cache = LocalMessageCache();
  StreamSubscription? _skdmSub;

  SupabaseClient get _db => _supabase.client;

  Future<String> createGroup(String title, List<String> memberIds) async {
    final me = _supabase.currentUser!.id;
    final tenantId = await _supabase.currentTenantId();
    final conv = await _db
        .from('conversations')
        .insert({'tenant_id': tenantId, 'is_group': true, 'created_by': me})
        .select('id')
        .single();
    final convId = conv['id'] as String;

    final rows = [
      {'conversation_id': convId, 'tenant_id': tenantId, 'user_id': me, 'role': 'admin'},
      for (final m in memberIds)
        {'conversation_id': convId, 'tenant_id': tenantId, 'user_id': m, 'role': 'member'},
    ];
    await _db.from('conversation_members').insert(rows);
    return convId;
  }

  Future<List<String>> _memberIds(String conversationId) async {
    final rows = await _db
        .from('conversation_members')
        .select('user_id')
        .eq('conversation_id', conversationId);
    return (rows as List).map((r) => r['user_id'] as String).toList();
  }

  /// Ensure our sender key is created locally and distributed to every other member.
  Future<void> _ensureDistributed(String conversationId) async {
    await _crypto.ensureReady(_supabase);
    final me = _supabase.currentUser!.id;
    final tenantId = await _supabase.currentTenantId();
    final myDevice = await DeviceId.get();

    if (await _distributed(conversationId)) return;

    final myName = SenderKeyName(conversationId, _crypto.sessions.addressFor(me, myDevice));
    final builder = GroupSessionBuilder(_crypto.senderKeys);
    final skdm = await builder.create(myName); // also stores our sender key locally
    final skdmBytes = skdm.serialize();

    for (final member in await _memberIds(conversationId)) {
      if (member == me) continue;
      final device = await _primaryDevice(member);
      if (device == null) continue;
      final address = await _crypto.sessions.ensureSession(member, device);
      final env = await _crypto.e2e.encryptText(address, base64.encode(skdmBytes));
      await _db.from('sender_key_distributions').insert({
        'tenant_id': tenantId,
        'conversation_id': conversationId,
        'from_user': me,
        'from_device': myDevice,
        'to_user': member,
        'skdm_enc': env,
      });
    }
    await _markDistributed(conversationId);
  }

  Future<void> sendGroupText(String conversationId, String text, {int? ttlSec}) async {
    await _ensureDistributed(conversationId);
    final me = _supabase.currentUser!.id;
    final tenantId = await _supabase.currentTenantId();
    final myDevice = await DeviceId.get();

    final myName = SenderKeyName(conversationId, _crypto.sessions.addressFor(me, myDevice));
    final cipher = GroupCipher(_crypto.senderKeys, myName);
    final ct = await cipher.encrypt(Uint8List.fromList(utf8.encode(text)));

    final inserted = await _db.from('messages').insert({
      'tenant_id': tenantId,
      'conversation_id': conversationId,
      'sender_id': me,
      'sender_device': myDevice,
      'body_enc': base64.encode(ct),
      'expires_at': ttlSec == null || ttlSec == 0
          ? null
          : DateTime.now().toUtc().add(Duration(seconds: ttlSec)).toIso8601String(),
    }).select('id').single();
    await _cache.put(inserted['id'] as String, text);
  }

  /// Listen for incoming sender-key distribution messages and process them so we can decrypt
  /// each sender's group messages.
  void startSkdmListener() {
    final me = _supabase.currentUser?.id;
    if (me == null) return;
    _skdmSub = _db
        .from('sender_key_distributions')
        .stream(primaryKey: ['id'])
        .eq('to_user', me)
        .listen((rows) async {
          await _crypto.ensureReady(_supabase);
          for (final r in rows) {
            try {
              final fromUser = r['from_user'] as String;
              final fromDevice = r['from_device'] as String;
              final convId = r['conversation_id'] as String;
              final address = _crypto.sessions.addressFor(fromUser, fromDevice);
              final skdmB64 = await _crypto.e2e.decryptText(address, r['skdm_enc'] as String);
              final skdm = SenderKeyDistributionMessage.fromSerialized(
                  Uint8List.fromList(base64.decode(skdmB64)));
              final name = SenderKeyName(convId, address);
              await GroupSessionBuilder(_crypto.senderKeys).process(name, skdm);
            } catch (_) {
              // Not yet decryptable (session not established) — will retry on next emission.
            }
          }
        });
  }

  Future<void> disposeListener() async => _skdmSub?.cancel();

  Stream<List<ChatMessage>> watchGroupMessages(String conversationId) {
    return _db
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at')
        .asyncMap((rows) async {
          await _crypto.ensureReady(_supabase);
          final me = _supabase.currentUser!.id;
          final now = DateTime.now().toUtc();
          final out = <ChatMessage>[];
          for (final r in rows) {
            final id = r['id'] as String;
            final senderId = r['sender_id'] as String;
            final senderDevice = r['sender_device'] as String?;
            final exp = r['expires_at'] == null ? null : DateTime.parse(r['expires_at'] as String);
            if (exp != null && exp.toUtc().isBefore(now)) continue;

            var failed = false;
            String? text = await _cache.get(id);
            if (text == null && senderId != me && senderDevice != null) {
              try {
                final name = SenderKeyName(
                    conversationId, _crypto.sessions.addressFor(senderId, senderDevice));
                final cipher = GroupCipher(_crypto.senderKeys, name);
                final plain = await cipher
                    .decrypt(Uint8List.fromList(base64.decode(r['body_enc'] as String)));
                text = utf8.decode(plain);
                await _cache.put(id, text);
              } catch (_) {
                failed = true;
              }
            }
            out.add(ChatMessage(
              id: id,
              conversationId: conversationId,
              senderId: senderId,
              createdAt: DateTime.parse(r['created_at'] as String),
              text: text,
              decryptFailed: failed,
            ));
          }
          return out;
        });
  }

  Future<String?> _primaryDevice(String userId) async {
    final row = await _db
        .from('device_keys')
        .select('device_id')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row?['device_id'] as String?;
  }

  Future<bool> _distributed(String conversationId) async {
    final db = await EncryptedDb.instance();
    final rows = await db
        .query('group_distributed', where: 'conversation_id = ?', whereArgs: [conversationId]);
    return rows.isNotEmpty;
  }

  Future<void> _markDistributed(String conversationId) async {
    final db = await EncryptedDb.instance();
    await db.insert('group_distributed', {'conversation_id': conversationId},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
