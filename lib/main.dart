import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/truck_profile_provider.dart';
import 'providers/route_provider.dart';
import 'repositories/restriction_repository.dart';
import 'repositories/firestore_restriction_repository.dart';
import 'repositories/api_restriction_repository.dart';
import 'screens/map_screen.dart';

const _backendUrl = String.fromEnvironment('BACKEND_URL');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final RestrictionRepository repo = _backendUrl.isNotEmpty
      ? ApiRestrictionRepository(_backendUrl)
      : FirestoreRestrictionRepository();

  runApp(
    MultiProvider(
      providers: [
        Provider<RestrictionRepository>.value(value: repo),
        ChangeNotifierProvider(create: (_) => TruckProfileProvider()..load()),
        ChangeNotifierProvider(create: (ctx) => RouteProvider(ctx.read<RestrictionRepository>())),
      ],
      child: const TruckRouterApp(),
    ),
  );
}

class TruckRouterApp extends StatelessWidget {
  const TruckRouterApp({super.key});

  @override
  Widget build(BuildContext context) {
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
      themeMode: ThemeMode.system,
      home: const MapScreen(),
    );
  }
}
