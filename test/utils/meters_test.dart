import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/utils/meters.dart';

void main() {
  test('metros com vírgula ou ponto viram cm', () {
    expect(metersToCm('4,20'), 420);
    expect(metersToCm('4.2'), 420);
    expect(metersToCm(' 14 '), 1400);
    expect(metersToCm('2,6'), 260);
  });
  test('lixo devolve null', () {
    expect(metersToCm(''), isNull);
    expect(metersToCm('abc'), isNull);
    expect(metersToCm('4,2,0'), isNull);
  });
  test('cm formata em metros com vírgula', () {
    expect(cmToMeters(420), '4,20');
    expect(cmToMeters(1400), '14,00');
  });
}
