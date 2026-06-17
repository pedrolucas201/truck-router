import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/truck_profile.dart';
import 'package:truck_router/utils/truck_glyph.dart';

TruckProfile _profile(int lengthCm) => TruckProfile(
      id: 't',
      name: 'Teste',
      heightCm: 420,
      lengthCm: lengthCm,
      weightKg: 25000,
    );

void main() {
  group('glyphForProfile', () {
    test('comprimento abaixo do limiar (999) → baú', () {
      expect(glyphForProfile(_profile(999)), TruckGlyph.bau);
    });
    test('comprimento no limiar (1000) → carreta', () {
      expect(glyphForProfile(_profile(1000)), TruckGlyph.carreta);
    });
    test('default do app (1400) → carreta', () {
      expect(glyphForProfile(_profile(1400)), TruckGlyph.carreta);
    });
    test('perfil pequeno (600) → baú', () {
      expect(glyphForProfile(_profile(600)), TruckGlyph.bau);
    });
  });

  group('assetFor', () {
    test('baú → caminho do baú', () {
      expect(assetFor(TruckGlyph.bau), 'assets/loader/truck_bau.svg');
    });
    test('carreta → caminho da carreta', () {
      expect(assetFor(TruckGlyph.carreta), 'assets/loader/truck_carreta.svg');
    });
  });
}
