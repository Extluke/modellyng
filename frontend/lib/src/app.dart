import 'package:flutter/material.dart';

import 'screens/app_shell.dart';
import 'screens/welcome_screen.dart';
import 'theme/app_theme.dart';

class ModellyngApp extends StatefulWidget {
  const ModellyngApp({super.key, this.skipWelcome = false});

  final bool skipWelcome;

  @override
  State<ModellyngApp> createState() => _ModellyngAppState();
}

class _ModellyngAppState extends State<ModellyngApp> {
  late bool _hasEntered = widget.skipWelcome;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Modellyng',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: _hasEntered
            ? const AppShell(key: ValueKey('app-shell'))
            : WelcomeScreen(
                key: const ValueKey('welcome'),
                onGetStarted: () => setState(() => _hasEntered = true),
              ),
      ),
    );
  }
}
