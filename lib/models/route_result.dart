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

/// Nível de trânsito de um trecho (trafficSpeed vs baseSpeed da HERE).
enum TrafficLevel {
  free,
  slow,
  heavy;

  /// Classifica pela razão trafficSpeed/baseSpeed: >=0.85 flui, >=0.5 lento,
  /// abaixo é pesado/parado.
  static TrafficLevel fromRatio(double ratio) => ratio >= 0.85
      ? TrafficLevel.free
      : ratio >= 0.5
          ? TrafficLevel.slow
          : TrafficLevel.heavy;
}

/// Trânsito por trecho a partir de um offset da polyline. `free` não é pintado
/// (a linha base já aparece) — só `slow` (laranja) e `heavy` (vermelho).
class TrafficSpan {
  final int offset;
  final TrafficLevel level;
  const TrafficSpan(this.offset, this.level);
}

/// Ponto no mapa onde a HERE reportou uma restrição de caminhão VIOLADA
/// (altura/peso/comprimento/horário/acesso proibido). O notice em si não traz
/// coordenada — vem do cruzamento `spans=notices` (o span referencia o notice
/// por índice e traz o offset na polyline). `position` = início do trecho
/// restrito; `label` = texto pronto pro usuário. Antes o app só falava/piscava
/// um banner sem dizer ONDE (report Gilberto 12/07).
class RestrictionPoint {
  final LatLng position;
  final String label;
  const RestrictionPoint(this.position, this.label);
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
  // Texto do TIPO/limite da restrição (ex "Comprimento máx 7,2 m", "Por horário"),
  // montado do `details` do notice da HERE — o `title` vem inútil ("Violated
  // vehicle restriction." em inglês genérico). Null = cai no texto genérico.
  final String? restrictionLabel;
  // O trecho proibido alcança o DESTINO (não é restrição de passagem): o
  // caminhão não consegue encostar no ponto pedido. Quando true, o
  // `restrictionLabel` é específico e nomeia a distância — pode ir pra voz.
  // Nos demais casos o label é de dimensão ("altura máx 3,5 m") e a voz mantém
  // a frase genérica: abreviação de unidade em TTS é loteria.
  final bool destinationBlocked;
  // Pontos no mapa das restrições violadas (cada uma com seu LatLng + rótulo).
  final List<RestrictionPoint> restrictionPoints;
  final RouteResult? dirtRoadAlternative;
  final List<SpeedLimitSpan> speedLimits;
  final List<TrafficSpan> trafficSpans;

  const RouteResult({
    required this.polylinePoints,
    required this.distanceMeters,
    required this.durationSeconds,
    this.maneuvers            = const [],
    this.restrictionsAvoided  = const [],
    this.restrictionsBlocked  = const [],
    this.usedTomTomData       = false,
    this.hasTimeRestriction   = false,
    this.restrictionLabel     ,
    this.destinationBlocked   = false,
    this.restrictionPoints    = const [],
    this.dirtRoadAlternative  ,
    this.speedLimits          = const [],
    this.trafficSpans         = const [],
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
    String? restrictionLabel,
    bool? destinationBlocked,
    List<RestrictionPoint>? restrictionPoints,
    RouteResult? dirtRoadAlternative,
    List<SpeedLimitSpan>? speedLimits,
    List<TrafficSpan>? trafficSpans,
  }) => RouteResult(
    polylinePoints:      polylinePoints      ?? this.polylinePoints,
    distanceMeters:      distanceMeters      ?? this.distanceMeters,
    durationSeconds:     durationSeconds     ?? this.durationSeconds,
    maneuvers:           maneuvers           ?? this.maneuvers,
    restrictionsAvoided: restrictionsAvoided ?? this.restrictionsAvoided,
    restrictionsBlocked: restrictionsBlocked ?? this.restrictionsBlocked,
    usedTomTomData:      usedTomTomData      ?? this.usedTomTomData,
    hasTimeRestriction:  hasTimeRestriction  ?? this.hasTimeRestriction,
    restrictionLabel:    restrictionLabel    ?? this.restrictionLabel,
    destinationBlocked:  destinationBlocked  ?? this.destinationBlocked,
    restrictionPoints:   restrictionPoints   ?? this.restrictionPoints,
    dirtRoadAlternative: dirtRoadAlternative ?? this.dirtRoadAlternative,
    speedLimits:         speedLimits         ?? this.speedLimits,
    trafficSpans:        trafficSpans        ?? this.trafficSpans,
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
