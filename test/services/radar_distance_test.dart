import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/services/radar_service.dart';

void main() {
  // distanceToSegment = distância perpendicular (em metros) de um ponto ao
  // SEGMENTO da rota (não a um ponto solto). É o que diferencia "na via" de
  // "na rua paralela": a separação entre ruas vira a distância medida.
  group('distanceToSegment', () {
    // Segmento leste-oeste em lat -23.5000, de lng -46.6010 a -46.5990 (~200 m).
    const aLat = -23.5000, aLng = -46.6010;
    const bLat = -23.5000, bLng = -46.5990;

    test('ponto sobre o segmento → ~0 m', () {
      final d = RadarService.distanceToSegment(-23.5000, -46.6000, aLat, aLng, bLat, bLng);
      expect(d, lessThan(1.0));
    });

    test('ponto 0.0002° ao norte do meio → ~22 m perpendicular', () {
      // 0.0002° de latitude ≈ 22,3 m.
      final d = RadarService.distanceToSegment(-23.4998, -46.6000, aLat, aLng, bLat, bLng);
      expect(d, closeTo(22.3, 1.5));
    });

    test('ponto além da ponta leste → mede até a ponta (clamp no segmento)', () {
      // 0.001° de lng a oeste de b, mesma latitude ≈ 102 m até b.
      final d = RadarService.distanceToSegment(-23.5000, -46.5980, aLat, aLng, bLat, bLng);
      expect(d, closeTo(102, 8));
    });
  });
}
