import 'package:flutter/material.dart';
import '../models/route_event.dart';

/// Estilo de apresentação por tipo de evento — fonte única compartilhada pela
/// faixa do próximo evento (NextEventStrip) e pelos pontinhos (UpcomingDots).
/// Ícones Material são o set definitivo do V2.
extension RouteEventStyle on RouteEventType {
  IconData get icon => switch (this) {
        RouteEventType.radar       => Icons.camera_alt,
        RouteEventType.restriction => Icons.warning_amber_rounded,
        RouteEventType.police      => Icons.local_police,
        RouteEventType.scale       => Icons.monitor_weight,
        RouteEventType.restArea    => Icons.local_hotel,
        RouteEventType.weather     => Icons.thunderstorm,
      };

  Color get accentColor => switch (this) {
        RouteEventType.radar       => Colors.red.shade600,
        RouteEventType.restriction => Colors.red.shade600,
        RouteEventType.police      => Colors.blue.shade600,
        RouteEventType.scale       => Colors.purple.shade600,
        RouteEventType.restArea    => Colors.green.shade600,
        RouteEventType.weather     => Colors.deepOrange.shade600,
      };

  String get label => switch (this) {
        RouteEventType.radar       => 'Radar',
        RouteEventType.restriction => 'Restrição',
        RouteEventType.police      => 'Polícia',
        RouteEventType.scale       => 'Balança',
        RouteEventType.restArea    => 'Descanso',
        RouteEventType.weather     => 'Clima',
      };
}
