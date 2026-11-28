import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'secure_store.dart';

/// Opens the on-device encrypted (SQLCipher) database. The encryption key lives in
/// Keystore-backed secure storage, so the DB file is useless without the device's Keystore.
///
/// Holds Signal protocol state (sessions/prekeys/identities) and decrypted message plaintext,
/// so chats and sessions survive app restarts.
class EncryptedDb {
  EncryptedDb._();
  static Database? _db;

  static Future<Database> instance() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/wowchat_secure.db';
    final key = await SecureStore.instance.databaseKey();
    _db = await openDatabase(
      path,
      password: key,
      version: 2,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE sessions(address TEXT PRIMARY KEY, record BLOB)');
        await db.execute('CREATE TABLE prekeys(id INTEGER PRIMARY KEY, record BLOB)');
        await db.execute('CREATE TABLE signed_prekeys(id INTEGER PRIMARY KEY, record BLOB)');
        await db.execute('CREATE TABLE identities(address TEXT PRIMARY KEY, ikey BLOB)');
        // Decrypted message text by message id (both sent and received). Received messages are
        // decrypted exactly once — re-decrypting would fail after the ratchet advances.
        await db.execute('CREATE TABLE msg_plain(id TEXT PRIMARY KEY, body TEXT)');
        // Per-group sender keys (keyed by "groupId::name:device").
        await db.execute('CREATE TABLE sender_keys(name TEXT PRIMARY KEY, record BLOB)');
        // Groups to which we've already distributed our sender key.
        await db.execute('CREATE TABLE group_distributed(conversation_id TEXT PRIMARY KEY)');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute('CREATE TABLE IF NOT EXISTS sender_keys(name TEXT PRIMARY KEY, record BLOB)');
          await db.execute('CREATE TABLE IF NOT EXISTS group_distributed(conversation_id TEXT PRIMARY KEY)');
        }
      },
    );
    return _db!;
  }

  /// Panic wipe: delete the encrypted database file entirely.
  static Future<void> wipe() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/wowchat_secure.db';
    await _db?.close();
    _db = null;
    await deleteDatabase(path);
  }
}
