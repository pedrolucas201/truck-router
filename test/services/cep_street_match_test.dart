import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/services/here_geocoding_service.dart';

/// Rua do ViaCEP × rua devolvida (HERE qq / TomTom structured) no fluxo do CEP.
///
/// Caso de origem (Beto, 2026-09-05, CEP 12280-244): a rua só existe nos
/// Correios. Sem o bairro no filtro, o TomTom devolvia "Rua Antônio Condino" e
/// o matcher antigo aceitava por "antônio" — pino na rua errada com o rótulo
/// certo. O passo HERE tinha o mesmo `any`, atrás de um queryScore ≥ 0.6 que
/// não mede rua.
void main() {
  const via = 'Rua Antônio Ailton Carvalhal';

  test('uma palavra em comum NÃO basta (o furo do Carvalhal)', () {
    expect(HereGeocodingService.streetMatches(via, 'Rua Antônio Condino'), isFalse);
    expect(HereGeocodingService.streetMatches(via, 'Rua Antônia Helena de Carvalho Souza'), isFalse);
  });

  test('mesma rua sem acento e com abreviação de tipo → aceita', () {
    expect(HereGeocodingService.streetMatches(via, 'Rua Antonio Ailton Carvalhal'), isTrue);
    expect(HereGeocodingService.streetMatches(via, 'R. ANTONIO AILTON CARVALHAL'), isTrue);
  });

  test('título abreviado pelo provedor não derruba (Doutor/Avenida)', () {
    expect(HereGeocodingService.streetMatches('Avenida Doutor João Ribeiro', 'Av. Dr. João Ribeiro'), isTrue);
  });

  test('rua sem palavra útil ("Rua Um") não tem como ser conferida → rejeita', () {
    expect(HereGeocodingService.streetMatches('Rua Um', 'Rua Um'), isFalse);
    expect(HereGeocodingService.streetMatches(via, ''), isFalse);
  });
}
