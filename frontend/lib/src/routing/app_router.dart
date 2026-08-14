import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';
import '../screens/app_shell.dart';
import '../screens/auth_screen.dart';
import '../screens/welcome_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  ref.watch(authSessionProvider);
  final refreshNotifier = AuthRefreshNotifier(authRepository.authStateChanges);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/welcome',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final signedIn = authRepository.currentSession != null;
      final location = state.matchedLocation;
      final publicRoute = location == '/welcome' || location == '/auth';

      if (!signedIn && !publicRoute) return '/welcome';
      if (signedIn && publicRoute) return '/app';
      return null;
    },
    routes: [
      GoRoute(
        path: '/welcome',
        builder: (context, state) =>
            WelcomeScreen(onGetStarted: () => context.go('/auth')),
      ),
      GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
      GoRoute(path: '/app', builder: (context, state) => const AppShell()),
    ],
  );
});

class AuthRefreshNotifier extends ChangeNotifier {
  AuthRefreshNotifier(Stream<AuthState> authStateChanges) {
    _subscription = authStateChanges.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
