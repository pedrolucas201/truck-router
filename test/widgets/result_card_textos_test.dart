import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/models/bridge_restriction.dart';
import 'package:truck_router/models/route_result.dart';
import 'package:truck_router/widgets/map/result_card.dart';

/// Card da rota (redesenho 26/09): um alerta só, em português de cabine, e
/// chips com o que o app fez pelo caminhão.
void main() {
  const vazia = RouteResult(polylinePoints: [LatLng(0, 0)], distanceMeters: 54100, durationSeconds: 4440);
  BridgeRestriction r(String tipo, double v) => BridgeRestriction(lat: 0, lng: 0, type: tipo, value: v);

  test('restrição não contornada vira chip "a conferir", não alerta vermelho', () {
    final bloqueada = vazia.copyWith(restrictionsBlocked: [r('maxheight', 4.2)]);
    expect(bloqueada.restrictionsBlocked, isNotEmpty);
    expect(alertaDaRota(const []), isNull,
        reason: 'o aviso de segurança é o da navegação, a 300 m');
    expect(textoConferir(1), '1 passagem a conferir');
    expect(textoConferir(3), '3 passagens a conferir');
    expect(textoConferir(0), isNull);
  });

  test('chips: radares, "sem pedágio" e desvios; distância com vírgula', () {
    final comDesvio = vazia.copyWith(restrictionsAvoided: [r('maxheight', 4.0)]);
    expect(chipsDaRota(comDesvio, 22).map((c) => c.$2),
        ['22 radares', 'sem pedágio', '1 desvio pro seu caminhão']);
    expect(chipsDaRota(vazia, 0).map((c) => c.$2), ['sem pedágio'], reason: 'radar ainda carregando: sem chip');
    expect(vazia.distanceText, '54,1 km');
  });
}
