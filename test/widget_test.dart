import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:truck_router/main.dart';
import 'package:truck_router/providers/theme_controller.dart';
import 'package:truck_router/providers/truck_profile_provider.dart';
import 'package:truck_router/providers/route_provider.dart';
import 'package:truck_router/repositories/restriction_repository.dart';
import 'package:truck_router/repositories/api_restriction_repository.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    final RestrictionRepository repo = ApiRestrictionRepository('http://localhost');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<RestrictionRepository>.value(value: repo),
          ChangeNotifierProvider(create: (_) => TruckProfileProvider()),
          ChangeNotifierProvider(create: (ctx) => RouteProvider(ctx.read<RestrictionRepository>())),
          ChangeNotifierProvider(create: (_) => ThemeController()),
        ],
        child: const TruckRouterApp(onboardingDone: true),
      ),
    );
  });
}
