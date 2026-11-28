import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

import '../config/app_config.dart';
import 'secure_store.dart';

/// Stores and verifies the secret code that unlocks the hidden chat from inside the To-Do
/// decoy. The code is never stored in plaintext — only a salted SHA-256 hash is kept in
/// Keystore-backed secure storage. Seeded once from the build-time default; user-changeable.
class AccessCodeService {
  AccessCodeService._();
  static final instance = AccessCodeService._();

  static const _hashKey = 'vault_code_hash';
  static const _saltKey = 'vault_code_salt';
  static const _panicHashKey = 'vault_panic_hash';
  static const _panicSaltKey = 'vault_panic_salt';
  final _store = SecureStore.instance;
  static final _sha = Sha256();

  Future<void> _seedIfNeeded() async {
    final h = await _store.read(_hashKey);
    if (h == null) await setCode(AppConfig.defaultAccessCode);
  }

  Future<String> _hash(String salt, String code) async {
    final digest = await _sha.hash(utf8.encode('$salt$code'));
    return base64.encode(digest.bytes);
  }

  String _newSalt() {
    final rnd = Random.secure();
    return base64.encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
  }

  Future<void> setCode(String code) async {
    final salt = _newSalt();
    await _store.write(_saltKey, salt);
    await _store.write(_hashKey, await _hash(salt, code));
  }

  /// Set (or clear, with an empty string) the panic code. Entering it in the decoy wipes the
  /// vault instead of opening it.
  Future<void> setPanicCode(String code) async {
    if (code.isEmpty) {
      await _store.delete(_panicHashKey);
      await _store.delete(_panicSaltKey);
      return;
    }
    final salt = _newSalt();
    await _store.write(_panicSaltKey, salt);
    await _store.write(_panicHashKey, await _hash(salt, code));
  }

  Future<bool> hasPanicCode() async => (await _store.read(_panicHashKey)) != null;

  /// True if [code] matches the stored secret. Seeds the default on first use.
  Future<bool> verify(String code) async {
    await _seedIfNeeded();
    final salt = await _store.read(_saltKey);
    final stored = await _store.read(_hashKey);
    if (salt == null || stored == null) return false;
    return await _hash(salt, code) == stored;
  }

  /// True if [code] matches the panic code (if one is set).
  Future<bool> verifyPanic(String code) async {
    final salt = await _store.read(_panicSaltKey);
    final stored = await _store.read(_panicHashKey);
    if (salt == null || stored == null) return false;
    return await _hash(salt, code) == stored;
  }
}
