import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Bounding box (min/max de lat e lng) de uma lista de pontos.
/// Pré-condição: [points] não vazia — todos os callers já checam isEmpty antes.
({double minLat, double maxLat, double minLng, double maxLng}) boundsOf(
    List<LatLng> points) {
  var minLat = points[0].latitude, maxLat = points[0].latitude;
  var minLng = points[0].longitude, maxLng = points[0].longitude;
  for (final p in points) {
    if (p.latitude < minLat) minLat = p.latitude;
    if (p.latitude > maxLat) maxLat = p.latitude;
    if (p.longitude < minLng) minLng = p.longitude;
    if (p.longitude > maxLng) maxLng = p.longitude;
  }
  return (minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng);
}
