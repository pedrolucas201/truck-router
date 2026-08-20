import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/utils/geo_uri_parser.dart';

void main() {
  group('incomingLinkAction — link chegando com o motorista dirigindo', () {
    // A tabela inteira: 2 dimensões, 4 casos. O caso que originou isto é o
    // terceiro — navegando COM destino, que antes abria um diálogo por cima da
    // navegação e cujo "Usar" não trocava o destino da rota em curso.
    test('mapa na frente e sem destino: aplica direto', () {
      expect(
        incomingLinkAction(screenOnTop: false, hasDestination: false),
        IncomingLinkAction.apply,
      );
    });

    test('mapa na frente e já com destino: pergunta antes de substituir', () {
      expect(
        incomingLinkAction(screenOnTop: false, hasDestination: true),
        IncomingLinkAction.ask,
      );
    });

    test('outra tela por cima (não-nav): guarda calado, NUNCA pergunta', () {
      // Ex.: perfil do caminhão aberto — um diálogo do mapa por baixo dela
      // seria o "Usar" mentiroso de antes.
      expect(
        incomingLinkAction(screenOnTop: true, hasDestination: true),
        IncomingLinkAction.storeQuietly,
      );
    });

    test('tela por cima sem destino: guarda calado do mesmo jeito', () {
      // Sem esta linha, "sem destino" cairia em apply e dispararia cálculo de
      // rota por baixo da navegação.
      expect(
        incomingLinkAction(screenOnTop: true, hasDestination: false),
        IncomingLinkAction.storeQuietly,
      );
    });

    // Decisão do Pedro (19/08/2026): link só chega quando o motorista TOCA,
    // então com a nav aberta o toque é intenção — popup de troca DENTRO da nav.
    test('navegando: oferece a troca de destino, pra qualquer combinação', () {
      for (final hasDest in [true, false]) {
        expect(
          incomingLinkAction(
              screenOnTop: true, hasDestination: hasDest, navOnTop: true),
          IncomingLinkAction.offerSwap,
        );
      }
    });

    test('tela por cima manda mais que ter destino', () {
      // O invariante em uma linha: dirigindo, nenhuma combinação abre o
      // diálogo do MAPA (ask) — o que existe em nav é o popup da própria nav.
      for (final hasDest in [true, false]) {
        for (final navOnTop in [true, false]) {
          expect(
            incomingLinkAction(
                screenOnTop: true, hasDestination: hasDest, navOnTop: navOnTop),
            isNot(IncomingLinkAction.ask),
          );
        }
      }
    });
  });

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
