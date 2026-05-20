import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TruckRouterApp());
  });
}
