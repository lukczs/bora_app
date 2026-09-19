import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/env.dart';
import 'app/router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }
  await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);
  runApp(const ProviderScope(child: BoraApp()));
}

class BoraApp extends ConsumerWidget {
  const BoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Bora',
      debugShowCheckedModeBanner: false,
      theme: buildBoraTheme(),
      routerConfig: ref.watch(routerProvider),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildBoraTheme(),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Falta ligar o app ao Supabase.\n\nAbra lib/app/env.dart e cole a URL e a chave anon do projeto (Settings > API).',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 17, height: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}
