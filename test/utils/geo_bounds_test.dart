import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/utils/geo_bounds.dart';

void main() {
  group('boundsOf', () {
    test('ponto único → min == max', () {
      final b = boundsOf([const LatLng(-8.13, -35.29)]);
      expect(b.minLat, -8.13);
      expect(b.maxLat, -8.13);
      expect(b.minLng, -35.29);
      expect(b.maxLng, -35.29);
    });

    test('múltiplos pontos → extremos corretos (ordem não importa)', () {
      final b = boundsOf(const [
        LatLng(-8.0, -35.0),
        LatLng(-9.5, -34.0),
        LatLng(-7.2, -36.1),
      ]);
      expect(b.minLat, -9.5);
      expect(b.maxLat, -7.2);
      expect(b.minLng, -36.1);
      expect(b.maxLng, -34.0);
    });
  });
}
