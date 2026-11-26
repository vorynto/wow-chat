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
  final _store = SecureStore.instance;
  static final _sha = Sha256();

  Future<void> _seedIfNeeded() async {
    final h = await _store.read(_hashKey);
    if (h == null) await setCode(AppConfig.defaultAccessCode);
  }

  Future<void> setCode(String code) async {
    final rnd = Random.secure();
    final salt = base64.encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    final digest = await _sha.hash(utf8.encode('$salt$code'));
    await _store.write(_saltKey, salt);
    await _store.write(_hashKey, base64.encode(digest.bytes));
  }

  /// True if [code] matches the stored secret. Seeds the default on first use.
  Future<bool> verify(String code) async {
    await _seedIfNeeded();
    final salt = await _store.read(_saltKey);
    final stored = await _store.read(_hashKey);
    if (salt == null || stored == null) return false;
    final digest = await _sha.hash(utf8.encode('$salt$code'));
    return base64.encode(digest.bytes) == stored;
  }
}
