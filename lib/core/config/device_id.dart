import 'dart:convert';
import 'dart:math';
import '../storage/secure_store.dart';

/// A stable, random per-install device id used for Signal device addressing. Generated once
/// and kept in secure storage. Not derived from any hardware identifier (privacy).
class DeviceId {
  static const _name = 'device_id';

  static Future<String> get() async {
    final store = SecureStore.instance;
    final existing = await store.read(_name);
    if (existing != null) return existing;
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    final id = base64Url.encode(bytes).replaceAll('=', '');
    await store.write(_name, id);
    return id;
  }
}
