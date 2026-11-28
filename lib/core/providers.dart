import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase/supabase_service.dart';
import '../features/auth/auth_service.dart';
import '../features/privacy/privacy_settings.dart';
import '../features/chat/chat_repository.dart';
import '../features/chat/group_repository.dart';
import '../features/calls/call_service.dart';

final supabaseServiceProvider = Provider((_) => SupabaseService.instance);

final authServiceProvider =
    Provider((ref) => AuthService(ref.watch(supabaseServiceProvider)));

/// Emits auth state changes so the UI can react to sign-in / sign-out.
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authServiceProvider).authChanges,
);

final chatRepositoryProvider =
    Provider((ref) => ChatRepository(ref.watch(supabaseServiceProvider)));

final groupRepositoryProvider =
    Provider((ref) => GroupRepository(ref.watch(supabaseServiceProvider)));

/// Single CallService for the session (holds the active call + signal listener).
final callServiceProvider = Provider<CallService>((ref) {
  final s = CallService(ref.watch(supabaseServiceProvider));
  ref.onDispose(s.dispose);
  return s;
});

final privacyRepositoryProvider =
    Provider((ref) => PrivacyRepository(ref.watch(supabaseServiceProvider)));

final privacySettingsProvider = FutureProvider<PrivacySettings>(
  (ref) => ref.watch(privacyRepositoryProvider).load(),
);
