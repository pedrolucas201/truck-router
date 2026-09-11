import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/models/radar_point.dart';
import 'package:truck_router/models/route_result.dart';
import 'package:truck_router/services/highway_truck_cap.dart';
import 'package:truck_router/widgets/nav/nav_ui_defs.dart';

// Rodoanel (SP-021) é 80 pra caminhão; o MapaRadar cadastra 100 e o app
// mostrava 90 (teto genérico). Áudio do Gilberto, 11/09.
void main() {
  // Linha reta N→S: os 20 primeiros vértices são BR-116, o resto SP-021.
  final pts = List.generate(40, (i) => LatLng(-23.5 - i * 0.001, -46.35));
  final route = RouteResult(
    polylinePoints: pts,
    distanceMeters: 0,
    durationSeconds: 0,
    routeRefs: const [RefSpan(0, ['BR-116']), RefSpan(20, ['SP-021'])],
  );
  RadarPoint radar(int idx, int kmh, {int? off}) => RadarPoint(
      lat: pts[idx].latitude,
      lng: pts[idx].longitude,
      type: 'Radar Movel - $kmh kmh',
      speedKmh: kmh,
      truckLimitOff: off);

  test('radar de 100 no Rodoanel mostra 80', () {
    final out = applyHighwayCaps([radar(30, 100)], route);
    expect(out.single.truckLimitOff, 80);
    expect(out.single.truckKmh, 80);
  });

  test('mesmo radar na Dutra fica no teto genérico (90)', () {
    final out = applyHighwayCaps([radar(5, 100)], route);
    expect(out.single.truckLimitOff, isNull);
    expect(out.single.truckKmh, kTruckCapKmh);
  });

  test('só abaixa: oficial de 60 não sobe pra 80', () {
    final out = applyHighwayCaps([radar(30, 100, off: 60)], route);
    expect(out.single.truckLimitOff, 60);
  });

  test('curador cravou 90 no Rodoanel: o menor manda, 80', () {
    final out = applyHighwayCaps([radar(30, 90)], route);
    expect(out.single.truckKmh, 80);
  });

  test('pedágio e lombada sem velocidade não ganham número', () {
    final ped = RadarPoint(
        lat: pts[30].latitude, lng: pts[30].longitude, type: 'Pedagio', speedKmh: 0);
    final out = applyHighwayCaps([ped], route);
    expect(out.single.truckLimitOff, isNull);
    expect(out.single.truckKmh, isNull);
  });

  test('rota sem routeNumbers (TomTom) devolve a lista intacta', () {
    final semRefs = RouteResult(
        polylinePoints: pts, distanceMeters: 0, durationSeconds: 0);
    final input = [radar(30, 100)];
    expect(applyHighwayCaps(input, semRefs), same(input));
  });

  test('refsAt: último span que já começou', () {
    expect(route.refsAt(0), ['BR-116']);
    expect(route.refsAt(19), ['BR-116']);
    expect(route.refsAt(20), ['SP-021']);
    expect(route.refsAt(39), ['SP-021']);
  });
}
