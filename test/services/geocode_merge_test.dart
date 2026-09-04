import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/services/here_geocoding_service.dart';

/// Gate do ranking da busca por nome.
///
/// Caso de origem (Beto, áudio de 2026-09-04): "nome de empresa no Google acha,
/// no nosso não". Medido na chave real no mesmo dia, com `at` em SJC:
///  - "Graal" → 1º da lista: "Rua Salito Graal, Manaus" (2.708 km), acima do
///    Graal de Caçapava (19 km, na Dutra); o "Graal 56" era cortado pelo take(5).
///  - A ordem era por FONTE (autocomplete → geocode → discover), e o discover é
///    justamente a fonte que busca por nome.
///  - Rótulo vinha com "&amp;" literal ("Quina &amp; Silva").
void main() {
  GeocodingSuggestion p(String t, {int? m, String src = ''}) =>
      GeocodingSuggestion.place(
          title: t, pos: const LatLng(0, 0), distanceM: m, source: src);
  GeocodingSuggestion a(String t, {int? m}) =>
      GeocodingSuggestion.address(title: t, id: t, distanceM: m, source: 'ac');

  group('mergeHere — com bias ordena pela distância da HERE', () {
    test('o caso do Graal: rua em Manaus cai pro fim, Caçapava sobe', () {
      final out = HereGeocodingService.mergeHere([
        [a('Rua Salito Graal, Manaus', m: 2708000)],
        [p('Graal, Guararema', m: 28000, src: 'gc')],
        [
          p('Graal Clube 500, Caçapava', m: 19000, src: 'dc'),
          p('Graal 56, Jundiaí', m: 106000, src: 'dc'),
        ],
      ], byDistance: true);
      expect(out.map((s) => s.title).toList(), [
        'Graal Clube 500, Caçapava',
        'Graal, Guararema',
        'Graal 56, Jundiaí',
        'Rua Salito Graal, Manaus',
      ]);
    });

    test('sem distância vai pro fim, mantendo a ordem entre si', () {
      final out = HereGeocodingService.mergeHere([
        [a('X'), a('Y')],
        [p('Z', m: 5)],
      ], byDistance: true);
      expect(out.map((s) => s.title).toList(), ['Z', 'X', 'Y']);
    });

    test('empate de distância preserva a ordem da fonte (sort estável)', () {
      final out = HereGeocodingService.mergeHere([
        [a('A', m: 100)],
        [p('B', m: 100)],
      ], byDistance: true);
      expect(out.map((s) => s.title).toList(), ['A', 'B']);
    });
  });

  group('mergeHere — dedupe', () {
    test('título repetido fica com a primeira ocorrência, sem case', () {
      final out = HereGeocodingService.mergeHere([
        [p('Embraer, SJC', m: 5000, src: 'gc')],
        [p('embraer, sjc ', m: 5000, src: 'dc')],
      ], byDistance: true);
      expect(out.length, 1);
      expect(out.single.source, 'gc');
    });

    test('sem bias mantém a ordem por fonte (HERE não manda distance)', () {
      final out = HereGeocodingService.mergeHere([
        [a('rua longe')],
        [p('empresa perto', m: 10)], // discover ancorado em Brasília: não vale
      ], byDistance: false);
      expect(out.first.title, 'rua longe');
    });
  });

  group('unescapeHtml — rótulo da HERE', () {
    test('&amp; vira &', () {
      expect(GeocodingSuggestion.unescapeHtml('Quina &amp; Silva'), 'Quina & Silva');
    });

    test('sem entidade não toca na string', () {
      const s = 'Rua José Gomes de Abreu, SJC';
      expect(GeocodingSuggestion.unescapeHtml(s), same(s));
    });

    test('o construtor já entrega o título limpo', () {
      expect(p('A &amp; B').title, 'A & B');
    });
  });
}
