import 'dart:typed_data';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// SQLCipher-backed [SenderKeyStore] for group (sender-key) messaging, so group sessions
/// survive restarts. Keyed by a stable string form of the SenderKeyName.
class PersistentSenderKeyStore extends SenderKeyStore {
  PersistentSenderKeyStore(this._db);
  final Database _db;

  static String _key(SenderKeyName n) =>
      '${n.groupId}::${n.sender.getName()}:${n.sender.getDeviceId()}';

  @override
  Future<SenderKeyRecord> loadSenderKey(SenderKeyName senderKeyName) async {
    final rows = await _db.query('sender_keys',
        where: 'name = ?', whereArgs: [_key(senderKeyName)], limit: 1);
    if (rows.isEmpty) return SenderKeyRecord();
    return SenderKeyRecord.fromSerialized(rows.first['record'] as Uint8List);
  }

  @override
  Future<void> storeSenderKey(SenderKeyName senderKeyName, SenderKeyRecord record) async {
    await _db.insert(
      'sender_keys',
      {'name': _key(senderKeyName), 'record': record.serialize()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
