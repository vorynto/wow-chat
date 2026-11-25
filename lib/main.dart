import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/supabase/supabase_service.dart';
import 'features/stealth/stealth_gate.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Block screenshots / recents preview as early as possible; the privacy setting can
  // relax it later if the user turns it off.
  await StealthGate.enableSecureFlag();

  if (AppConfig.isConfigured) {
    await SupabaseService.init();
  }

  runApp(const ProviderScope(child: WowChatApp()));
}
