import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase/supabase_service.dart';
import '../features/auth/auth_service.dart';
import '../features/privacy/privacy_settings.dart';
import '../features/chat/chat_repository.dart';

final supabaseServiceProvider = Provider((_) => SupabaseService.instance);

final authServiceProvider =
    Provider((ref) => AuthService(ref.watch(supabaseServiceProvider)));

/// Emits auth state changes so the UI can react to sign-in / sign-out.
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authServiceProvider).authChanges,
);

final chatRepositoryProvider =
    Provider((ref) => ChatRepository(ref.watch(supabaseServiceProvider)));

final privacyRepositoryProvider =
    Provider((ref) => PrivacyRepository(ref.watch(supabaseServiceProvider)));

final privacySettingsProvider = FutureProvider<PrivacySettings>(
  (ref) => ref.watch(privacyRepositoryProvider).load(),
);
