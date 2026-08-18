import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/models/bridge_restriction.dart';
import 'package:truck_router/providers/route_provider.dart';
import 'package:truck_router/services/physical_restriction_service.dart';

void main() {
  group('parseCsv', () {
    test('lê o formato do asset e pula o header', () {
      final r = PhysicalRestrictionService.parseCsv(
        'longitude,latitude,tipo,valor,via\n'
        '-46.581909,-23.518305,maxheight,4.5,Ponte Cruzeiro\n'
        '-43.030287,-22.665031,maxweight,10,\n',
      );
      expect(r.length, 2);
      expect(r[0].lat, -23.518305);
      expect(r[0].lng, -46.581909);
      expect(r[0].type, 'maxheight');
      expect(r[0].value, 4.5);
      expect(r[0].roadName, 'Ponte Cruzeiro');
      expect(r[1].roadName, isNull); // via vazia não vira string vazia
    });

    test('descarta linha sem valor numérico em vez de virar restrição fantasma', () {
      final r = PhysicalRestrictionService.parseCsv(
        '-46.5,-23.5,maxheight,default,X\n'
        '-46.5,-23.6,maxheight,,Y\n'
        '-46.5,-23.7,maxheight,4.2,Z\n',
      );
      expect(r.length, 1);
      expect(r.single.value, 4.2);
    });
  });

  group('filterNearRoute', () {
    // Rota reta ~1,1 km no eixo leste-oeste, na latitude de SP.
    final rota = [
      const LatLng(-23.5000, -46.6000),
      const LatLng(-23.5000, -46.5900),
    ];

    BridgeRestriction em(double lat, double lng) =>
        BridgeRestriction(lat: lat, lng: lng, type: 'maxheight', value: 4.0);

    test('pega o que está sobre a rota e descarta o que está longe', () {
      final r = PhysicalRestrictionService.filterNearRoute(
        [em(-23.5000, -46.5950), em(-23.6000, -46.5950)], rota);
      expect(r.length, 1);
      expect(r.single.lat, -23.5000);
    });

    test('via paralela a 200m cai fora do corredor', () {
      // ~0.0018° de latitude ≈ 200 m: é o caso que a distância a pontos soltos
      // erra e a distância perpendicular ao segmento acerta.
      final r = PhysicalRestrictionService.filterNearRoute(
        [em(-23.5018, -46.5950)], rota);
      expect(r, isEmpty);
    });

    test('perto do meio do segmento entra, mesmo sem vértice por perto', () {
      // 0.0005° ≈ 55 m, dentro do corredor de 80 m, no meio do trecho.
      final r = PhysicalRestrictionService.filterNearRoute(
        [em(-23.5005, -46.5950)], rota);
      expect(r.length, 1);
    });

    test('rota vazia ou de um ponto não explode', () {
      expect(PhysicalRestrictionService.filterNearRoute([em(0, 0)], []), isEmpty);
      expect(
        PhysicalRestrictionService.filterNearRoute(
            [em(0, 0)], [const LatLng(0, 0)]),
        isEmpty,
      );
    });
  });

  group('capAvoidAreas', () {
    // O teto da HERE é 150 (medido); o app corta em 100.
    List<BridgeRestriction> muitas(int n) => List.generate(
      n,
      // Longe → perto: o índice 0 é o MAIS distante do início da rota.
      (i) => BridgeRestriction(
          lat: -23.5, lng: -46.6 - (n - i) * 0.001, type: 'maxheight', value: 4.0),
    );
    final rota = [const LatLng(-23.5, -46.6), const LatLng(-23.5, -46.5)];

    test('abaixo do teto passa intacto e sem reordenar', () {
      final entrada = muitas(10);
      final r = RouteProvider.capAvoidAreas(entrada, rota);
      expect(r.length, 10);
      expect(r.first.lng, entrada.first.lng);
    });

    test('acima do teto corta em 100 mantendo as mais próximas do início', () {
      final r = RouteProvider.capAvoidAreas(muitas(300), rota);
      expect(r.length, 100);
      // As mantidas têm que ser as mais perto de -46.6, não as primeiras da lista.
      final maisLonge = r.map((e) => e.lng).reduce((a, b) => a < b ? a : b);
      expect(maisLonge, greaterThan(-46.75));
    });

    test('não mexe na lista de quem chamou', () {
      // O chamador continua usando `conflicts` DEPOIS do cap, pra classificar o
      // que virou avoided/blocked. Se o cap ordenasse in-place, o aviso ao
      // motorista sairia embaralhado; se truncasse, a restrição que não coube na
      // URL da HERE sumiria do aviso — limite de API virando alerta suprimido.
      final entrada = muitas(300);
      final antes = List.of(entrada);
      RouteProvider.capAvoidAreas(entrada, rota);
      expect(entrada.length, 300);
      expect(entrada.map((e) => e.lng).toList(), antes.map((e) => e.lng).toList());
    });

    test('desconta as áreas manuais do teto', () {
      expect(RouteProvider.capAvoidAreas(muitas(300), rota, reservado: 40).length, 60);
      expect(RouteProvider.capAvoidAreas(muitas(300), rota, reservado: 100), isEmpty);
    });
  });

  group('offersDirtAlternative', () {
    // Gate: economia ≥5min E ≥20%. Piso era 15min e fechava toda viagem curta
    // (30min exigia 50% de economia). Regimes: <25min o piso manda, ≥25min os
    // 20% mandam, viagem longa não muda em relação ao gate antigo.
    test('viagem curta abre com 20% (impossível no gate de 15min)', () {
      // 30min, economiza 8min (27%): antes fechado, agora abre.
      expect(RouteProvider.offersDirtAlternative(1800, 1320), isTrue);
      // 30min, economiza exatamente 6min (20%): borda abre.
      expect(RouteProvider.offersDirtAlternative(1800, 1440), isTrue);
    });

    test('economia trivial não abre: piso de 5min segura viagem minúscula', () {
      // 10min, economiza 4min (40% mas <5min).
      expect(RouteProvider.offersDirtAlternative(600, 360), isFalse);
      // 30min, economiza 5min (17%): passa no piso mas não nos 20%.
      expect(RouteProvider.offersDirtAlternative(1800, 1500), isFalse);
    });

    test('viagem longa fica idêntica ao gate antigo', () {
      // 3h: 30min (17%) segue fechado, 36min (20%) segue aberto.
      expect(RouteProvider.offersDirtAlternative(10800, 9000), isFalse);
      expect(RouteProvider.offersDirtAlternative(10800, 8640), isTrue);
    });
  });
}
