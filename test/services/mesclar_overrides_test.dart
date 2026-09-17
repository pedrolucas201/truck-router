import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/services/firestore_radar_service.dart';

/// A regra que o motorista sente na cara: ou ele vê o próprio palpite, ou vê o
/// da maioria. Decisão do Pedro (17/09/2026): com 3+ votos e sem empate, a
/// maioria manda pra todos — inclusive pra quem votou o contrário.
///
/// Se isto quebrar pro lado errado, uma de duas coisas acontece: o voto de um
/// motorista sozinho passa a valer pra todos (o problema que a maioria vem
/// resolver), ou a maioria nunca vale e nada muda.
void main() {
  const rid = '-23.29676_-45.96660';

  test('sem apuração no servidor, o voto local manda', () {
    final out = mesclarOverrides(
      {}, // servidor não tem nada
      {rid: const RadarOverride(true, 80)},
    );
    expect(out[rid]!.speedKmh, 80);
    expect(out[rid]!.exists, isTrue);
  });

  test('servidor sem maioria NÃO passa por cima do local', () {
    // O caso Beto 80 x Fernando 90: 2 votos, abaixo do piso. O servidor publica
    // neutro (kmh 0) e cada aparelho segue com o seu.
    final out = mesclarOverrides(
      {rid: const RadarOverride(true, 0)},
      {rid: const RadarOverride(true, 80)},
    );
    expect(out[rid]!.speedKmh, 80, reason: 'sem maioria o local vence');
  });

  test('maioria no limite passa por cima do local', () {
    // Beto votou 80; a maioria apurou 90. Ele passa a ver 90.
    final out = mesclarOverrides(
      {rid: const RadarOverride(true, 90, mandaKmh: true)},
      {rid: const RadarOverride(true, 80)},
    );
    expect(out[rid]!.speedKmh, 90);
  });

  test('maioria diz que NÃO existe e derruba o "existe" local', () {
    final out = mesclarOverrides(
      {rid: const RadarOverride(false, 0, mandaExists: true)},
      {rid: const RadarOverride(true, 80)},
    );
    expect(out[rid]!.exists, isFalse);
  });

  test('campo por campo: maioria sobre existir, empate no limite', () {
    // Decisões independentes — o motorista aceita a maioria no que foi decidido
    // e mantém o dele no que empatou.
    final out = mesclarOverrides(
      {rid: const RadarOverride(true, 0, mandaExists: true)},
      {rid: const RadarOverride(false, 60)},
    );
    expect(out[rid]!.exists, isTrue, reason: 'maioria mandou no existir');
    expect(out[rid]!.speedKmh, 60, reason: 'limite empatou, fica o dele');
  });

  test('radar em que só o servidor tem voto: vale o do servidor', () {
    final out = mesclarOverrides(
      {rid: const RadarOverride(false, 0, mandaExists: true)},
      {},
    );
    expect(out[rid]!.exists, isFalse);
  });

  test('não mistura radares diferentes', () {
    const outro = '-23.10000_-45.10000';
    final out = mesclarOverrides(
      {rid: const RadarOverride(true, 90, mandaKmh: true)},
      {outro: const RadarOverride(true, 60)},
    );
    expect(out[rid]!.speedKmh, 90);
    expect(out[outro]!.speedKmh, 60);
    expect(out.length, 2);
  });
}
