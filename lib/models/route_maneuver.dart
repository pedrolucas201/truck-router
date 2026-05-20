import 'package:google_maps_flutter/google_maps_flutter.dart';

class RouteManeuver {
  final String instruction;
  final String action;
  final String? direction;
  final int distanceMeters;
  final int durationSeconds;
  final int polylineOffset;
  final LatLng position;

  const RouteManeuver({
    required this.instruction,
    required this.action,
    this.direction,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.polylineOffset,
    required this.position,
  });
}
