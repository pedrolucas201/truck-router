import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/route_event.dart';

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
}
