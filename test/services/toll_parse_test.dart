import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/models/radar_point.dart';
import 'package:truck_router/models/route_result.dart';
import 'package:truck_router/services/here_routing_service.dart';
import 'package:truck_router/services/radar_service.dart';
import 'package:truck_router/widgets/nav/nav_ui_defs.dart';

// Fixture da rota REAL do Gilberto em 11/09 (Jacareí → São Bernardo, 4 praças),
// recortada do JSON da HERE. A praça de Jacareí é o caso do relato: o ponto do
// MapaRadar fica a 22,1 m da linha (corredor 22,0) e o app passou calado.
Map<String, dynamic> _section() => {
      'tolls': [
        {
          'tollSystem': 'RIOSP',
          'fares': [
            {'name': 'RIOSP', 'price': {'currency': 'BRL', 'value': 24.3}},
          ],
          'tollCollectionLocations': [
            {'name': 'Jacareí', 'location': {'lat': -23.29644, 'lng': -46.00746}},
          ],
        },
        {
          'tollSystem': 'ECOVIAS LESTE PAULISTA',
          'fares': [
            {'price': {'currency': 'BRL', 'value': 17.1}},
          ],
          'tollCollectionLocations': [
            {'name': 'Guararema', 'location': {'lat': -23.38405, 'lng': -46.15395}},
          ],
        },
        {
          // Sem fares e sem nome: entra mesmo assim, como 'Pedágio' sem preço.
          'tollCollectionLocations': [
            {'location': {'lat': -23.71570, 'lng': -46.46442}},
          ],
        },
        {
          // Sem coordenada: não vira praça (e não derruba a rota).
          'tollCollectionLocations': [
            {'name': 'Fantasma'},
          ],
        },
      ],
    };

void main() {
  group('parseTolls', () {
    test('praças com nome, coordenada e preço do 1º fare', () {
      final tolls = HereRoutingService.parseTolls(_section());
      expect(tolls.length, 3);
      expect(tolls[0].name, 'Jacareí');
      expect(tolls[0].position, const LatLng(-23.29644, -46.00746));
      expect(tolls[0].priceBrl, 24.3);
      expect(tolls[1].name, 'Guararema');
      expect(tolls[2].name, 'Pedágio');
      expect(tolls[2].priceBrl, isNull);
    });

    test('section sem tolls devolve vazio', () {
      expect(HereRoutingService.parseTolls({'summary': <String, dynamic>{}}),
          isEmpty);
    });
  });

  group('tollRadares', () {
    test('vira radar tipo pedágio, com nome e sem velocidade', () {
      final r = const RouteResult(
        polylinePoints: [LatLng(0, 0)],
        distanceMeters: 0,
        durationSeconds: 0,
        tolls: [TollPlaza('Jacareí', LatLng(-23.29644, -46.00746))],
      ).tollRadares;
      expect(r.length, 1);
      expect(r.first.type.toLowerCase(), contains('pedagio'));
      expect(r.first.speedKmh, 0);
      expect(r.first.name, 'Jacareí');
      expect(r.first.truckKmh, isNull);
    });

    test('praça da HERE vence o ponto do MapaRadar a 22 m no dedupe', () {
      // Ponto real do asset (maparadar.csv) da mesma praça.
      const csv = RadarPoint(
          lat: -23.296300, lng: -46.007617, type: 'Pedagio', speedKmh: 0);
      final here = const RouteResult(
        polylinePoints: [LatLng(0, 0)],
        distanceMeters: 0,
        durationSeconds: 0,
        tolls: [TollPlaza('Jacareí', LatLng(-23.29644, -46.00746))],
      ).tollRadares;
      final out = RadarService.deduplicateNearby([...here, csv]);
      expect(out.length, 1, reason: 'uma praça, não dois avisos');
      expect(out.first.name, 'Jacareí', reason: 'o da HERE é o que fica');
    });
  });
}
