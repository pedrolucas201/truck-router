import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Cópia local da fórmula usada em _segmentBearing — testa o algoritmo isolado.
double segmentBearing(List<LatLng> pts, int idx) {
  if (pts.length < 2) return 0;
  final i = idx.clamp(0, pts.length - 2);
  final a = pts[i];
  final b = pts[i + 1];
  final dLng = (b.longitude - a.longitude) * pi / 180;
  final lat1 = a.latitude * pi / 180;
  final lat2 = b.latitude * pi / 180;
  final y = sin(dLng) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
  return (atan2(y, x) * 180 / pi + 360) % 360;
}

void main() {
  group('segmentBearing — bearing do segmento de polilinha', () {
    test('norte: lat cresce, lng constante → 0°', () {
      final pts = [const LatLng(0, 0), const LatLng(1, 0)];
      expect(segmentBearing(pts, 0), closeTo(0, 0.5));
    });

    test('leste: lng cresce, lat constante → 90°', () {
      final pts = [const LatLng(0, 0), const LatLng(0, 1)];
      expect(segmentBearing(pts, 0), closeTo(90, 0.5));
    });

    test('sul: lat decresce → 180°', () {
      final pts = [const LatLng(1, 0), const LatLng(0, 0)];
      expect(segmentBearing(pts, 0), closeTo(180, 0.5));
    });

    test('oeste: lng decresce → 270°', () {
      final pts = [const LatLng(0, 1), const LatLng(0, 0)];
      expect(segmentBearing(pts, 0), closeTo(270, 0.5));
    });

    test('lista vazia → 0 sem crash', () {
      expect(segmentBearing([], 0), equals(0));
    });

    test('lista com 1 ponto → 0 sem crash', () {
      final pts = [const LatLng(-23.5, -46.6)];
      expect(segmentBearing(pts, 0), equals(0));
    });

    test('idx fora do range → clamp no último segmento válido', () {
      final pts = [
        const LatLng(0, 0),
        const LatLng(0, 1),
        const LatLng(0, 2),
      ];
      expect(segmentBearing(pts, 5), closeTo(segmentBearing(pts, 1), 0.001));
    });
  });
}
