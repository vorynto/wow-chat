import 'dart:convert';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import '../storage/secure_store.dart';
import '../supabase/supabase_service.dart';

/// Generates and persists the device's Signal identity + prekeys, and publishes the
/// PUBLIC half to Supabase so other users can start an X3DH session with us.
///
/// Private keys are stored only in Keystore-backed [SecureStore] and are NEVER uploaded.
class KeyManager {
  KeyManager(this._store, this._supabase);
  final SecureStore _store;
  final SupabaseService _supabase;

  static const _identityKeyName = 'signal_identity_keypair';
  static const _registrationIdName = 'signal_registration_id';

  /// First-run setup: create identity + registration id, a signed prekey, and a batch of
  /// one-time prekeys; persist locally and publish the public bundle.
  Future<void> ensureRegistered({required String deviceId, int oneTimeCount = 100}) async {
    final already = await _store.read(_identityKeyName);
    if (already != null) return;

    final identityKeyPair = generateIdentityKeyPair();
    final registrationId = generateRegistrationId(false);

    // Persist the private identity material locally (base64 of the serialized pair).
    await _store.write(_identityKeyName, base64.encode(identityKeyPair.serialize()));
    await _store.write(_registrationIdName, registrationId.toString());

    final signedPreKey = generateSignedPreKey(identityKeyPair, 0);
    final oneTimePreKeys = generatePreKeys(0, oneTimeCount);

    // TODO(store): persist signedPreKey + oneTimePreKeys into the local Signal stores
    // (InMemory* for now; swap for SQLCipher-backed stores in e2e_service.dart).

    await _publishBundle(
      deviceId: deviceId,
      registrationId: registrationId,
      identityKeyPair: identityKeyPair,
      signedPreKey: signedPreKey,
      oneTimePreKeys: oneTimePreKeys,
    );
  }

  Future<void> _publishBundle({
    required String deviceId,
    required int registrationId,
    required IdentityKeyPair identityKeyPair,
    required SignedPreKeyRecord signedPreKey,
    required List<PreKeyRecord> oneTimePreKeys,
  }) async {
    final tenantId = await _supabase.currentTenantId();
    final userId = _supabase.currentUser?.id;
    if (tenantId == null || userId == null) {
      throw StateError('Not signed in / no tenant; cannot publish keys.');
    }
    final db = _supabase.client;

    await db.from('device_keys').upsert({
      'tenant_id': tenantId,
      'user_id': userId,
      'device_id': deviceId,
      'registration_id': registrationId,
      'identity_key': base64.encode(identityKeyPair.getPublicKey().serialize()),
      'signed_prekey_id': signedPreKey.id,
      'signed_prekey_pub': base64.encode(signedPreKey.getKeyPair().publicKey.serialize()),
      'signed_prekey_sig': base64.encode(signedPreKey.signature),
    });

    final rows = oneTimePreKeys
        .map((pk) => {
              'tenant_id': tenantId,
              'user_id': userId,
              'device_id': deviceId,
              'prekey_id': pk.id,
              'prekey_pub': base64.encode(pk.getKeyPair().publicKey.serialize()),
            })
        .toList();
    await db.from('one_time_prekeys').insert(rows);
  }

  Future<IdentityKeyPair> loadIdentity() async {
    final raw = await _store.read(_identityKeyName);
    if (raw == null) throw StateError('No identity key; call ensureRegistered first.');
    return IdentityKeyPair.fromSerialized(base64.decode(raw));
  }
}
