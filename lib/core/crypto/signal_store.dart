import 'dart:convert';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import '../storage/secure_store.dart';

/// Builds the Signal protocol store (identity / prekeys / sessions / sender-keys).
///
/// NOTE: this uses the in-memory store seeded from the persisted identity. Sessions created
/// at runtime therefore do not survive an app restart yet. Before shipping, replace with
/// SQLCipher-backed implementations of IdentityKeyStore / PreKeyStore / SignedPreKeyStore /
/// SessionStore so ratchet state persists. The repository API below does not change when you
/// swap the store.
class SignalStoreFactory {
  static const _identityKeyName = 'signal_identity_keypair';
  static const _registrationIdName = 'signal_registration_id';

  static Future<InMemorySignalProtocolStore> build() async {
    final store = SecureStore.instance;
    final rawIdentity = await store.read(_identityKeyName);
    final rawReg = await store.read(_registrationIdName);
    if (rawIdentity == null || rawReg == null) {
      throw StateError('Signal identity not initialised; run KeyManager.ensureRegistered.');
    }
    final identity = IdentityKeyPair.fromSerialized(base64.decode(rawIdentity));
    final registrationId = int.parse(rawReg);
    return InMemorySignalProtocolStore(identity, registrationId);
  }
}
