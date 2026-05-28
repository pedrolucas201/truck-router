import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'truck_profile.dart';

class BridgeRestriction {
  final String? id;
  final double lat;
  final double lng;
  final String type;   // 'maxheight' | 'maxweight' | 'maxwidth'
  final double value;  // metros para altura/largura; toneladas para peso
  final String? roadName;
  final int confirmedBy;

  const BridgeRestriction({
    this.id,
    required this.lat,
    required this.lng,
    required this.type,
    required this.value,
    this.roadName,
    this.confirmedBy = 0,
  });

  bool get isVerified => confirmedBy >= 3;

  LatLng get position => LatLng(lat, lng);

  bool conflictsWith(TruckProfile truck) => switch (type) {
        'maxheight' => truck.heightCm / 100.0 >= value,
        'maxweight' => truck.weightKg / 1000.0 >= value,
        'maxwidth'  => truck.widthCm  / 100.0 >= value,
        'dirtroad'  => true,  // todo caminhão evita estrada de terra não-mapeada
        _           => false,
      };

  String get label => switch (type) {
        'maxheight' => 'Altura máx. ${value.toStringAsFixed(1)} m',
        'maxweight' => 'Peso máx. ${value.toStringAsFixed(0)} t',
        'maxwidth'  => 'Largura máx. ${value.toStringAsFixed(1)} m',
        'dirtroad'  => 'Estrada de terra / sem pavimento',
        _           => 'Restrição',
      };

  // Gera um bbox ~100m ao redor da restrição para o parâmetro avoid[areas] do HERE.
  String toAvoidArea() {
    const deltaLat = 0.0009; // ≈ 100 m
    const deltaLng = 0.0010; // ≈ 100 m na latitude do Brasil
    final s = lat - deltaLat;
    final w = lng - deltaLng;
    final n = lat + deltaLat;
    final e = lng + deltaLng;
    return 'bbox:$s,$w,$n,$e';
  }
}
