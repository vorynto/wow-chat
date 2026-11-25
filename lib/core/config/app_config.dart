/// App configuration. Values are injected at build time via --dart-define so secrets
/// never land in source control. See docs/BUILD.md.
class AppConfig {
  /// Supabase project URL, e.g. https://xxxx.supabase.co
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase anon/publishable key (safe to ship; RLS enforces access).
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Secret code typed in the phone dialer to reveal the app, e.g. "7469" -> *#*#7469#*#*.
  /// Keep this out of the APK string table in production (obfuscate / set at build time).
  static const secretDialCode = String.fromEnvironment('SECRET_DIAL_CODE', defaultValue: '7469');

  /// TURN/STUN for WebRTC NAT traversal.
  static const iceServers = String.fromEnvironment('ICE_SERVERS'); // JSON array

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
