import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'bridge_restriction.dart';

class UserRestriction {
  final double lat;
  final double lng;
  final String type; // 'maxheight' | 'maxweight' | 'maxwidth'
  final double value; // metros (height/width) | toneladas (weight)
  final DateTime createdAt;
  final int confirmedBy;

  const UserRestriction({
    required this.lat,
    required this.lng,
    required this.type,
    required this.value,
    required this.createdAt,
    this.confirmedBy = 0,
  });

  bool get isVerified => confirmedBy >= 3;

  LatLng get position => LatLng(lat, lng);

  BridgeRestriction toBridgeRestriction() => BridgeRestriction(
        lat: lat,
        lng: lng,
        type: type,
        value: value,
      );

  String get fullLabel => switch (type) {
        'maxheight' => 'Altura máx. ${value.toStringAsFixed(1)} m',
        'maxweight' => 'Peso máx. ${value.toStringAsFixed(0)} t',
        'maxwidth'  => 'Largura máx. ${value.toStringAsFixed(1)} m',
        'dirtroad'  => 'Estrada de terra / sem pavimento',
        _           => 'Restrição',
      };

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'type': type,
        'value': value,
        'createdAt': createdAt.toIso8601String(),
        'confirmedBy': confirmedBy,
      };

  factory UserRestriction.fromJson(Map<String, dynamic> json) => UserRestriction(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        type: json['type'] as String,
        value: (json['value'] as num).toDouble(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        confirmedBy: (json['confirmedBy'] as num?)?.toInt() ?? 0,
      );
}
