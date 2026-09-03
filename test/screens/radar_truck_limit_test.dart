import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/radar_point.dart';
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

  // truckKmh = o número que ícone, balão, chip e voz mostram/falam. Um só.
  // Regressão do drive 2026-09-02: ícone dizia 100 (placa de carro), barra 90.
  RadarPoint rp(int speed, {int? off, String type = 'Radar Fixo - 100 kmh'}) =>
      RadarPoint(lat: 0, lng: 0, type: type, speedKmh: speed, truckLimitOff: off);

  group('RadarPoint.truckKmh (fonte única do número na tela e na voz)', () {
    test('placa de carro 110 → 90', () => expect(rp(110).truckKmh, 90));
    test('placa 100 com oficial 80 → 80', () => expect(rp(100, off: 80).truckKmh, 80));
    test('placa 0 com oficial 80 → 80 (mostra número onde antes era bolinha)',
        () => expect(rp(0, off: 80).truckKmh, 80));
    test('placa 0 sem oficial → null', () => expect(rp(0).truckKmh, isNull));
    test('placa 60 → 60 (cidade não muda)', () => expect(rp(60).truckKmh, 60));
  });

  group('RadarPoint.isMovel', () {
    test('"Radar Movel - 100 kmh" do CSV → móvel',
        () => expect(rp(100, type: 'Radar Movel - 100 kmh').isMovel, isTrue));
    test('"Radar Fixo" e crowd "Radar" → não',
        () {
      expect(rp(100).isMovel, isFalse);
      expect(rp(60, type: 'Radar').isMovel, isFalse);
    });
  });
}
