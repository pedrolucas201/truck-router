import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/utils/truck_glyph.dart';

void main() {
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
