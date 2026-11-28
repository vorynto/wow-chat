import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../supabase/supabase_service.dart';
import '../storage/encrypted_db.dart';
import 'e2e_service.dart';
import 'persistent_sender_key_store.dart';
import 'signal_store.dart';
import '../../features/chat/session_service.dart';

/// Single shared Signal protocol store + services, so chat and calls operate on the SAME
/// session/ratchet state (two separate stores would diverge). Built once per process.
class CryptoEngine {
  CryptoEngine._();
  static final instance = CryptoEngine._();

  SignalProtocolStore? _store;
  E2EService? _e2e;
  SessionService? _sessions;
  PersistentSenderKeyStore? _senderKeys;

  SignalProtocolStore get store => _store!;
  E2EService get e2e => _e2e!;
  SessionService get sessions => _sessions!;
  PersistentSenderKeyStore get senderKeys => _senderKeys!;

  Future<void> ensureReady(SupabaseService supabase) async {
    if (_store != null) return;
    _store = await SignalStoreFactory.build();
    _e2e = E2EService(_store!);
    _sessions = SessionService(supabase, _store!);
    _senderKeys = PersistentSenderKeyStore(await EncryptedDb.instance());
  }
}
