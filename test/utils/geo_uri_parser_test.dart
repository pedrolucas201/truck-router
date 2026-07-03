import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/utils/geo_uri_parser.dart';

void main() {
  group('parseGeoUri — geo: scheme', () {
    test('parseia geo:lat,lng básico', () {
      final uri = Uri.parse('geo:-23.5505,-46.6333');
      final result = parseGeoUri(uri);
      expect(result, isNotNull);
      expect(result!.coords.latitude, closeTo(-23.5505, 0.0001));
    });

    // Report de campo (2026-07-02): WhatsApp manda coords no path e endereço
    // textual no q — antes caía em "Link não reconhecido".
    test('geo:lat,lng?q=Endereço(Nome) usa coords do path e nome como label', () {
      final uri = Uri.parse(
        'geo:-23.12380504,-45.72210813?q=Rua+Edelzuita+Ribeiro+Gobbi%2C+218%2C+Ca%C3%A7apava%2C+12285-445%2C+SP%2C+BR(Moovemaq)',
      );
      final result = parseGeoUri(uri);
      expect(result, isNotNull);
      expect(result!.coords.latitude, closeTo(-23.12380504, 0.0001));
      expect(result.coords.longitude, closeTo(-45.72210813, 0.0001));
      expect(result.label, 'Moovemaq');
    });

    test('geo:lat,lng?q=lat,lng ainda prioriza coords do q', () {
      final uri = Uri.parse('geo:0,0?q=-23.5,-46.6(Posto)');
      final result = parseGeoUri(uri);
      expect(result, isNotNull);
      expect(result!.coords.latitude, closeTo(-23.5, 0.0001));
      expect(result.label, 'Posto');
    });
  });

  group('hosts alargados (WhatsApp compartilha em vários)', () {
    test('parseMapsDestination aceita www.google.com/maps?q=', () {
      final uri = Uri.parse('https://www.google.com/maps?q=-8.05,-34.9(Recife)');
      final result = parseMapsDestination(uri);
      expect(result, isNotNull);
      expect(result!.coords.latitude, closeTo(-8.05, 0.0001));
      expect(result.label, 'Recife');
    });

    test('classifyMapsUri reconhece destino em google.com/maps', () {
      final uri = Uri.parse('https://google.com/maps?q=-8.05,-34.9');
      expect(classifyMapsUri(uri), DeepLinkType.destination);
    });

    test('shortlink maps.app.goo.gl NÃO parseia (cai na captura)', () {
      final uri = Uri.parse('https://maps.app.goo.gl/abc123');
      expect(classifyMapsUri(uri), DeepLinkType.unknown);
      expect(parseMapsDestination(uri), isNull);
    });
  });

  group('parseMapsUri — maps.google.com', () {
    test('parseia saddr e daddr', () {
      final uri = Uri.parse(
        'https://maps.google.com/maps?saddr=-23.5,-46.6&daddr=-23.6,-46.7',
      );
      final result = parseMapsUri(uri);
      expect(result, isNotNull);
      expect(result!.origin, isNotNull);
      expect(result.origin!.latitude, closeTo(-23.5, 0.0001));
      expect(result.destination.latitude, closeTo(-23.6, 0.0001));
    });

    test('parseia só daddr (sem origem)', () {
      final uri = Uri.parse(
        'https://maps.google.com/maps?daddr=-23.6,-46.7',
      );
      final result = parseMapsUri(uri);
      expect(result, isNotNull);
      expect(result!.origin, isNull);
      expect(result.destination.latitude, closeTo(-23.6, 0.0001));
    });

    test('retorna null para URL inválida', () {
      final uri = Uri.parse('https://maps.google.com/maps?q=pizza');
      final result = parseMapsUri(uri);
      expect(result, isNull);
    });
  });

  group('parseMapsDestination — maps.google.com?q= (pin do WhatsApp)', () {
    test('parseia q=lat,lng sem label', () {
      final uri = Uri.parse('https://maps.google.com/maps?q=-23.5505,-46.6333');
      final result = parseMapsDestination(uri);
      expect(result, isNotNull);
      expect(result!.coords.latitude, closeTo(-23.5505, 0.0001));
      expect(result.coords.longitude, closeTo(-46.6333, 0.0001));
      expect(result.label, isNull);
    });

    test('parseia q=lat,lng(Label) com label', () {
      final uri =
          Uri.parse('https://maps.google.com/maps?q=-23.5,-46.6(Posto Graal)');
      final result = parseMapsDestination(uri);
      expect(result, isNotNull);
      expect(result!.coords.latitude, closeTo(-23.5, 0.0001));
      expect(result.label, 'Posto Graal');
    });

    test('retorna null para q= texto (sem coordenadas)', () {
      final uri = Uri.parse('https://maps.google.com/maps?q=pizzaria');
      final result = parseMapsDestination(uri);
      expect(result, isNull);
    });

    test('retorna null sem parâmetro q', () {
      final uri = Uri.parse('https://maps.google.com/maps?daddr=-23.6,-46.7');
      final result = parseMapsDestination(uri);
      expect(result, isNull);
    });

    test('retorna null para host diferente', () {
      final uri = Uri.parse('https://example.com/maps?q=-23.5,-46.6');
      final result = parseMapsDestination(uri);
      expect(result, isNull);
    });
  });
}
