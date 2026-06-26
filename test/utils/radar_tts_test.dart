import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/utils/radar_tts.dart';

void main() {
  group('radarAlertPhrase', () {
    test('com limite cadastrado → "Radar de X à frente"', () {
      expect(radarAlertPhrase(60), 'Radar de 60 à frente');
      expect(radarAlertPhrase(110), 'Radar de 110 à frente');
    });

    test('sem limite (0) → "Radar à frente"', () {
      expect(radarAlertPhrase(0), 'Radar à frente');
    });
  });
}
