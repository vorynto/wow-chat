import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'sign_in_screen.dart';
import 'onboarding_screen.dart';
import '../home/home_shell.dart';

/// Decides what to show once the decoy has been passed:
///  - not signed in            -> SignInScreen (email OTP)
///  - signed in, no tenant yet -> OnboardingScreen (create / join tenant)
///  - signed in + onboarded    -> HomeShell
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild when auth state changes.
    ref.watch(authStateProvider);
    final auth = ref.watch(authServiceProvider);

    if (!auth.isSignedIn) {
      return const SignInScreen();
    }

    return FutureBuilder<bool>(
      future: auth.hasProfile(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snap.data! ? const HomeShell() : const OnboardingScreen();
      },
    );
  }
}
