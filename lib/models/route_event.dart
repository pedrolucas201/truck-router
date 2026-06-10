enum RouteEventType { radar, restriction, police, scale, restArea }

class RouteEvent {
  final RouteEventType type;
  final double distanceM;

  const RouteEvent({required this.type, required this.distanceM});
}
