import '../supabase/supabase_service.dart';
import 'encrypted_db.dart';
import 'secure_store.dart';

/// Destroys all local secrets and data. After a wipe the device holds no keys, no decrypted
/// messages and no session — the encrypted DB is deleted and the Keystore entries are cleared,
/// so nothing local is recoverable. Server-side ciphertext remains until deleted separately,
/// but it is unreadable without the (now destroyed) keys.
class WipeService {
  static Future<void> wipeEverything() async {
    try {
      await SupabaseService.instance.signOut();
    } catch (_) {}
    await EncryptedDb.wipe();
    await SecureStore.instance.wipe();
  }
}
