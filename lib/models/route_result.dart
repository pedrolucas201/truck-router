import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'bridge_restriction.dart';
import 'route_maneuver.dart';

class RouteResult {
  final List<LatLng> polylinePoints;
  final int distanceMeters;
  final int durationSeconds;
  final List<RouteManeuver> maneuvers;
  final List<BridgeRestriction> restrictionsAvoided;
  final List<BridgeRestriction> restrictionsBlocked;

  const RouteResult({
    required this.polylinePoints,
    required this.distanceMeters,
    required this.durationSeconds,
    this.maneuvers           = const [],
    this.restrictionsAvoided = const [],
    this.restrictionsBlocked = const [],
  });

  RouteResult copyWith({
    List<LatLng>? polylinePoints,
    int? distanceMeters,
    int? durationSeconds,
    List<RouteManeuver>? maneuvers,
    List<BridgeRestriction>? restrictionsAvoided,
    List<BridgeRestriction>? restrictionsBlocked,
  }) => RouteResult(
    polylinePoints:      polylinePoints      ?? this.polylinePoints,
    distanceMeters:      distanceMeters      ?? this.distanceMeters,
    durationSeconds:     durationSeconds     ?? this.durationSeconds,
    maneuvers:           maneuvers           ?? this.maneuvers,
    restrictionsAvoided: restrictionsAvoided ?? this.restrictionsAvoided,
    restrictionsBlocked: restrictionsBlocked ?? this.restrictionsBlocked,
  );

  String get distanceText {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
    return '$distanceMeters m';
  }

  String get durationText {
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}min';
    return '${m}min';
  }
}
