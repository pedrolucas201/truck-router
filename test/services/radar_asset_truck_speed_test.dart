import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/models/radar_point.dart';
import 'package:truck_router/services/radar_service.dart';
import 'package:truck_router/widgets/nav/nav_ui_defs.dart';

// Guarda o enriquecimento do asset com a velocidade_pesado OFICIAL da ANTT
// (tools/enriquece_velocidade_pesado.py). A operação é min(postado, oficial):
// só ABAIXA o limite pro de caminhão, nunca sobe (invariante: nunca afrouxa
// alerta = nunca falso negativo = nunca multa). Fonte: dados abertos ANTT,
// campo velocidade_pesado; 125 "Radar Fixo" baixados, match <=40m.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('asset: toda velocidade de radar é plausível (0..130) — pega corrupção do gerador', () async {
    final radares = await RadarService.load();
    for (final r in radares) {
      expect(r.speedKmh, inInclusiveRange(0, 130),
          reason: 'radar ${r.lat},${r.lng} (${r.type}) com velocidade absurda: ${r.speedKmh}');
    }
  });

  test('enriquecimento ANTT aplicado: radares de rodovia baixados pro limite de caminhão', () async {
    final radares = await RadarService.load();
    RadarPoint at(double lat, double lng) => radares.firstWhere(
        (r) => (r.lat - lat).abs() < 1e-5 && (r.lng - lng).abs() < 1e-5,
        orElse: () => throw StateError('radar $lat,$lng sumiu do asset'));
    // Ambos eram "Radar Fixo" com velocidade postada maior; a ANTT diz o limite
    // de caminhão. Se o asset antigo for restaurado, estes valores regridem e o
    // teste quebra — que é o ponto.
    expect(at(-22.853505, -43.602011).speedKmh, 30); // postado 40 -> caminhão 30
    expect(at(-22.122788, -42.779015).speedKmh, 40); // postado 60 -> caminhão 40
  });

  test('invariante de runtime: truckRadarLimit nunca SOBE o limite (min, nunca max)', () {
    for (final v in [0, 30, 60, 80, 90, 100, 110, 120]) {
      final lim = truckRadarLimit(v);
      if (lim != null) {
        expect(lim, lessThanOrEqualTo(v)); // nunca acima do postado
        expect(lim, lessThanOrEqualTo(kTruckCapKmh)); // nunca acima do teto de caminhão
      }
    }
  });
}
