import 'package:flutter_test/flutter_test.dart';

// Cópia local da fórmula usada em _animateMarkerTo — testa o algoritmo isolado.
double bearingDelta(double from, double to) => ((to - from + 540) % 360) - 180;

void main() {
  group('bearingDelta — caminho mínimo de rotação', () {
    test('giro positivo simples', () {
      expect(bearingDelta(10, 80), closeTo(70, 0.001));
    });

    test('giro negativo simples', () {
      expect(bearingDelta(80, 10), closeTo(-70, 0.001));
    });

    test('wrap 355 → 5: deve girar +10, não −350', () {
      expect(bearingDelta(355, 5), closeTo(10, 0.001));
    });

    test('wrap 5 → 355: deve girar −10, não +350', () {
      expect(bearingDelta(5, 355), closeTo(-10, 0.001));
    });

    test('sem mudança', () {
      expect(bearingDelta(90, 90), closeTo(0, 0.001));
    });

    test('180 graus: caminho mínimo é 180 (qualquer sentido aceito)', () {
      expect(bearingDelta(0, 180).abs(), closeTo(180, 0.001));
    });
  });
}
