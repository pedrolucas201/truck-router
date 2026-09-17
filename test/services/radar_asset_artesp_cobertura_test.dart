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
      // Desde a 2.4.71 a classe "Radar Fixo"/speed 0 também abriga a cobertura
      // OFICIAL (DNIT/ANTT/DER-SP snapada na pista, merge_official_only.py):
      // essa pode trazer direção oficial que CONCORDA com a geometria, e status
      // ativo. O que continua proibido: direção vinda do cardeal (der_sp
      // bidirecional/artesp) e qualquer status inativo.
      if (r.dir1 != null) {
        expect(['osm_geom', 'dnit', 'antt', 'der_sp'], contains(r.dirSrc),
            reason: 'radar de cobertura ${r.lat},${r.lng} com direção de '
                '${r.dirSrc} — o `Sentido` cardeal do ARTESP está bloqueado por '
                'semântica igual ao DER-SP');
        // `dir2` (bidirecional) é aceito de qualquer fonte conhecida, e isto foi
        // refinado em 17/09/2026 — o teste estava restritivo além do invariante.
        //
        // Bidirecional NUNCA CALA: o radar alerta nos dois sentidos, então o
        // erro possível é falso alarme (passável), nunca sem-alarme (multa). E
        // no caso do cardeal ele nem é ambíguo: `{bearing, bearing+180}` é o
        // MESMO conjunto nas duas leituras de "Norte" (fluxo-vs-face), que é
        // exatamente por que os 394 bidirecionais do DER-SP foram aprovados em
        // 16/07 (+136 no asset) enquanto os 568 unidirecionais seguem bloqueados.
        //
        // O invariante que importa é sobre UNIDIRECIONAL, e ele continua nas
        // duas asserções em volta: direção unidirecional só de fonte cuja
        // semântica não é ambígua. A proibição total de dir2 era acidente do
        // escopo de 16/09, quando a cobertura vinha toda do `osmgeom -snap`,
        // que por construção só produz unidirecional.
      }
      expect(r.status, isNot('inactive'),
          reason: 'radar de cobertura ${r.lat},${r.lng} inativo — só os ATIVOS '
              'entram na cobertura; inativo é outra frente (guarda de sucessão)');
    }
  });
}
