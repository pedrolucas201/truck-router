import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/route_event.dart';
import 'package:truck_router/widgets/next_event_strip.dart';

void main() {
  group('tierFor', () {
    test('mapeia distância para o degrau certo', () {
      expect(tierFor(350), BadgeTier.near);
      expect(tierFor(799), BadgeTier.near);
      expect(tierFor(800), BadgeTier.mid);   // limite inferior do MID (inclusivo)
      expect(tierFor(1200), BadgeTier.mid);
      expect(tierFor(2000), BadgeTier.mid);  // limite superior do MID (inclusivo)
      expect(tierFor(2001), BadgeTier.far);
      expect(tierFor(5000), BadgeTier.far);
    });
  });

  group('NextEventStrip', () {
    Widget wrap(RouteEvent e) =>
        MaterialApp(home: Scaffold(body: NextEventStrip(event: e)));

    testWidgets('FAR (>2km) não renderiza nada', (tester) async {
      await tester.pumpWidget(
          wrap(const RouteEvent(type: RouteEventType.radar, distanceM: 5000)));
      expect(find.byType(Icon), findsNothing);
      expect(find.text('RADAR'), findsNothing);
    });

    testWidgets('MID mostra ícone + palavra + distância (auto-suficiente no mudo)',
        (tester) async {
      await tester.pumpWidget(
          wrap(const RouteEvent(type: RouteEventType.radar, distanceM: 1200)));
      expect(find.byIcon(Icons.camera_alt), findsOneWidget);
      expect(find.text('RADAR'), findsOneWidget);
      expect(find.text('1,2 km'), findsOneWidget);
      expect(find.byKey(const ValueKey('next-event-glow')), findsNothing);
    });

    testWidgets('NEAR (<800m) destaca e tem glow', (tester) async {
      await tester.pumpWidget(
          wrap(const RouteEvent(type: RouteEventType.scale, distanceM: 350)));
      expect(find.text('BALANÇA'), findsOneWidget);
      expect(find.text('350 m'), findsOneWidget);
      expect(find.byKey(const ValueKey('next-event-glow')), findsOneWidget);
    });
  });
}
