import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/route_event.dart';
import 'package:truck_router/widgets/route_event_style.dart';

void main() {
  test('cada tipo mapeia para icon, cor e label distintos', () {
    expect(RouteEventType.radar.icon, Icons.camera_alt);
    expect(RouteEventType.radar.label, 'Radar');
    expect(RouteEventType.restriction.icon, Icons.warning_amber_rounded);
    expect(RouteEventType.police.accentColor, Colors.blue.shade600);
    expect(RouteEventType.scale.label, 'Balança');
    expect(RouteEventType.restArea.icon, Icons.local_hotel);
  });
}
