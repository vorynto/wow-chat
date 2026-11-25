import 'dart:convert';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../../core/supabase/supabase_service.dart';

/// Establishes a Signal (X3DH) session with a recipient device by fetching their published
/// public prekey bundle from Supabase and processing it. One-time prekeys are consumed
/// (marked used) so each is handed out once.
class SessionService {
  SessionService(this._supabase, this._store);
  final SupabaseService _supabase;
  final SignalProtocolStore _store;

  /// Ensure a session exists with [userId]'s [deviceId]. Idempotent: no-op if one exists.
  Future<SignalProtocolAddress> ensureSession(String userId, String deviceId) async {
    final address = SignalProtocolAddress(userId, deviceId.hashCode & 0x7fffffff);
    final exists = await _store.containsSession(address);
    if (exists) return address;

    final db = _supabase.client;

    // Identity + signed prekey.
    final dk = await db
        .from('device_keys')
        .select()
        .eq('user_id', userId)
        .eq('device_id', deviceId)
        .single();

    // Grab and consume one unused one-time prekey (best-effort; sessions still work without).
    final otp = await db
        .from('one_time_prekeys')
        .select()
        .eq('user_id', userId)
        .eq('device_id', deviceId)
        .eq('consumed', false)
        .limit(1)
        .maybeSingle();

    if (otp != null) {
      await db.from('one_time_prekeys').update({'consumed': true}).eq('id', otp['id']);
    }

    final bundle = PreKeyBundle(
      dk['registration_id'] as int,
      address.getDeviceId(),
      otp == null ? null : otp['prekey_id'] as int,
      otp == null
          ? null
          : Curve.decodePoint(base64.decode(otp['prekey_pub'] as String), 0),
      dk['signed_prekey_id'] as int,
      Curve.decodePoint(base64.decode(dk['signed_prekey_pub'] as String), 0),
      base64.decode(dk['signed_prekey_sig'] as String),
      IdentityKey.fromBytes(base64.decode(dk['identity_key'] as String), 0),
    );

    final builder = SessionBuilder.fromSignalStore(_store, address);
    await builder.processPreKeyBundle(bundle);
    return address;
  }
}
