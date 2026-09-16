import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/services/radar_service.dart';

// Guarda a COBERTURA do ARTESP no asset (tools/radar-enrich/prep_artesp.py).
//
// São ~210 radares fixos de concessionária de SP que o MapaRadar não tinha (medido:
// só 45% já estavam na base <=80m; concentrados no interior — SP294/SP333/SP304 — onde
// o crowd é ralo). Vêm do "Cadastro de Ativos" da ARTESP (recursos.xlsx, dado oficial,
// 99.5% geocodificado). Radar faltando = sem alerta = a pior falha do projeto.
//
// Entram como AUMENTO DE BASE (não como fonte de enriquecimento): o enrich_v2.go só
// enriquece linha existente, então radar que a base não tem só entra adicionando linha.
// Identidade no asset: desc EXATO "Radar Fixo" (sem "@vel") — nenhum radar da base tem
// esse desc (a base sempre traz "@N"). speedKmh==0 => navigation_screen trata como
// "dado ausente -> alerta por cautela" (card, sem flash de excesso). Lado seguro.
//
// O que fica BLOQUEADO de propósito (não relaxar sem fechar a semântica):
//   - DIREÇÃO: o `Sentido` do ARTESP é cardeal, mesma parede do DER-SP (180° ambíguo).
//     Os da cobertura entram SEM dir => omnidirecional => sempre alerta. Se algum dia
//     um dir vazar pra cá, este teste cai.
//   - STATUS: só os ATIVOS entram. Inativo/desativado é outra frente (guarda de sucessão).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('COBERTURA ARTESP: os radares novos existem e alertam por cautela', () async {
    final radares = await RadarService.load();
    // Identidade: desc exato "Radar Fixo" => type "Radar Fixo" e speed 0.
    final cov = radares.where((r) => r.type == 'Radar Fixo' && r.speedKmh == 0).toList();

    expect(cov.length, greaterThanOrEqualTo(180),
        reason: 'cobertura do ARTESP sumiu do asset (${cov.length} radares "Radar Fixo"). '
            'O asset regrediu pra um build sem prep_artesp.py, ou o rebuild não incluiu '
            'a base aumentada (-base data/maparadar_base_artesp.csv). Ver TODO.md §C.');

    for (final r in cov) {
      // speed 0 = alerta por cautela (nav:1744). Se ganhar velocidade, deixa de ser
      // a classe sem-limite e a premissa da cobertura muda.
      expect(r.speedKmh, 0, reason: 'radar de cobertura ${r.lat},${r.lng} com velocidade');
      // Tipo real de radar (não lombada/pedágio) => dispara o alerta de radar.
      expect(r.type.toLowerCase().contains('lombada'), isFalse);
      expect(r.type.toLowerCase().contains('pedagio'), isFalse);
    }
  });

  test('INVARIANTE: cobertura ARTESP nunca ganha direção do cardeal (só da geometria)',
      () async {
    final radares = await RadarService.load();
    final cov = radares.where((r) => r.type == 'Radar Fixo' && r.speedKmh == 0);
    for (final r in cov) {
      // Cardeal sem dicionário = ambiguidade fluxo-vs-face (mesma parede do DER-SP).
      // Desde 2026-09-16 a direção pode vir da GEOMETRIA DA PISTA (osm_geom: o
      // ponto está colado numa via de sentido único do OSM, medido com margem),
      // que não depende do rótulo cardeal. Qualquer OUTRA fonte aqui é vazamento.
      if (r.dir1 != null) {
        expect(r.dirSrc, 'osm_geom',
            reason: 'radar de cobertura ${r.lat},${r.lng} com direção de '
                '${r.dirSrc} — o `Sentido` cardeal do ARTESP está bloqueado por '
                'semântica igual ao DER-SP; só geometria pode dar direção aqui');
        expect(r.dir2, isNull,
            reason: 'osm_geom é sempre unidirecional (pista de sentido único)');
      }
      expect(r.status, isNull,
          reason: 'radar de cobertura ${r.lat},${r.lng} com status — só os ATIVOS '
              'entram na cobertura; inativo é outra frente (guarda de sucessão)');
    }
  });
}
