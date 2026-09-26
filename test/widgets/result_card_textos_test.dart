import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/models/bridge_restriction.dart';
import 'package:truck_router/models/route_result.dart';
import 'package:truck_router/models/truck_profile.dart';
import 'package:truck_router/widgets/map/result_card.dart';

/// Card da rota (redesenho 26/09): um alerta só, em português de cabine, e
/// chips com o que o app fez pelo caminhão.
void main() {
  const carreta = TruckProfile(id: 'c', name: 'Carreta', heightCm: 440, lengthCm: 1860, weightKg: 41500, axleCount: 5);
  const vazia = RouteResult(polylinePoints: [LatLng(0, 0)], distanceMeters: 54100, durationSeconds: 4440);
  BridgeRestriction r(String tipo, double v) => BridgeRestriction(lat: 0, lng: 0, type: tipo, value: v);

  test('bloqueio de altura põe a medida do caminhão do lado', () {
    expect(textoBloqueio([r('maxheight', 4.2)], carreta), 'Passagem de 4,20 m no caminho. Seu caminhão tem 4,40.');
    expect(textoBloqueio([r('maxweight', 30)], carreta), 'Limite de 30 t no caminho. Seu caminhão tem 42 t.');
    expect(textoBloqueio([r('maxheight', 4.2), r('maxheight', 3.9)], carreta),
        '2 pontos no caminho que não cabem no seu caminhão.');
  });

  test('bloqueio vence clima; sem nada, sem alerta', () {
    final bloqueada = vazia.copyWith(restrictionsBlocked: [r('maxheight', 4.2)]);
    expect(alertaDaRota(bloqueada, const [], carreta)!.bloqueio, isTrue);
    expect(alertaDaRota(vazia, const [], carreta), isNull);
  });

  test('chips: radares, "sem pedágio" e desvios; distância com vírgula', () {
    final comDesvio = vazia.copyWith(restrictionsAvoided: [r('maxheight', 4.0)]);
    expect(chipsDaRota(comDesvio, 22).map((c) => c.$2),
        ['22 radares', 'sem pedágio', '1 desvio pro seu caminhão']);
    expect(chipsDaRota(vazia, 0).map((c) => c.$2), ['sem pedágio'], reason: 'radar ainda carregando: sem chip');
    expect(vazia.distanceText, '54,1 km');
  });
}
