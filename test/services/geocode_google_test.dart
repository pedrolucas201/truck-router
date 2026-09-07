import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/services/here_geocoding_service.dart';

/// Gate do resultado da Google pra endereço com número de casa.
///
/// Caso de origem (Beto, 2026-09-05): "rua Antônio Ailton Carvalhal, 36
/// Caçapava". Medido com as chaves reais em 07/09:
///  - HERE, TomTom e OSM não têm a rua (só os Correios: CEP 12280-244). A HERE
///    devolveu "Rua Antônia Helena de Carvalho Souza, 35" em 1º e o Beto
///    navegou pra lá.
///  - Google: `route` GEOMETRIC_CENTER "R Antonio Ailton Carvalhal - Jardim
///    Campo Grande, Caçapava - SP, 12280-244, Brasil", partial_match=true
///    (o 36 não existe pra ela, a rua sim) → partial_match NÃO serve de gate.
void main() {
  const carvalhal =
      'R Antonio Ailton Carvalhal - Jardim Campo Grande, Caçapava - SP, 12280-244, Brasil';
  const route = ['route'];

  group('acceptsAddressResult', () {
    test('o caso do Beto: rua certa sem o número, acento diferente → aceita', () {
      expect(
        HereGeocodingService.acceptsAddressResult(
            'rua Antônio Ailton Carvalhal, 36 Caçapava', 'GEOMETRIC_CENTER', carvalhal, route),
        isTrue,
      );
    });

    test('fuzzy de rua parecida (o que a HERE mostrou) → rejeita', () {
      expect(
        HereGeocodingService.acceptsAddressResult(
            'rua Antônio Ailton Carvalhal, 36 Caçapava',
            'ROOFTOP',
            'Rua Antônia Helena de Carvalho Souza, 35, Caçapava - SP, Brasil',
            ['street_address']),
        isFalse,
      );
    });

    test('só achou a cidade (APPROXIMATE / locality) → rejeita', () {
      expect(
        HereGeocodingService.acceptsAddressResult(
            'Rua Um, 36 Caçapava', 'APPROXIMATE', 'Caçapava - SP, Brasil', ['locality', 'political']),
        isFalse,
      );
      expect(
        HereGeocodingService.acceptsAddressResult(
            'Rua Antônio Ailton Carvalhal, 36 Caçapava', 'GEOMETRIC_CENTER',
            'Caçapava - SP, 12280-244, Brasil', ['postal_code']),
        isFalse,
      );
    });

    test('abreviação da Google não derruba: "Avenida"/"Doutor" × "Av."/"Dr."', () {
      expect(
        HereGeocodingService.acceptsAddressResult(
            'Avenida Doutor Nelson d\'Ávila, 1000 São José dos Campos', 'ROOFTOP',
            'Av. Dr. Nelson D\'Ávila, 1000 - Jardim São Dimas, São José dos Campos - SP, 12245-030, Brasil',
            ['street_address']),
        isTrue,
      );
    });

    test('consulta sem palavra conferível ("Rua Um, 36") → rejeita por segurança', () {
      expect(
        HereGeocodingService.acceptsAddressResult(
            'Rua Um, 36', 'GEOMETRIC_CENTER', 'R. Dois - Centro, Caçapava - SP, Brasil', route),
        isFalse,
      );
    });

    test('ROOFTOP com número exato → aceita', () {
      expect(
        HereGeocodingService.acceptsAddressResult(
            'Rua Guaianases, 1448', 'ROOFTOP',
            'R. dos Guaianases, 1448 - Campos Elíseos, São Paulo - SP, 01204-001, Brasil',
            ['street_address']),
        isTrue,
      );
    });
  });
}
