import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/models/route_maneuver.dart';
import 'package:truck_router/services/plano_rota.dart';

/// O atraso é medido contra o plano POR MANOBRA da HERE, não contra a média da
/// rota. Se isto regredir pra proporcional, o começo urbano de toda viagem
/// parece "atrasado" e o gatilho da Fase B recalcularia logo na saída.
void main() {
  // 100 km em linha, um vértice por km. Manobra 1: 10 km de cidade em 24 min.
  // Manobra 2: 90 km de rodovia em 72 min. Média da rota = 96 min / 100 km.
  final pts = [for (var i = 0; i <= 100; i++) LatLng(-23.0, -46.0 + i * 0.009)];
  RouteManeuver m(int off, int distM, int durS) => RouteManeuver(
      instruction: '', action: 'turn', distanceMeters: distM,
      durationSeconds: durS, polylineOffset: off, position: pts[off]);
  final plano = PlanoRota.de(
      [m(0, 10000, 24 * 60), m(10, 90000, 72 * 60)], pts, rotaDurS: 96 * 60);

  test('perfil soma as manobras', () {
    expect(plano.perfilS, 96 * 60);
  });

  test('no meio da cidade o plano prevê 12 min, não os ~5 do proporcional', () {
    expect(plano.previstoAteS(5), 12 * 60);
    // proporcional daria 96 min × 5/100 ≈ 4,8 min
  });

  test('fronteira e meio da rodovia', () {
    expect(plano.previstoAteS(10), 24 * 60);
    expect(plano.previstoAteS(55), 24 * 60 + 36 * 60);
    expect(plano.previstoAteS(100), 96 * 60);
  });

  test('atraso = decorrido menos previsto; adiantado é negativo', () {
    expect(plano.atrasoS(idx: 5, decorrido: const Duration(minutes: 17)), 5 * 60);
    expect(plano.atrasoS(idx: 5, decorrido: const Duration(minutes: 10)), -2 * 60);
  });

  test('sem duração por manobra (TomTom) cai no proporcional', () {
    final semPerfil = PlanoRota.de(const [], pts, rotaDurS: 96 * 60);
    expect(semPerfil.perfilS, 0);
    expect(semPerfil.previstoAteS(50), closeTo(48 * 60, 60));
  });
}
