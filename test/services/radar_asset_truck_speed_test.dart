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

  test('enriquecimento CET-SP: Marginal Pinheiros expressa mostra 60 pro caminhão, não 90', () async {
    final radares = await RadarService.load();
    RadarPoint at(double lat, double lng) => radares.firstWhere(
        (r) => (r.lat - lat).abs() < 1e-5 && (r.lng - lng).abs() < 1e-5,
        orElse: () => throw StateError('radar $lat,$lng sumiu do asset'));
    // Marginal Pinheiros, pista expressa: placa de leve 90, de PESADO 60 (NT-253 da
    // própria CET). Sem o truck_limit_off o app mostrava min(90, kTruckCapKmh=90) = 90
    // pro caminhão — 30 km/h acima do limite real = multa, não susto. O cap nacional
    // NÃO cobre este caso: é limite local menor que o teto (ver TODO, item P1).
    final r = at(-23.515635, -46.667687);
    expect(r.speedKmh, 90); // a placa de leve continua 90
    expect(r.truckLimitOff, 60); // e a CET diz que pesado é 60
    expect(truckRadarLimit(r.speedKmh, officialTruckLimit: r.truckLimitOff), 60);
  });

  test('enriquecimento DER-SP: rodovia estadual de 100 mostra 80 pro caminhão', () async {
    final radares = await RadarService.load();
    RadarPoint at(double lat, double lng) => radares.firstWhere(
        (r) => (r.lat - lat).abs() < 1e-5 && (r.lng - lng).abs() < 1e-5,
        orElse: () => throw StateError('radar $lat,$lng sumiu do asset'));
    // DER-SP `Velocidade` = "100/080 Km/h" = leve/PESADO (convenção R-19; o DER não
    // publica dicionário — é inferência, corroborada: nos 488 valores compostos da
    // fonte o 2º número nunca é maior que o 1º). Sem isso o app mostrava
    // min(100, kTruckCapKmh=90) = 90.
    final r = at(-22.166328, -51.320689);
    expect(r.speedKmh, 100); // placa de leve
    expect(r.truckLimitOff, 80); // DER diz que pesado é 80
    expect(truckRadarLimit(r.speedKmh, officialTruckLimit: r.truckLimitOff), 80);
  });

  test('invariante: o asset não silencia radar vivo — inactive é raro e isolado', () async {
    final radares = await RadarService.load();
    final inativos = radares.where((r) => r.status == 'inactive').length;
    // O CET-SP é um HISTÓRICO de equipamentos, não de pontos: quando trocam o
    // aparelho (às vezes com código novo), o registro velho ganha DESATIVAÇÃO e nasce
    // outro ATIVO no mesmo lugar. Medido no dump de 2026-07-16: 1114 dos 1191 registros
    // "desativados" têm um ATIVO a <20m, e 147 dos 195 locais mortos têm um local vivo
    // (código diferente) a <20m. Mapear desativação linha-a-linha rebaixaria ~1114
    // radares ATIVOS pra bip — radar real, fiscalizando, silenciado por registro velho.
    // prep_cet_sp.py cura isso em duas camadas (por CÓDIGO LOCAL + guarda espacial de
    // 60m). Se alguém remover qualquer uma das duas, este número explode e o teste cai.
    expect(inativos, lessThan(50),
        reason: 'inactive=$inativos: a guarda de troca-de-equipamento do prep_cet_sp.py '
            'provavelmente caiu — radar ativo sendo rebaixado pra bip');
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
