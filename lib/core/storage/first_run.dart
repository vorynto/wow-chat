import 'secure_store.dart';

/// Tracks whether the one-time first-run welcome has been completed. Stored in Keystore-backed
/// secure storage, so it resets on uninstall (a fresh install shows the welcome again).
class FirstRun {
  static const _key = 'first_run_done_v1';

  static Future<bool> isDone() async =>
      (await SecureStore.instance.read(_key)) == '1';

  static Future<void> markDone() async =>
      SecureStore.instance.write(_key, '1');
}
