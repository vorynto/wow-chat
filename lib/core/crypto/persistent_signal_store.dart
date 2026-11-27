import 'dart:typed_data';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// A Signal protocol store backed by the encrypted SQLCipher database, so sessions, prekeys
/// and known identities survive app restarts.
///
/// Implementation note: it extends [InMemorySignalProtocolStore] for the read paths and
/// overrides the mutating methods to also write through to SQL. On startup [load] seeds the
/// in-memory maps from the database (via `super.*`, bypassing the write-through overrides).
class PersistentSignalStore extends InMemorySignalProtocolStore {
  PersistentSignalStore(IdentityKeyPair identityKeyPair, int registrationId, this._db)
      : super(identityKeyPair, registrationId);

  final Database _db;

  static String _addr(SignalProtocolAddress a) => '${a.getName()}:${a.getDeviceId()}';

  /// Seed in-memory state from the database. Call once after construction.
  Future<void> load() async {
    for (final r in await _db.query('sessions')) {
      final parts = (r['address'] as String).split(':');
      final address = SignalProtocolAddress(parts[0], int.parse(parts[1]));
      await super.storeSession(address, SessionRecord.fromSerialized(r['record'] as Uint8List));
    }
    for (final r in await _db.query('prekeys')) {
      await super.storePreKey(r['id'] as int, PreKeyRecord.fromBuffer(r['record'] as Uint8List));
    }
    for (final r in await _db.query('signed_prekeys')) {
      await super.storeSignedPreKey(
          r['id'] as int, SignedPreKeyRecord.fromSerialized(r['record'] as Uint8List));
    }
    for (final r in await _db.query('identities')) {
      final parts = (r['address'] as String).split(':');
      final address = SignalProtocolAddress(parts[0], int.parse(parts[1]));
      await super.saveIdentity(address, IdentityKey.fromBytes(r['ikey'] as Uint8List, 0));
    }
  }

  // ───────────────────────── sessions ─────────────────────────
  @override
  Future<void> storeSession(SignalProtocolAddress address, SessionRecord record) async {
    await super.storeSession(address, record);
    await _db.insert('sessions', {'address': _addr(address), 'record': record.serialize()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteSession(SignalProtocolAddress address) async {
    await super.deleteSession(address);
    await _db.delete('sessions', where: 'address = ?', whereArgs: [_addr(address)]);
  }

  @override
  Future<void> deleteAllSessions(String name) async {
    await super.deleteAllSessions(name);
    await _db.delete('sessions', where: 'address LIKE ?', whereArgs: ['$name:%']);
  }

  // ───────────────────────── one-time prekeys ─────────────────────────
  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) async {
    await super.storePreKey(preKeyId, record);
    await _db.insert('prekeys', {'id': preKeyId, 'record': record.serialize()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> removePreKey(int preKeyId) async {
    await super.removePreKey(preKeyId);
    await _db.delete('prekeys', where: 'id = ?', whereArgs: [preKeyId]);
  }

  // ───────────────────────── signed prekeys ─────────────────────────
  @override
  Future<void> storeSignedPreKey(int signedPreKeyId, SignedPreKeyRecord record) async {
    await super.storeSignedPreKey(signedPreKeyId, record);
    await _db.insert('signed_prekeys', {'id': signedPreKeyId, 'record': record.serialize()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) async {
    await super.removeSignedPreKey(signedPreKeyId);
    await _db.delete('signed_prekeys', where: 'id = ?', whereArgs: [signedPreKeyId]);
  }

  // ───────────────────────── identities ─────────────────────────
  @override
  Future<bool> saveIdentity(SignalProtocolAddress address, IdentityKey? identityKey) async {
    final changed = await super.saveIdentity(address, identityKey);
    if (identityKey != null) {
      await _db.insert('identities', {'address': _addr(address), 'ikey': identityKey.serialize()},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return changed;
  }
}
