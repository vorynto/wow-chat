import 'package:sqflite_sqlcipher/sqflite.dart';
import '../../core/storage/encrypted_db.dart';

/// Stores decrypted message plaintext by message id in the encrypted local DB.
///
/// Why this exists: a Double-Ratchet message can be decrypted only ONCE — the message key is
/// deleted afterwards. The realtime stream re-emits rows on every change, so we must decrypt a
/// received message a single time and then read it back from here. It also lets our own sent
/// messages (stored encrypted-for-the-recipient on the server) and history survive restarts.
class LocalMessageCache {
  Future<void> put(String id, String body) async {
    final db = await EncryptedDb.instance();
    await db.insert('msg_plain', {'id': id, 'body': body},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> get(String id) async {
    final db = await EncryptedDb.instance();
    final rows = await db.query('msg_plain', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first['body'] as String?;
  }
}
