import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/services/here_geocoding_service.dart';

// P0 de campo 01/07 (Extrema-MG): "Fernão Dias km 936" caía ~2 km antes do
// destino. O fix manda esse formato pra Google — mas a Google só acerta quando
// tem o marco indexado. Os casos abaixo são respostas REAIS medidas em
// 2026-07-31, não inventadas: sem este gate, o `GEOMETRIC_CENTER` da BR-116
// entraria no TOPO das sugestões apontando pra Minas Gerais, ~600 km fora.
void main() {
  group('acceptsKmResult', () {
    test('ROOFTOP citando o mesmo km: aceita', () {
      expect(
        HereGeocodingService.acceptsKmResult(
          'Rodovia Castelo Branco km 60, Sorocaba SP',
          'ROOFTOP',
          'Rod. Pres. Castello Branco, km 60 - São Roque, SP',
        ),
        isTrue,
      );
    });

    test('GEOMETRIC_CENTER é o centro da via, não o marco: rejeita', () {
      // Resposta real: -18.67/-41.98, em MG, ~600 km de Jacareí.
      expect(
        HereGeocodingService.acceptsKmResult(
          'BR-116 km 210, Jacareí SP',
          'GEOMETRIC_CENTER',
          'BR-116, São Paulo, Brasil',
        ),
        isFalse,
      );
    });

    test('ROOFTOP num endereço que não é o km pedido: rejeita', () {
      // Resposta real de "Imigrantes km 28": casou com uma avenida qualquer.
      expect(
        HereGeocodingService.acceptsKmResult(
          'Rodovia dos Imigrantes km 28, Sao Bernardo',
          'ROOFTOP',
          'Av. Sapopemba, 25720a - Jardim Santo Andre, São Paulo',
        ),
        isFalse,
      );
    });

    test('km diferente do pedido: rejeita', () {
      expect(
        HereGeocodingService.acceptsKmResult(
          'Rodovia Anhanguera km 100',
          'ROOFTOP',
          'Rod. Anhanguera, km 10 - Osasco, SP',
        ),
        isFalse,
      );
    });

    test('APPROXIMATE: rejeita', () {
      expect(
        HereGeocodingService.acceptsKmResult(
          'Rodovia Anhanguera km 100',
          'APPROXIMATE',
          'Rod. Anhanguera, km 100',
        ),
        isFalse,
      );
    });

    test('"KM 936+700": compara só o inteiro do marco', () {
      expect(
        HereGeocodingService.acceptsKmResult(
          'Rodovia Fernão Dias KM 936+700',
          'ROOFTOP',
          'Rod. Fernão Dias, Km 936, Extrema - MG',
        ),
        isTrue,
      );
    });

    test('resposta sem km nenhum: rejeita', () {
      expect(
        HereGeocodingService.acceptsKmResult(
          'Rodovia Marechal Rondon km 300',
          'ROOFTOP',
          'Rod. Marechal Rondon, Castilho - SP',
        ),
        isFalse,
      );
    });
  });
}
