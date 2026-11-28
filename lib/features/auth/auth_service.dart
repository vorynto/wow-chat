import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/device_id.dart';
import '../../core/crypto/key_manager.dart';
import '../../core/storage/secure_store.dart';
import '../../core/supabase/supabase_service.dart';

/// Sign-in + tenant onboarding. We use passwordless email OTP (no password to leak, no
/// phone number required). Tenant membership is created via SECURITY DEFINER RPCs so the
/// client can never assign itself an arbitrary tenant.
class AuthService {
  AuthService(this._supabase);
  final SupabaseService _supabase;

  SupabaseClient get _db => _supabase.client;

  Stream<AuthState> get authChanges => _db.auth.onAuthStateChange;
  bool get isSignedIn => _supabase.isSignedIn;

  /// Step 1: request a 6-digit code by email. This both CREATES the account (if the email is
  /// new) and signs in an existing one — `shouldCreateUser: true` makes it an email-OTP
  /// sign-up + sign-in in a single flow.
  Future<void> sendEmailOtp(String email) => _db.auth.signInWithOtp(
        email: email.trim(),
        shouldCreateUser: true,
      );

  /// Step 2: verify the code. On success a session exists; the user may still need onboarding.
  ///
  /// A brand-new email (first-time signup) is verified under the `signup` OTP type, while an
  /// existing email uses the `email` type. We don't know which applies, so we try `email`
  /// first and fall back to `signup`. A failed verify does NOT consume the token, so retrying
  /// with another type is safe.
  Future<void> verifyEmailOtp(String email, String token) async {
    final e = email.trim();
    final t = token.replaceAll(RegExp(r'\s'), ''); // strip spaces from a pasted code
    try {
      await _db.auth.verifyOTP(type: OtpType.email, email: e, token: t);
    } on AuthException {
      await _db.auth.verifyOTP(type: OtpType.signup, email: e, token: t);
    }
  }

  /// Does the signed-in user already belong to a tenant (has a profile)?
  Future<bool> hasProfile() async {
    final uid = _supabase.currentUser?.id;
    if (uid == null) return false;
    final row =
        await _db.from('profiles').select('id').eq('id', uid).maybeSingle();
    return row != null;
  }

  /// Create a brand-new tenant (workspace) and become its first member.
  Future<void> createTenant({
    required String slug,
    required String name,
    required String handle,
  }) async {
    await _db.rpc('create_tenant', params: {
      'p_slug': slug,
      'p_name': name,
      'p_handle': handle,
    });
    await _afterOnboarding();
  }

  /// Join an existing tenant using an invite code.
  Future<void> joinTenant({
    required String slug,
    required String inviteCode,
    required String handle,
  }) async {
    await _db.rpc('join_tenant', params: {
      'p_slug': slug,
      'p_invite_code': inviteCode,
      'p_handle': handle,
    });
    await _afterOnboarding();
  }

  /// After a profile exists, publish this device's Signal key bundle (public keys only).
  Future<void> _afterOnboarding() async {
    final deviceId = await DeviceId.get();
    final km = KeyManager(SecureStore.instance, _supabase);
    await km.ensureRegistered(deviceId: deviceId);
  }

  /// Called on normal app start when already signed in + onboarded, to make sure keys exist
  /// (e.g. after a reinstall that kept the auth session but lost local keys).
  Future<void> ensureKeysIfOnboarded() async {
    if (!isSignedIn) return;
    if (await hasProfile()) {
      await _afterOnboarding();
    }
  }

  Future<void> signOut() => _supabase.signOut();
}
