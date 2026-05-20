import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class WaypointEntry {
  final String label;
  final LatLng position;

  const WaypointEntry({required this.label, required this.position});

  Map<String, dynamic> toJson() => {
    'label': label,
    'lat':   position.latitude,
    'lng':   position.longitude,
  };

  factory WaypointEntry.fromJson(Map<String, dynamic> j) => WaypointEntry(
    label:    j['label'] as String,
    position: LatLng(j['lat'] as double, j['lng'] as double),
  );
}

class RouteHistory {
  final String originLabel;
  final LatLng originPosition;
  final List<WaypointEntry> waypoints;
  final String destinationLabel;
  final LatLng destinationPosition;
  final DateTime? departureTime;
  final String distanceText;
  final String durationText;
  final DateTime calculatedAt;

  const RouteHistory({
    required this.originLabel,
    required this.originPosition,
    required this.waypoints,
    required this.destinationLabel,
    required this.destinationPosition,
    this.departureTime,
    required this.distanceText,
    required this.durationText,
    required this.calculatedAt,
  });

  Map<String, dynamic> toJson() => {
    'originLabel':        originLabel,
    'originLat':          originPosition.latitude,
    'originLng':          originPosition.longitude,
    'waypoints':          waypoints.map((w) => w.toJson()).toList(),
    'destinationLabel':   destinationLabel,
    'destinationLat':     destinationPosition.latitude,
    'destinationLng':     destinationPosition.longitude,
    'departureTime':      departureTime?.toIso8601String(),
    'distanceText':       distanceText,
    'durationText':       durationText,
    'calculatedAt':       calculatedAt.toIso8601String(),
  };

  factory RouteHistory.fromJson(Map<String, dynamic> j) => RouteHistory(
    originLabel:         j['originLabel'] as String,
    originPosition:      LatLng(j['originLat'] as double, j['originLng'] as double),
    waypoints:           (j['waypoints'] as List<dynamic>)
        .map((w) => WaypointEntry.fromJson(w as Map<String, dynamic>))
        .toList(),
    destinationLabel:    j['destinationLabel'] as String,
    destinationPosition: LatLng(j['destinationLat'] as double, j['destinationLng'] as double),
    departureTime:       j['departureTime'] != null
        ? DateTime.parse(j['departureTime'] as String)
        : null,
    distanceText:        j['distanceText'] as String,
    durationText:        j['durationText'] as String,
    calculatedAt:        DateTime.parse(j['calculatedAt'] as String),
  );

  static List<RouteHistory> listFromJson(String raw) =>
      (jsonDecode(raw) as List<dynamic>)
          .map((e) => RouteHistory.fromJson(e as Map<String, dynamic>))
          .toList();

  static String listToJson(List<RouteHistory> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());
}
