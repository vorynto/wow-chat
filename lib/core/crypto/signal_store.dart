import 'dart:convert';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../storage/encrypted_db.dart';
import '../storage/secure_store.dart';
import 'persistent_signal_store.dart';

/// Builds the SQLCipher-backed Signal protocol store, seeded from the persisted identity.
/// Sessions and prekeys now survive app restarts.
class SignalStoreFactory {
  static const _identityKeyName = 'signal_identity_keypair';
  static const _registrationIdName = 'signal_registration_id';

  static Future<PersistentSignalStore> build() async {
    final store = SecureStore.instance;
    final rawIdentity = await store.read(_identityKeyName);
    final rawReg = await store.read(_registrationIdName);
    if (rawIdentity == null || rawReg == null) {
      throw StateError('Signal identity not initialised; run KeyManager.ensureRegistered.');
    }
    final identity = IdentityKeyPair.fromSerialized(base64.decode(rawIdentity));
    final registrationId = int.parse(rawReg);

    final db = await EncryptedDb.instance();
    final signalStore = PersistentSignalStore(identity, registrationId, db);
    await signalStore.load();
    return signalStore;
  }
}
