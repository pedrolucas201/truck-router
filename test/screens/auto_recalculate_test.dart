import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/screens/map_screen.dart';

/// O mapa fica montado por baixo da navegação e recebe o resume do app. Sem o
/// gate de "mapa na frente", cada tela acesa na viagem virava um cálculo
/// completo na HERE (rota, pedágio, clima) que ninguém usa — 68 de 99 em 09/2026.
void main() {
  final t0 = DateTime(2026, 9, 16, 7, 54);

  bool decide({bool mapOnTop = true, int minutos = 20}) => shouldAutoRecalculate(
        mapOnTop: mapOnTop,
        calculatedAt: t0,
        scheduledDeparture: false,
        hasOriginAndDestination: true,
        now: t0.add(Duration(minutes: minutos)),
      );

  test('navegação por cima: nunca recalcula, por mais velha que a rota esteja', () {
    expect(decide(mapOnTop: false, minutos: 25), isFalse);
    expect(decide(mapOnTop: false, minutos: 600), isFalse);
  });

  test('mapa na frente com rota velha: recalcula (comportamento de antes, mantido)', () {
    expect(decide(minutos: 15), isTrue);
    expect(decide(minutos: 25), isTrue);
  });

  test('rota recente não recalcula', () {
    expect(decide(minutos: 14), isFalse);
  });

  test('sem rota, com saída agendada ou sem origem/destino: não recalcula', () {
    final now = t0.add(const Duration(hours: 1));
    expect(
        shouldAutoRecalculate(mapOnTop: true, calculatedAt: null, scheduledDeparture: false,
            hasOriginAndDestination: true, now: now),
        isFalse);
    expect(
        shouldAutoRecalculate(mapOnTop: true, calculatedAt: t0, scheduledDeparture: true,
            hasOriginAndDestination: true, now: now),
        isFalse);
    expect(
        shouldAutoRecalculate(mapOnTop: true, calculatedAt: t0, scheduledDeparture: false,
            hasOriginAndDestination: false, now: now),
        isFalse);
  });
}
