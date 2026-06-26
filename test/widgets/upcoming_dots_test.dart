import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/route_event.dart';
import 'package:truck_router/widgets/upcoming_dots.dart';

void main() {
  Widget wrap(List<RouteEvent> events) =>
      MaterialApp(home: Scaffold(body: Stack(children: [UpcomingDots(events: events)])));

  Finder dotsIn() => find.descendant(
        of: find.byType(UpcomingDots),
        matching: find.byType(DecoratedBox),
      );

  testWidgets('vazio não renderiza pontos', (tester) async {
    await tester.pumpWidget(wrap([]));
    expect(dotsIn(), findsNothing);
  });

  testWidgets('um ponto por evento, capado em 3', (tester) async {
    await tester.pumpWidget(wrap(const [
      RouteEvent(type: RouteEventType.radar, distanceM: 3000),
      RouteEvent(type: RouteEventType.police, distanceM: 4000),
      RouteEvent(type: RouteEventType.scale, distanceM: 5000),
      RouteEvent(type: RouteEventType.restArea, distanceM: 6000),
    ]));
    expect(dotsIn(), findsNWidgets(3));
  });
}
