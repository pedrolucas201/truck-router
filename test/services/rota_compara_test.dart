import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/models/route_result.dart';
import 'package:truck_router/services/rota_compara.dart';

/// A telemetria que decide se o recálculo periódico pode esperar mais e se as
/// praças da rota anterior podem ser reaproveitadas. Se a comparação mentir,
/// a semana de dados decide errado.
void main() {
  // Reta leste-oeste de ~11 km, um ponto a cada ~110 m (0,001° de longitude).
  List<LatLng> reta({double lat = -23.0, double deslocLat = 0}) => [
        for (var i = 0; i <= 100; i++) LatLng(lat + deslocLat, -46.0 + i * 0.001),
      ];
  const praca = TollPlaza('Jacareí', LatLng(-23.0, -45.95));
  const outra = TollPlaza('Outra', LatLng(-23.0, -45.92));

  test('mesma rota, mesmas praças: desvio ~0 e nada mudou', () {
    final r = compararRotas(
      restanteAnterior: reta(),
      nova: reta(),
      pracasAnteriores: const [praca],
      pracasNovas: const [praca],
    );
    expect(r.desvioMaxM, lessThan(2));
    expect(r.pracasNovas, 0);
    expect(r.pracasSumiram, 0);
  });

  test('rota nova 500 m ao lado: o desvio aparece com o valor real', () {
    final r = compararRotas(
      restanteAnterior: reta(),
      nova: reta(deslocLat: 0.0045), // ~500 m ao norte
      pracasAnteriores: const [],
      pracasNovas: const [],
    );
    expect(r.desvioMaxM, inInclusiveRange(480, 520));
  });

  test('traçado igual com praça nova: é o furo que o reaproveitamento teria', () {
    final r = compararRotas(
      restanteAnterior: reta(),
      nova: reta(),
      pracasAnteriores: const [praca],
      pracasNovas: const [praca, outra],
    );
    expect(r.desvioMaxM, lessThan(2));
    expect(r.pracasNovas, 1);
  });

  test('praça que já ficou pra trás não conta como sumida', () {
    // O caminhão já passou de Jacareí: o restante começa depois dela.
    final restante = reta().where((p) => p.longitude > -45.94).toList();
    final r = compararRotas(
      restanteAnterior: restante,
      nova: restante,
      pracasAnteriores: const [praca],
      pracasNovas: const [],
    );
    expect(r.pracasSumiram, 0);
  });

  test('praça à frente que não veio na nova conta como sumida', () {
    final r = compararRotas(
      restanteAnterior: reta(),
      nova: reta(),
      pracasAnteriores: const [praca, outra],
      pracasNovas: const [praca],
    );
    expect(r.pracasSumiram, 1);
  });
}
