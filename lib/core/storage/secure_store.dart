import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keystore-backed secure storage for secrets that must never leave the device:
///  - the Signal identity private key / session state,
///  - the SQLCipher database key,
///  - the app-lock PIN hash and decoy/panic settings.
///
/// On Android this is backed by the hardware Keystore (AES-GCM, StrongBox where available).
class SecureStore {
  SecureStore._();
  static final instance = SecureStore._();

  static const _opts = AndroidOptions(
    encryptedSharedPreferences: true,
  );
  final _s = const FlutterSecureStorage(aOptions: _opts);

  static const _dbKeyName = 'db_cipher_key';

  Future<void> write(String key, String value) => _s.write(key: key, value: value, aOptions: _opts);
  Future<String?> read(String key) => _s.read(key: key, aOptions: _opts);
  Future<void> delete(String key) => _s.delete(key: key, aOptions: _opts);

  /// Returns the SQLCipher key, creating a strong random one on first run.
  Future<String> databaseKey() async {
    final existing = await read(_dbKeyName);
    if (existing != null) return existing;
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    final key = base64Url.encode(bytes);
    await write(_dbKeyName, key);
    return key;
  }

  /// Panic wipe: erase all local secrets. The caller should also drop the encrypted DB file
  /// and sign out. Without the Keystore key, the ciphertext DB is unrecoverable.
  Future<void> wipe() => _s.deleteAll(aOptions: _opts);
}
