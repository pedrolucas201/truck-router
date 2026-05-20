import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'truck_profile.dart';

enum PoiCategory { fuel, scale, restArea }

class Poi {
  final String name;
  final PoiCategory category;
  final LatLng position;
  final String? description;
  final int? maxHeightCm;
  final int? maxLengthCm;
  final int? maxWeightKg;
  final bool hasDiesel;

  const Poi({
    required this.name,
    required this.category,
    required this.position,
    this.description,
    this.maxHeightCm,
    this.maxLengthCm,
    this.maxWeightKg,
    this.hasDiesel = false,
  });

  bool isCompatibleWith(TruckProfile truck) {
    if (maxHeightCm != null && truck.heightCm > maxHeightCm!) return false;
    if (maxLengthCm != null && truck.lengthCm > maxLengthCm!) return false;
    if (maxWeightKg != null && truck.weightKg > maxWeightKg!) return false;
    return true;
  }

  String? incompatibilityReason(TruckProfile truck) {
    if (maxHeightCm != null && truck.heightCm > maxHeightCm!) {
      return 'Altura do caminhão (${truck.heightCm}cm) excede o teto máximo (${maxHeightCm}cm)';
    }
    if (maxLengthCm != null && truck.lengthCm > maxLengthCm!) {
      return 'Comprimento do caminhão (${truck.lengthCm}cm) excede o máximo (${maxLengthCm}cm)';
    }
    if (maxWeightKg != null && truck.weightKg > maxWeightKg!) {
      return 'Peso do caminhão (${truck.weightKg}kg) excede o limite (${maxWeightKg}kg)';
    }
    return null;
  }

  String get categoryLabel => switch (category) {
        PoiCategory.fuel     => 'Posto de Combustível',
        PoiCategory.scale    => 'Balança DNIT',
        PoiCategory.restArea => 'Área de Descanso',
      };
}
