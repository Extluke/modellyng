import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/config/app_config.dart';
import 'src/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final initialization = Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
  );
  // Warm the PDFium web worker/WASM while authentication initializes so the
  // first evidence click does not pay the full renderer startup cost.
  unawaited(pdfrxFlutterInitialize().catchError((Object _) {}));
  runApp(
    ProviderScope(child: _ModellyngBootstrap(initialization: initialization)),
  );
}

class _ModellyngBootstrap extends StatelessWidget {
  const _ModellyngBootstrap({required this.initialization});

  final Future<Supabase> initialization;

  @override
  Widget build(BuildContext context) => FutureBuilder<Supabase>(
    future: initialization,
    builder: (context, snapshot) {
      if (snapshot.hasData) return const ModellyngApp();
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: snapshot.hasError
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_outlined, size: 48),
                        SizedBox(height: 16),
                        Text(
                          'Layanan lokal belum dapat dihubungkan. Muat ulang setelah Supabase berjalan.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    )
                  : const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Menyiapkan Modellyng…'),
                      ],
                    ),
            ),
          ),
        ),
      );
    },
  );
}
