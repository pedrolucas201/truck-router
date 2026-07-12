import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/widgets/nav/nav_ui_defs.dart';

// Na área de radar, a "velocidade permitida" é a POSTADA no radar (curada pelo
// Gilberto), capada no teto de caminhão. NÃO usa mais o limite do trecho da HERE
// (report Gilberto 2026-07-09: HERE cravava 40 numa via de 90 → flash piscava a
// 64 do lado de um radar de 90). Ainda protege contra placa de carro (110 → 90).
void main() {
  test('radar de carro (110) → capado no teto de caminhão (90)', () {
    expect(truckRadarLimit(110), 90);
  });

  test('radar de 60 → 60 (não é mais rebaixado por HERE nem elevado)', () {
    expect(truckRadarLimit(60), 60);
  });

  test('radar de 90 → 90 (não pisca a 64 mesmo com HERE cravando 40)', () {
    expect(truckRadarLimit(90), 90);
  });

  test('nunca acima do teto de caminhão (120 → 90)', () {
    expect(truckRadarLimit(120), kTruckCapKmh);
  });

  test('radar sem velocidade postada (0) → null (chamador mostra "Radar"/teto)', () {
    expect(truckRadarLimit(0), isNull);
  });
}
