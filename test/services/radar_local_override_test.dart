import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truck_router/models/radar_point.dart';
import 'package:truck_router/services/firestore_radar_service.dart';

// Guarda o caminho crítico novo do recálculo (FASE 1, 2026-07-13): a rota nova vai
// pra tela antes do Firestore responder, e os radares que entram junto são o CSV
// filtrado pelos verdictos LOCAIS do curador. Se loadLocalOverrides() voltasse
// vazia, um radar NEGADO ressuscitaria na tela durante toda a janela do enrichment
// — exatamente a ressurreição que o v2.4.26 matou.
//
// O ponto do teste é que isso funcione SEM REDE: só SharedPreferences.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  RadarPoint radar(double lat, double lng, int speed) =>
      RadarPoint(lat: lat, lng: lng, type: 'Radar', speedKmh: speed);

  const negadoLat = -8.12419, negadoLng = -35.31299;
  const corrigidoLat = -8.13000, corrigidoLng = -35.32000;

  test('verdicto local sobrevive sem rede: radar negado some, velocidade corrigida vale',
      () async {
    SharedPreferences.setMockInitialValues({
      'radar_overrides_local': jsonEncode({
        dismissalKey(negadoLat, negadoLng): {'exists': false, 'speed': 0},
        dismissalKey(corrigidoLat, corrigidoLng): {'exists': true, 'speed': 40},
      }),
    });

    // Nenhuma chamada de rede aqui — é o que a FASE 1 tem à mão.
    final local = await FirestoreRadarService.loadLocalOverrides();

    final csvNearby = [
      radar(negadoLat, negadoLng, 60),        // curador disse: não existe
      radar(corrigidoLat, corrigidoLng, 60),  // curador disse: é 40, não 60
      radar(-8.20000, -35.40000, 80),         // sem verdicto: passa intacto
    ];

    final naTela = applyOverrides(csvNearby, local);

    expect(naTela.length, 2, reason: 'o radar negado não pode ressuscitar');
    expect(naTela.any((r) => r.lat == negadoLat), isFalse);
    expect(naTela.firstWhere((r) => r.lat == corrigidoLat).speedKmh, 40,
        reason: 'a velocidade corrigida pelo curador vale desde o 1º frame');
    expect(naTela.firstWhere((r) => r.lat == -8.20000).speedKmh, 80);
  });
}
