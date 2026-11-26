/// App configuration. Values are injected at build time via --dart-define so secrets
/// never land in source control. See docs/BUILD.md.
class AppConfig {
  /// Supabase project URL, e.g. https://xxxx.supabase.co
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase anon/publishable key (safe to ship; RLS enforces access).
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Default secret code that reveals the hidden chat from inside the To-Do decoy. Seeded on
  /// first run; the user can change it later (stored hashed in secure storage). Set at build
  /// time so it isn't a plain default in the APK.
  static const defaultAccessCode =
      String.fromEnvironment('ACCESS_CODE', defaultValue: '4729');

  /// TURN/STUN for WebRTC NAT traversal.
  static const iceServers = String.fromEnvironment('ICE_SERVERS'); // JSON array

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
