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

  // Did the user arrive via the secret dial code? If so, skip the decoy.
  final viaSecret = await StealthGate.instance.openedViaSecretCode();

  runApp(ProviderScope(child: WowChatApp(openedViaSecretCode: viaSecret)));
}
