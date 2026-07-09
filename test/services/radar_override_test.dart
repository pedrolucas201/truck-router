import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/radar_point.dart';
import 'package:truck_router/services/firestore_radar_service.dart';

// Verdicto do curador ganha do dado bruto (CSV/crowd): remove, troca a velocidade
// ou confirma. Casa por chave exata de localização.
void main() {
  RadarPoint radar(double lat, double lng, int speed) =>
      RadarPoint(lat: lat, lng: lng, type: 'Radar', speedKmh: speed);

  test('exists=false remove o radar', () {
    final r = radar(-8.12419, -35.31299, 60);
    final ov = {dismissalKey(-8.12419, -35.31299): const RadarOverride(false, 0)};
    expect(applyOverrides([r], ov), isEmpty);
  });

  test('exists=true com velocidade troca a velocidade', () {
    final r = radar(-8.12419, -35.31299, 60);
    final ov = {dismissalKey(-8.12419, -35.31299): const RadarOverride(true, 80)};
    expect(applyOverrides([r], ov).single.speedKmh, 80);
  });

  test('exists=true sem velocidade (0) mantém intacto', () {
    final r = radar(-8.12419, -35.31299, 60);
    final ov = {dismissalKey(-8.12419, -35.31299): const RadarOverride(true, 0)};
    expect(applyOverrides([r], ov).single.speedKmh, 60);
  });

  test('sem override → radar intacto', () {
    final r = radar(-8.12419, -35.31299, 60);
    expect(applyOverrides([r], const {}).single.speedKmh, 60);
  });

  test('casa por chave exata — não afeta vizinho longe', () {
    final r = radar(-8.20000, -35.40000, 60);
    final ov = {dismissalKey(-8.12419, -35.31299): const RadarOverride(false, 0)};
    expect(applyOverrides([r], ov).length, 1);
  });
}
