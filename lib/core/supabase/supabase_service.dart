import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';

/// Thin wrapper around the Supabase client. All reads/writes go through RLS, so even
/// with the shipped anon key a client can only touch its own tenant's rows.
class SupabaseService {
  SupabaseService._();
  static final instance = SupabaseService._();

  SupabaseClient get client => Supabase.instance.client;

  static Future<void> init() async {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
      // Persist the session in encrypted storage, not plain shared-prefs.
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: true,
      ),
    );
  }

  User? get currentUser => client.auth.currentUser;
  bool get isSignedIn => currentUser != null;

  /// The caller's tenant id, read from their profile row (RLS-guarded).
  Future<String?> currentTenantId() async {
    final uid = currentUser?.id;
    if (uid == null) return null;
    final row = await client
        .from('profiles')
        .select('tenant_id')
        .eq('id', uid)
        .maybeSingle();
    return row?['tenant_id'] as String?;
  }

  Future<void> signOut() => client.auth.signOut();
}
