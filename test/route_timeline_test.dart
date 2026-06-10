import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/route_event.dart';
import 'package:truck_router/widgets/route_timeline.dart';

void main() {
  group('RouteEvent', () {
    test('stores type and distance', () {
      const e = RouteEvent(type: RouteEventType.radar, distanceM: 8000);
      expect(e.type, RouteEventType.radar);
      expect(e.distanceM, 8000.0);
    });

    test('all enum values exist', () {
      expect(RouteEventType.values, containsAll([
        RouteEventType.radar,
        RouteEventType.restriction,
        RouteEventType.police,
        RouteEventType.scale,
        RouteEventType.restArea,
      ]));
    });
  });

  group('RouteTimeline', () {
    Widget wrap(List<RouteEvent> events) => MaterialApp(
          home: Scaffold(
            body: Stack(children: [RouteTimeline(events: events)]),
          ),
        );

    testWidgets('renders nothing when events is empty', (tester) async {
      await tester.pumpWidget(wrap([]));
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('renders one icon for one event', (tester) async {
      await tester.pumpWidget(wrap([
        const RouteEvent(type: RouteEventType.radar, distanceM: 8000),
      ]));
      expect(find.byType(Icon), findsOneWidget);
    });

    testWidgets('shows distance badge only on first item', (tester) async {
      await tester.pumpWidget(wrap([
        const RouteEvent(type: RouteEventType.radar, distanceM: 8000),
        const RouteEvent(type: RouteEventType.police, distanceM: 23000),
      ]));
      expect(find.text('8.0km'), findsOneWidget);
      expect(find.text('23km'), findsNothing);
    });

    testWidgets('caps display at 4 items', (tester) async {
      await tester.pumpWidget(wrap([
        const RouteEvent(type: RouteEventType.radar,       distanceM: 1000),
        const RouteEvent(type: RouteEventType.police,      distanceM: 2000),
        const RouteEvent(type: RouteEventType.restriction, distanceM: 3000),
        const RouteEvent(type: RouteEventType.scale,       distanceM: 4000),
        const RouteEvent(type: RouteEventType.restArea,    distanceM: 5000),
      ]));
      expect(find.byType(Icon), findsNWidgets(4));
    });
  });
}
