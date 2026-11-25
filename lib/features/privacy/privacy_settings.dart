import '../../core/supabase/supabase_service.dart';

enum PhotoScope { everyone, contacts, nobody }

/// User-controlled privacy settings surfaced on the Settings page.
class PrivacySettings {
  const PrivacySettings({
    this.lastSeenVisible = false,
    this.readReceipts = false,
    this.typingIndicators = false,
    this.profilePhotoScope = PhotoScope.contacts,
    this.defaultMsgTtlSec = 0,
    this.blockScreenshots = true,
    this.appLock = true,
  });

  final bool lastSeenVisible;
  final bool readReceipts;
  final bool typingIndicators;
  final PhotoScope profilePhotoScope;
  final int defaultMsgTtlSec; // 0 = disappearing messages off
  final bool blockScreenshots; // FLAG_SECURE
  final bool appLock; // biometric/PIN on open

  PrivacySettings copyWith({
    bool? lastSeenVisible,
    bool? readReceipts,
    bool? typingIndicators,
    PhotoScope? profilePhotoScope,
    int? defaultMsgTtlSec,
    bool? blockScreenshots,
    bool? appLock,
  }) =>
      PrivacySettings(
        lastSeenVisible: lastSeenVisible ?? this.lastSeenVisible,
        readReceipts: readReceipts ?? this.readReceipts,
        typingIndicators: typingIndicators ?? this.typingIndicators,
        profilePhotoScope: profilePhotoScope ?? this.profilePhotoScope,
        defaultMsgTtlSec: defaultMsgTtlSec ?? this.defaultMsgTtlSec,
        blockScreenshots: blockScreenshots ?? this.blockScreenshots,
        appLock: appLock ?? this.appLock,
      );

  factory PrivacySettings.fromRow(Map<String, dynamic> r) => PrivacySettings(
        lastSeenVisible: r['last_seen_visible'] as bool? ?? false,
        readReceipts: r['read_receipts'] as bool? ?? false,
        typingIndicators: r['typing_indicators'] as bool? ?? false,
        profilePhotoScope: PhotoScope.values.firstWhere(
          (e) => e.name == (r['profile_photo_scope'] as String? ?? 'contacts'),
          orElse: () => PhotoScope.contacts,
        ),
        defaultMsgTtlSec: r['default_msg_ttl_sec'] as int? ?? 0,
        blockScreenshots: r['block_screenshots'] as bool? ?? true,
        appLock: r['app_lock'] as bool? ?? true,
      );

  Map<String, dynamic> toRow() => {
        'last_seen_visible': lastSeenVisible,
        'read_receipts': readReceipts,
        'typing_indicators': typingIndicators,
        'profile_photo_scope': profilePhotoScope.name,
        'default_msg_ttl_sec': defaultMsgTtlSec,
        'block_screenshots': blockScreenshots,
        'app_lock': appLock,
      };
}

/// Loads/saves the caller's privacy settings (RLS: only your own row).
class PrivacyRepository {
  PrivacyRepository(this._supabase);
  final SupabaseService _supabase;

  Future<PrivacySettings> load() async {
    final uid = _supabase.currentUser?.id;
    if (uid == null) return const PrivacySettings();
    final row = await _supabase.client
        .from('privacy_settings')
        .select()
        .eq('user_id', uid)
        .maybeSingle();
    return row == null ? const PrivacySettings() : PrivacySettings.fromRow(row);
  }

  Future<void> save(PrivacySettings s) async {
    final uid = _supabase.currentUser?.id;
    final tenantId = await _supabase.currentTenantId();
    if (uid == null || tenantId == null) return;
    await _supabase.client.from('privacy_settings').upsert({
      'user_id': uid,
      'tenant_id': tenantId,
      ...s.toRow(),
    });
  }
}
