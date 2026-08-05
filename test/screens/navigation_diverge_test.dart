import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/screens/navigation_screen.dart';

/// Afastamento (m) que um caminhão a [kmh] gera numa janela de 2,5s andando
/// [deg] graus fora da rota. É a geometria que o detector tenta ler de volta.
double _growth(double kmh, double deg) =>
    (kmh / 3.6) * 2.5 * math.sin(deg * math.pi / 180);
double _advance(double kmh) => (kmh / 3.6) * 2.5;

/// Roda uma série de amostras (1 por segundo) pelo acumulador e diz em quantos
/// ms a divergência virou "desvio de verdade" — ou null se nunca virou.
int? _timeToFire(List<double> growthPerSample, double advancePerSample) {
  int? since;
  for (var i = 0; i < growthPerSample.length; i++) {
    final now = i * 1000;
    final sine = divergenceSine(growthPerSample[i], advancePerSample);
    since = divergeSince(since, now, sine, true);
    if (divergeSustained(since, now)) return now - (since ?? now) + 0;
  }
  return null;
}

void main() {
  group('divergenceSine — geometria, não velocidade', () {
    test('devolve o seno do ângulo, seja qual for a velocidade', () {
      // 30° a 28 km/h e a 80 km/h: mesma geometria, mesma resposta.
      expect(divergenceSine(_growth(28, 30), _advance(28)), closeTo(0.5, 0.01));
      expect(divergenceSine(_growth(80, 30), _advance(80)), closeTo(0.5, 0.01));
    });

    test('sem deslocamento não existe ângulo — devolve -1, não divide por ~0', () {
      expect(divergenceSine(5, 0), -1);
      expect(divergenceSine(5, kMinAdvanceForAngleM - 0.1), -1);
      expect(divergenceSine(5, kMinAdvanceForAngleM), isNot(-1));
    });
  });

  // ESTE é o teste que separa o fix novo do gate antigo. O gate antigo era
  // "cresceu > 12m na janela de 2,5s" — limiar em METROS numa janela de TEMPO,
  // ou seja um teste de TAXA. O MESMO desvio, no MESMO ângulo, passa ou não
  // passa dependendo só da velocidade. Foi assim que o desvio do Gilberto
  // (2026-08-03, 34-42° a ~28 km/h) foi suprimido 15 vezes.
  group('invariante: o veredicto não pode depender da velocidade', () {
    const antigoLimiarM = 12.0; // _offGrowM
    const deg = 35.0;

    test('gate ANTIGO (metros/janela) inverte o veredicto com a velocidade', () {
      expect(_growth(28, deg) > antigoLimiarM, isFalse,
          reason: 'a 28 km/h o desvio real de 35° NÃO passava — o bug');
      expect(_growth(60, deg) > antigoLimiarM, isTrue,
          reason: 'o MESMO desvio a 60 km/h passava');
    });

    test('gate NOVO (geométrico) dá o mesmo veredicto nas duas velocidades', () {
      for (final kmh in [20.0, 28.0, 60.0, 90.0]) {
        expect(divergenceSine(_growth(kmh, deg), _advance(kmh)),
            greaterThan(kDivergeSine),
            reason: '35° tem que ser desvio a $kmh km/h');
      }
    });

    test('mudança de faixa (~10°) não vira desvio em nenhuma velocidade', () {
      for (final kmh in [20.0, 60.0, 90.0]) {
        expect(divergenceSine(_growth(kmh, 10), _advance(kmh)),
            lessThan(kDivergeSine));
      }
    });
  });

  group('sustentação: pista paralela satura, saída real não', () {
    test('série REAL do desvio do Gilberto (msd9r5fg) dispara', () {
      // growM medido em campo: 11,10,10,10,10,10,9,10,10,10,9,9,9,9,9 a ~28 km/h.
      // Todos abaixo do limiar antigo de 12 — por isso foram 15 supressões,
      // 148m e 14s até o teto de 150m salvar.
      const List<double> growM =
          [11, 10, 10, 10, 10, 10, 9, 10, 10, 10, 9, 9, 9, 9, 9];
      for (final g in growM) {
        expect(g, lessThan(12), reason: 'confirma: o gate antigo não pegava');
      }
      expect(_timeToFire(growM, _advance(28)), isNotNull,
          reason: 'o gate novo tem que pegar');
    });

    test('série REAL de pista paralela (mrjq79zw) NÃO dispara — ela satura', () {
      // growM medido em campo: 8,7,6,5,3,2,2,1,0 — decai a zero. O afastamento
      // lateral tem teto (largura da via), então a razão cai junto.
      const List<double> growM = [8, 7, 6, 5, 3, 2, 2, 1, 0];
      expect(_timeToFire(growM, _advance(60)), isNull);
    });

    test('série REAL de pista paralela (mrxz9so2) NÃO dispara', () {
      const List<double> growM = [5, 5, 4, 4, 4, 3, 3, 3, 2, 2];
      expect(_timeToFire(growM, _advance(60)), isNull);
    });

    // O caso mais perigoso do gate novo: em velocidade BAIXA o denominador
    // encolhe e a razão infla, então as primeiras amostras da paralela chegam a
    // cruzar 0,34. Quem segura não é o limiar — é a SATURAÇÃO: a série decai e
    // zera o relógio antes dos 5s. Se este teste quebrar, o fix virou gerador de
    // reroute espúrio em pista dupla no trânsito da cidade (o storm que a
    // supressão foi criada pra matar).
    test('paralela em velocidade baixa: cruza o limiar mas NÃO se sustenta', () {
      const List<double> growM = [8, 7, 6, 5, 3, 2, 2, 1, 0];
      final adv = _advance(20);
      expect(divergenceSine(growM.first, adv), greaterThan(kDivergeSine),
          reason: 'a 20 km/h as primeiras amostras REALMENTE cruzam o limiar');
      expect(_timeToFire(growM, adv), isNull,
          reason: 'mas ela satura antes de fechar a janela — é isso que segura');
    });

    test('transiente curto de GPS não dispara — precisa se sustentar', () {
      final alto = _growth(60, 40);
      // 3 amostras fortes e volta ao normal: menos que kDivergeSustainMs.
      expect(_timeToFire([alto, alto, alto, 0, 0, 0, 0], _advance(60)), isNull);
    });

    test('uma amostra abaixo do limiar zera o relógio', () {
      final alto = _growth(60, 40);
      final serie = [alto, alto, alto, alto, 0.0, alto, alto, alto, alto];
      // Sem o zeramento, 8 amostras altas fechariam a janela de 5s.
      expect(_timeToFire(serie, _advance(60)), isNull);
    });

    test('parado (não mensurável) não acumula tempo de desvio', () {
      int? since;
      for (var i = 0; i < 10; i++) {
        since = divergeSince(since, i * 1000, 0.9, false);
      }
      expect(since, isNull);
      expect(divergeSustained(since, 10000), isFalse);
    });
  });
}
