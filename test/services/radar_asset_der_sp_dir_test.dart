import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/services/radar_direction.dart';
import 'package:truck_router/services/radar_service.dart';

// Guarda a direção do DER-SP no asset (tools/radar-enrich/prep_der_sp.py).
//
// SÓ OS BIDIRECIONAIS ENTRAM. Os 568 radares unidirecionais do DER-SP estão
// BLOQUEADOS por semântica: o `Sentido` da fonte é cardeal ("Norte") e não se sabe
// se significa "o tráfego FLUI pro norte" ou "o radar APONTA pro norte" (= fotografa
// quem VEM do norte = veículo indo pro SUL). São 180° e o DER não publica dicionário.
// O comunicado oficial do DER NÃO resolve: ele só traz rótulos COMPOSTOS, que são
// SIMÉTRICOS sob as duas hipóteses (numa via N-S o tráfego flui pro norte E pro sul;
// o equipamento também visa norte E sul — as duas preveem o mesmo rótulo).
//
// Os bidirecionais não dependem dessa semântica: dir1/dir2 = {bearing, bearing+180}
// vem da GEOMETRIA (malha_der_sp.geojson), e as duas hipóteses dão resposta idêntica.
// Do cardeal usa-se só A VÍRGULA ("Norte, Sul" = fiscaliza os dois sentidos).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('INVARIANTE: todo radar der_sp com direção é BIDIRECIONAL (dir1 E dir2 a 180°)',
      () async {
    final radares = await RadarService.load();
    final der = radares.where((r) => r.dirSrc == 'der_sp').toList();

    expect(der, isNotEmpty,
        reason: 'nenhum radar der_sp com direção: o asset regrediu pro anterior '
            'ou o prep_der_sp.py parou de emitir dir1/dir2');

    for (final r in der) {
      // Se algum dia um UNIdirecional do DER-SP vazar pra cá, ele chega com dir1 e
      // dir2 == null — e este teste cai. É de propósito: liberar os 568 exige fechar
      // a semântica antes (resposta do DER ou crowd), não relaxar este teste.
      expect(r.dir2, isNotNull,
          reason: 'radar der_sp ${r.lat},${r.lng} com dir1 mas SEM dir2 = '
              'unidirecional vazou. Os 568 simples estão bloqueados por semântica '
              '(180° de ambiguidade). Ver tools/radar-enrich/TODO.md');
      final delta = angleDiff(r.dir1!, r.dir2!);
      expect(delta, closeTo(180, 1.5),
          reason: 'radar der_sp ${r.lat},${r.lng}: dir2 deveria ser dir1+180, '
              'delta=$delta');
    }
  });

  test('bidirecional nunca produz etiqueta "sentido oposto" — o erro dele é mudo',
      () async {
    final radares = await RadarService.load();
    final der = radares.where((r) => r.dirSrc == 'der_sp').toList();

    // A propriedade que torna esta classe segura de embarcar sem a semântica
    // resolvida: como angleDiff(h, d) + angleDiff(h, d+180) == 180, o mínimo dos
    // dois é sempre <= 90 <= sameMax(100). Logo um bidirecional classifica `same`
    // pra QUALQUER heading, e o VALOR do bearing não altera o resultado — um erro
    // de geometria aqui é mudo. Já um unidirecional errado em 180° produziria um
    // "sentido oposto" FALSO, que o motorista vê. É a assimetria que justifica
    // entrar só com os bidirecionais.
    for (final r in der.take(50)) {
      for (var h = 0; h < 360; h += 15) {
        final m = classifyRadarDirection(
          dir1: r.dir1,
          dir2: r.dir2,
          dirSrc: r.dirSrc,
          userHeading: h.toDouble(),
        );
        expect(m, RadarDirMatch.same,
            reason: 'radar der_sp ${r.lat},${r.lng} com heading $h° deu $m — '
                'bidirecional tem que ser sempre `same`');
      }
    }
  });

  test('enriquecimento DER-SP: a direção entrou sem tomar radar de fonte anterior',
      () async {
    final radares = await RadarService.load();
    // dnit e antt já estavam no ar (v2.4.35) e têm prioridade sobre der_sp no
    // sources.json. Se este número cair, o der_sp começou a ganhar desempate que
    // não era dele — ou o SNV/prep_oficiais regrediu.
    final dnit = radares.where((r) => r.dirSrc == 'dnit').length;
    final antt = radares.where((r) => r.dirSrc == 'antt').length;
    expect(dnit, greaterThanOrEqualTo(1603));
    expect(antt, greaterThanOrEqualTo(710));
  });
}
