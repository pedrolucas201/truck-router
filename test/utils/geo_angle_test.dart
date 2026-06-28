import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/utils/geo_angle.dart';

void main() {
  group('lerpAngleDeg — menor arco', () {
    test('t=0 fica na origem; t=1 chega no alvo', () {
      expect(lerpAngleDeg(40, 100, 0), closeTo(40, 1e-9));
      expect(lerpAngleDeg(40, 100, 1), closeTo(100, 1e-9));
    });

    test('interpola linear no caso simples', () {
      expect(lerpAngleDeg(0, 90, 0.5), closeTo(45, 1e-9));
    });

    test('cruza o zero pelo menor arco (350 -> 10 passa por 0, não por 180)', () {
      expect(lerpAngleDeg(350, 10, 0.5), closeTo(0, 1e-9));
    });

    test('cruza o zero no sentido inverso (10 -> 350 passa por 0)', () {
      expect(lerpAngleDeg(10, 350, 0.5), closeTo(0, 1e-9));
    });

    test('t=1 cruzando o zero chega exatamente no alvo', () {
      expect(lerpAngleDeg(350, 10, 1), closeTo(10, 1e-9));
    });

    test('rumos iguais não se movem (sem oscilação quando parado)', () {
      expect(lerpAngleDeg(123.4, 123.4, 0.2), closeTo(123.4, 1e-9));
    });

    test('resultado sempre normalizado em [0, 360)', () {
      for (final t in [0.0, 0.2, 0.5, 0.8, 1.0]) {
        final r = lerpAngleDeg(350, 10, t);
        expect(r, greaterThanOrEqualTo(0));
        expect(r, lessThan(360));
      }
    });

    test('passo pequeno (lerp de 0.2) anda no sentido certo cruzando o zero', () {
      // 350 -> 10: alvo +20° pelo menor arco; 20% disso = +4° => 354
      expect(lerpAngleDeg(350, 10, 0.2), closeTo(354, 1e-9));
    });
  });
}
