import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/supabase/supabase_service.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // NOTE: screenshot protection (FLAG_SECURE) is applied only once the hidden chat is open
  // (see VaultShell), not on the To-Do decoy — a to-do app that blocks screenshots would be
  // a tell.

  if (AppConfig.isConfigured) {
    await SupabaseService.init();
  }

  runApp(const ProviderScope(child: WowChatApp()));
}
