import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'providers/truck_profile_provider.dart';
import 'providers/route_provider.dart';
import 'repositories/restriction_repository.dart';
import 'repositories/firestore_restriction_repository.dart';
import 'repositories/api_restriction_repository.dart';
import 'screens/map_screen.dart';
import 'screens/onboarding_screen.dart';
import 'providers/theme_controller.dart';

const _backendUrl = String.fromEnvironment('BACKEND_URL');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final prefs = await SharedPreferences.getInstance();
  final onboardingDone = prefs.getBool('onboarding_done') ?? false;

  final RestrictionRepository repo = _backendUrl.isNotEmpty
      ? ApiRestrictionRepository(_backendUrl)
      : FirestoreRestrictionRepository();

  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['truck_router'],
      'Ícones de caminhão do loader: Twemoji '
      '(© Twitter/X, mantido por jdecked), licença CC-BY 4.0. '
      'https://github.com/jdecked/twemoji',
    );
  });

  runApp(
    MultiProvider(
      providers: [
        Provider<RestrictionRepository>.value(value: repo),
        ChangeNotifierProvider(create: (_) => TruckProfileProvider()..load()),
        ChangeNotifierProvider(create: (ctx) => RouteProvider(ctx.read<RestrictionRepository>())),
        ChangeNotifierProvider(create: (_) => ThemeController()),
      ],
      child: TruckRouterApp(onboardingDone: onboardingDone),
    ),
  );
}

class TruckRouterApp extends StatelessWidget {
  final bool onboardingDone;
  const TruckRouterApp({super.key, required this.onboardingDone});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeController>().value;
    return MaterialApp(
      title: 'Rota Caminhão',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFF00897B)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Color(0xFF00897B),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: themeMode,
      home: onboardingDone ? const MapScreen() : const OnboardingScreen(),
    );
  }
}
