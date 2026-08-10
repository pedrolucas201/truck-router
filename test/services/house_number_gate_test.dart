import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/services/here_geocoding_service.dart';

/// Gate do número de casa.
///
/// Caso de origem (Gilberto, 2026-08-10): buscar "rua guaianases, 1448" devolvia
/// o 1448 de TUPÃ, 600 km longe, e São Paulo só aparecia como rua — 975 m do
/// número que ele precisava, no centro de São Paulo, de caminhão.
///
/// Medido na chave real naquele dia:
///  - HERE texto livre .............. só Tupã, mesmo digitando "são paulo" junto
///  - HERE com `at` na posição dele .. sobe SP no ranking, nunca dá o número
///  - HERE `qq=` com city explícita .. acerta (mas o motorista não digita cidade)
///  - Nominatim/OSM, sem cidade ...... acerta: -23.5302717,-46.6482871
///
/// Estes testes cobrem as duas decisões puras: QUANDO consultar o OSM e QUANDO
/// o resultado dele entra na lista.
void main() {
  group('houseNumberOf — quando o OSM é consultado', () {
    test('número depois de vírgula: o caso do Gilberto', () {
      expect(HereGeocodingService.houseNumberOf('rua guaianases, 1448'), '1448');
    });

    test('número fechando a busca, sem vírgula', () {
      expect(HereGeocodingService.houseNumberOf('av paulista 1000'), '1000');
    });

    test('número no meio do nome da rua NÃO é número de casa', () {
      // Se casasse aqui, toda "Rua 25 de Março" gastaria uma consulta à toa e
      // ainda poderia sugerir o número 25 como se fosse o destino.
      expect(HereGeocodingService.houseNumberOf('rua 25 de março'), isNull);
    });

    test('nome de rua com número E número de casa: vale o número de casa', () {
      expect(HereGeocodingService.houseNumberOf('rua 25 de março, 100'), '100');
    });

    test('cidade depois do número não atrapalha', () {
      expect(HereGeocodingService.houseNumberOf('rua guaianases, 1448, sao paulo'),
          '1448');
    });

    test('km de rodovia não é número de casa', () {
      // Tem dono próprio (marco do SNV/DNIT). Se caísse aqui, o OSM seria
      // consultado em toda busca de rodovia sem nenhuma chance de acertar.
      expect(HereGeocodingService.houseNumberOf('fernão dias km 936'), isNull);
      expect(HereGeocodingService.houseNumberOf('br-116 km 230'), isNull);
    });

    test('CEP não é número de casa', () {
      expect(HereGeocodingService.houseNumberOf('01204-002'), isNull);
      expect(HereGeocodingService.houseNumberOf('01204002'), isNull);
    });

    test('busca sem número não consulta o OSM', () {
      expect(HereGeocodingService.houseNumberOf('rua guaianases'), isNull);
      expect(HereGeocodingService.houseNumberOf('posto graal'), isNull);
    });
  });

  group('labelHasHouseNumber — quando o resultado do OSM entra', () {
    // Rótulos reais devolvidos pela API em 2026-08-10.
    const tupa =
        'Rua Guaianases, 1448, Centro, Tupã - SP, 17600-390, Brasil';
    const ruaSemNumero = 'Rua Guaianases, São Paulo - SP, Brasil';
    const osmSaoPaulo = 'Rua Guaianases, 1448, Campos Elísios, São Paulo - SP';

    test('a HERE já trouxe o número: o OSM não precisa entrar', () {
      expect(HereGeocodingService.labelHasHouseNumber(tupa, '1448'), isTrue);
    });

    test('sugestão de rua sem número: é o buraco que o OSM preenche', () {
      expect(HereGeocodingService.labelHasHouseNumber(ruaSemNumero, '1448'),
          isFalse);
    });

    test('o resultado do OSM é reconhecido como tendo o número', () {
      expect(HereGeocodingService.labelHasHouseNumber(osmSaoPaulo, '1448'),
          isTrue);
    });

    test('não casa número contido em outro maior', () {
      expect(
          HereGeocodingService.labelHasHouseNumber(
              'Rua X, 14480, Centro, Tupã - SP', '1448'),
          isFalse);
    });

    test('não casa o número dentro de um CEP', () {
      // "..., 17600-390, ..." não pode contar como "casa 17600" — contaria como
      // "a HERE já trouxe o número" e mataria a consulta ao OSM em silêncio.
      expect(HereGeocodingService.labelHasHouseNumber(tupa, '17600'), isFalse);
    });

    test('NÃO compara nome de rua — o S/Z é a razão de tudo isto existir', () {
      // Em São Paulo a HERE guarda os números sob "Rua dos Guaianazes" (com Z) e
      // a busca do motorista é "Rua Guaianases" (com S). Um guard por nome de rua
      // reprovaria exatamente o caso que este código conserta.
      expect(
          HereGeocodingService.labelHasHouseNumber(
              'Rua dos Guaianazes, 1448, Santa Cecília, São Paulo - SP', '1448'),
          isTrue);
    });
  });
}
