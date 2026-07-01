import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'bridge_restriction.dart';
import 'route_maneuver.dart';

/// Limite de velocidade de caminhão (km/h) a partir de um offset da polyline.
/// A HERE já devolve o limite ciente do modo (transportMode=truck) por segmento —
/// não é o limite de carro, é o do caminhão naquele trecho.
class SpeedLimitSpan {
  final int offset; // índice em polylinePoints onde este limite passa a valer
  final int kmh;
  const SpeedLimitSpan(this.offset, this.kmh);
}

class RouteResult {
  final List<LatLng> polylinePoints;
  final int distanceMeters;
  final int durationSeconds;
  final List<RouteManeuver> maneuvers;
  final List<BridgeRestriction> restrictionsAvoided;
  final List<BridgeRestriction> restrictionsBlocked;
  final bool usedTomTomData;
  final bool hasTimeRestriction;
  final RouteResult? dirtRoadAlternative;
  final List<SpeedLimitSpan> speedLimits;

  const RouteResult({
    required this.polylinePoints,
    required this.distanceMeters,
    required this.durationSeconds,
    this.maneuvers            = const [],
    this.restrictionsAvoided  = const [],
    this.restrictionsBlocked  = const [],
    this.usedTomTomData       = false,
    this.hasTimeRestriction   = false,
    this.dirtRoadAlternative  ,
    this.speedLimits          = const [],
  });

  RouteResult copyWith({
    List<LatLng>? polylinePoints,
    int? distanceMeters,
    int? durationSeconds,
    List<RouteManeuver>? maneuvers,
    List<BridgeRestriction>? restrictionsAvoided,
    List<BridgeRestriction>? restrictionsBlocked,
    bool? usedTomTomData,
    bool? hasTimeRestriction,
    RouteResult? dirtRoadAlternative,
    List<SpeedLimitSpan>? speedLimits,
  }) => RouteResult(
    polylinePoints:      polylinePoints      ?? this.polylinePoints,
    distanceMeters:      distanceMeters      ?? this.distanceMeters,
    durationSeconds:     durationSeconds     ?? this.durationSeconds,
    maneuvers:           maneuvers           ?? this.maneuvers,
    restrictionsAvoided: restrictionsAvoided ?? this.restrictionsAvoided,
    restrictionsBlocked: restrictionsBlocked ?? this.restrictionsBlocked,
    usedTomTomData:      usedTomTomData      ?? this.usedTomTomData,
    hasTimeRestriction:  hasTimeRestriction  ?? this.hasTimeRestriction,
    dirtRoadAlternative: dirtRoadAlternative ?? this.dirtRoadAlternative,
    speedLimits:         speedLimits         ?? this.speedLimits,
  );

  /// Limite de caminhão vigente em [polylineIdx]: o último span cujo offset
  /// já começou (offset <= idx). Null quando a rota não trouxe dados de limite.
  int? limitAt(int polylineIdx) {
    int? kmh;
    for (final s in speedLimits) {
      if (s.offset > polylineIdx) break;
      kmh = s.kmh;
    }
    return kmh;
  }

  /// Maior limite de caminhão da rota — usado no resumo/compartilhar.
  int? get maxTruckSpeedKmh {
    if (speedLimits.isEmpty) return null;
    var m = 0;
    for (final s in speedLimits) {
      if (s.kmh > m) m = s.kmh;
    }
    return m;
  }

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
