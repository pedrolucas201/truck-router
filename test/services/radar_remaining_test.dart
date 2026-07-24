import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/services/radar_service.dart';

// Freio de chegada (P0 Gilberto 2026-07-12): na reta final da rota, o reroute
// cede pra chegada em vez de mandar o caminhão "voltar" pro destino que ele
// está passando. A decisão é `remainingAlongRoute(...) < _arrivalZoneM (150m)`.
void main() {
  // ~100m por segmento: 0,0009° de latitude ≈ 100,2 m (lng constante).
  const step = 0.0009;
  List<LatLng> line(int n) => List.generate(n, (i) => LatLng(i * step, 0));

  group('remainingAlongRoute', () {
    test('longe do fim: soma passa do teto (não é reta final)', () {
      final r = RadarService.remainingAlongRoute(line(4), 0, 150); // ~300m
      expect(r, greaterThan(150));
    });

    test('perto do fim: um segmento restante fica abaixo do teto', () {
      final r = RadarService.remainingAlongRoute(line(4), 2, 150); // ~100m
      expect(r, lessThan(150));
      expect(r, closeTo(100.2, 5));
    });

    test('no último vértice: 0', () {
      expect(RadarService.remainingAlongRoute(line(4), 3, 150), 0);
    });

    test('rota vazia: 0', () {
      expect(RadarService.remainingAlongRoute(const [], 0, 150), 0);
    });

    test('decisão nearDestination bate com o teto de 150m', () {
      final pts = line(4);
      bool near(int idx) =>
          RadarService.remainingAlongRoute(pts, idx, 150) < 150;
      expect(near(0), isFalse); // ~300m restante → reroute age normal
      expect(near(2), isTrue);  // ~100m restante → reroute cede (freio)
      expect(near(3), isTrue);  // no fim → cede
    });

    // Gate do atalho de chegada por linha reta (falso "chegou" a 1.7 km, campo Beto
    // 24/07): reta curta ao pino SÓ vira chegada se a rota restante < 400m. Passando
    // perto com rota longa não pode armar chegada.
    test('gate de chegada em linha reta bate com o teto de 400m', () {
      const cap = 400.0; // = _arrivalStraightMaxRouteM
      final pts = line(20); // ~1.9 km, simula os 1.7 km restantes do campo
      bool routeEnded(int idx) =>
          RadarService.remainingAlongRoute(pts, idx, cap) < cap;
      expect(routeEnded(0), isFalse);  // ~1.9 km restante → passando perto, NÃO chega
      expect(routeEnded(16), isTrue);  // ~300m restante → no lote, pode chegar
    });
  });
}
