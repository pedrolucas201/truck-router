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

  group('kLoaderAssets', () {
    test('contém exatamente 5 assets', () {
      expect(kLoaderAssets.length, 5);
    });
    test('todos os paths começam com assets/loader/', () {
      for (final a in kLoaderAssets) {
        expect(a, startsWith('assets/loader/'));
      }
    });
    test('inclui baú, carreta, bus, minibus, tractor', () {
      expect(kLoaderAssets, contains('assets/loader/truck_bau.svg'));
      expect(kLoaderAssets, contains('assets/loader/truck_carreta.svg'));
      expect(kLoaderAssets, contains('assets/loader/bus.svg'));
      expect(kLoaderAssets, contains('assets/loader/minibus.svg'));
      expect(kLoaderAssets, contains('assets/loader/tractor.svg'));
    });
  });

  group('randomLoaderAsset', () {
    setUp(resetLoaderHistory);

    test('retorna um asset do pool', () {
      final asset = randomLoaderAsset();
      expect(kLoaderAssets, contains(asset));
    });

    test('segunda chamada não repete o mesmo asset', () {
      final first = randomLoaderAsset();
      final second = randomLoaderAsset();
      expect(second, isNot(equals(first)));
    });

    test('terceira chamada pode retornar qualquer asset exceto o segundo', () {
      randomLoaderAsset();
      final second = randomLoaderAsset();
      final third = randomLoaderAsset();
      expect(third, isNot(equals(second)));
      expect(kLoaderAssets, contains(third));
    });
  });
}
