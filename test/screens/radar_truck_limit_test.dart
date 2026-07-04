import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/screens/navigation_screen.dart';

// Radar tem que avisar no limite de CAMINHÃO, nunca no de carro (report Gilberto
// 2026-07-03: Dom Pedro postava 110 do carro, caminhão é 90). Regra = o mais
// restritivo entre o postado no radar e o limite de caminhão do trecho.
void main() {
  test('radar de carro (110) + trecho caminhão (90) → 90', () {
    expect(truckRadarLimit(110, 90), 90);
  });

  test('radar mais baixo que o trecho (60 numa via de 90) → 60', () {
    expect(truckRadarLimit(60, 90), 60);
  });

  test('radar sem velocidade postada (0) → cai no limite do trecho', () {
    expect(truckRadarLimit(0, 90), 90);
  });

  test('radar de carro (110) sem dado do trecho → capado no teto de caminhão (90)', () {
    expect(truckRadarLimit(110, null), 90);
  });

  test('nunca acima do teto de caminhão, mesmo com os dois altos (120/100 → 90)', () {
    expect(truckRadarLimit(120, 100), kTruckCapKmh);
  });

  test('nenhum dado → null (chamador aplica piso)', () {
    expect(truckRadarLimit(0, null), isNull);
  });
}
