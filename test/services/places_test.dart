import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/services/here_geocoding_service.dart';

/// Google Places (New) na busca por nome de lugar.
///
/// Medido em 2026-09-09 com 20 nomes que um motorista digita (at = SJC):
/// HERE discover achou 14, Google 20. "Ceasa SJC" na HERE vira "Casa Doce" a
/// 1 km; na Google é o CEAGESP a 12 km. O JSON abaixo é a resposta real.
void main() {
  // Resposta real do Autocomplete com `origin` (placeId encurtado).
  final real = {
    'suggestions': [
      {
        'placePrediction': {
          'place': 'places/ChIJZ8BxQMJN',
          'placeId': 'ChIJZ8BxQMJN',
          'text': {
            'text': 'CEAGESP - Rodovia Presidente Dutra - Eugênio de Melo, Distrito - SP, Brasil',
            'matches': [{'endOffset': 7}],
          },
          'structuredFormat': {
            'mainText': {'text': 'CEAGESP'},
            'secondaryText': {'text': 'Rodovia Presidente Dutra - Eugênio de Melo, Distrito - SP, Brasil'},
          },
          'types': ['food', 'point_of_interest', 'wholesaler'],
          'distanceMeters': 12163,
        },
      },
      // Sugestão de TEXTO (sem lugar): não vira item.
      {'queryPrediction': {'text': {'text': 'ceasa perto de mim'}}},
      // Sem origin a Google não manda distanceMeters: entra sem distância.
      {
        'placePrediction': {
          'placeId': 'ChIJoutro',
          'text': {'text': 'Estação Ceasa - São Paulo - SP, Brasil'},
        },
      },
    ],
  };

  test('parse da resposta real: placeId vira lookup, distância entra, queryPrediction some', () {
    final out = HereGeocodingService.parsePlacesAutocomplete(real);
    expect(out.length, 2);
    expect(out.first.title, startsWith('CEAGESP'));
    expect(out.first.hereId, 'ChIJZ8BxQMJN');
    expect(out.first.needsLookup, isTrue);
    expect(out.first.distanceM, 12163);
    expect(out.first.source, 'gp');
    expect(out.first.fromGoogle, isTrue, reason: 'termo 14.3: expira em 30 dias');
    expect(out.last.distanceM, isNull);
  });

  test('resposta vazia ou sem suggestions não quebra', () {
    expect(HereGeocodingService.parsePlacesAutocomplete({}), isEmpty);
    expect(HereGeocodingService.parsePlacesAutocomplete({'suggestions': []}), isEmpty);
  });

  test('o caso do Ceasa: Google vai na frente do lixo perto da HERE', () {
    GeocodingSuggestion here(String t, int km) =>
        GeocodingSuggestion.place(title: t, pos: const LatLng(0, 0), distanceM: km * 1000, source: 'dc');
    final google = HereGeocodingService.parsePlacesAutocomplete(real);
    final merged = HereGeocodingService.mergePlaces(google, [
      here('Casa Doce Sjc', 1),
      here('Santa Casa São José dos Campos', 0),
    ]);
    expect(merged.first.source, 'gp');
    expect(merged.map((s) => s.title).toList().sublist(2), ['Casa Doce Sjc', 'Santa Casa São José dos Campos']);
  });

  test('Google entra no máximo 3 e não repete rótulo da HERE', () {
    GeocodingSuggestion g(String t) => GeocodingSuggestion.address(title: t, id: t, source: 'gp');
    final merged = HereGeocodingService.mergePlaces(
      [g('A'), g('B'), g('C'), g('D')],
      [GeocodingSuggestion.place(title: 'b', pos: const LatLng(0, 0), source: 'dc'),
       GeocodingSuggestion.place(title: 'E', pos: const LatLng(0, 0), source: 'dc')],
    );
    expect(merged.map((s) => s.title).toList(), ['A', 'B', 'C', 'E']);
  });
}
