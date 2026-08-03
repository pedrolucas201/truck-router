import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/services/here_routing_service.dart';
import 'package:truck_router/services/radar_service.dart';

// ~0,0001 grau de latitude = ~11,1 m. A linha desce em latitude, então a
// distância entre dois pontos consecutivos é previsível.
const _stepDeg = 0.0001;
const _stepM = 11.1;

List<LatLng> _linha(int n) =>
    List.generate(n, (i) => LatLng(-23.0 - i * _stepDeg, -45.6));

SpanViolation _span(int offset, {bool violated = false, bool mode = false}) =>
    (offset: offset, violated: violated, blocksMode: mode);

void main() {
  group('destinationBlockedLabel — invariante do destino inalcançável', () {
    test('sanidade da fixture: o passo da linha é ~11,1 m', () {
      // Se esta conversão estiver errada, TODAS as distâncias esperadas abaixo
      // estão erradas junto — e passariam como se estivessem certas.
      final pts = _linha(2);
      final m = RadarService.remainingAlongRoute(pts, 0, double.infinity);
      expect(m, closeTo(_stepM, 0.2));
    });

    test('trecho proibido que alcança o último span vira rótulo de destino', () {
      // 21 pontos (~222 m). Proibição começa no offset 10 e vai até o fim.
      final pts = _linha(21);
      final label = HereRoutingService.destinationBlockedLabel([
        _span(0),
        _span(5),
        _span(10, violated: true, mode: true),
        _span(15, violated: true, mode: true),
      ], pts);
      // do offset 10 até o ponto 20 = 10 saltos ≈ 111 m → arredonda pra 110
      expect(label, 'Últimos 110 metros proibidos para caminhão');
    });

    test('proibição SÓ no meio não vira rótulo de destino', () {
      final pts = _linha(21);
      final label = HereRoutingService.destinationBlockedLabel([
        _span(0),
        _span(5, violated: true, mode: true),
        _span(10), // liberado de novo antes do fim
        _span(15),
      ], pts);
      expect(label, isNull);
    });

    test('mede o BLOCO FINAL, não o 1º span restrito da rota', () {
      // Mesmo notice aparece solto lá atrás (offset 2) e no bloco final (15+).
      // Usar o 1º span restrito devolveria a rota quase inteira.
      final pts = _linha(21);
      final label = HereRoutingService.destinationBlockedLabel([
        _span(0),
        _span(2, violated: true, mode: true), // solto no meio
        _span(6),
        _span(15, violated: true, mode: true), // bloco final começa aqui
        _span(18, violated: true, mode: true),
      ], pts);
      // offset 15 → ponto 20 = 5 saltos ≈ 55,5 m → 60 m (e não ~210 m)
      expect(label, 'Últimos 60 metros proibidos para caminhão');
    });

    test('restrição de dimensão no fim mantém o rótulo de dimensão (null)', () {
      final pts = _linha(21);
      final label = HereRoutingService.destinationBlockedLabel([
        _span(0),
        _span(10, violated: true), // violado, mas não é acesso proibido
      ], pts);
      expect(label, isNull);
    });

    test('rota limpa não produz rótulo', () {
      expect(
        HereRoutingService.destinationBlockedLabel(
            [_span(0), _span(10)], _linha(21)),
        isNull,
      );
    });

    test('entradas degeneradas não explodem', () {
      expect(HereRoutingService.destinationBlockedLabel([], _linha(21)), isNull);
      expect(
        HereRoutingService.destinationBlockedLabel(
            [_span(0, violated: true, mode: true)], const [LatLng(-23, -45.6)]),
        isNull,
      );
      // offset além da polyline (span citando ponto que não existe)
      expect(
        HereRoutingService.destinationBlockedLabel(
            [_span(999, violated: true, mode: true)], _linha(21)),
        isNull, // clampa no último ponto → 0 m restante → sem rótulo
      );
    });

    test('acima de 1 km sai em km', () {
      // 100 saltos de 11,1 m ≈ 1110 m
      final pts = _linha(101);
      final label = HereRoutingService.destinationBlockedLabel(
          [_span(0, violated: true, mode: true)], pts);
      expect(label, 'Últimos 1,1 quilômetros proibidos para caminhão');
    });

    test('reproduz o caso de campo de 03/08 (Taubaté, ~225 m)', () {
      // Dois spans finais restritos, como a resposta real da HERE:
      // offset 313 e 314, com o último a 178 m e o início do bloco a 225 m.
      final pts = _linha(21); // ~222 m no total, próximo do caso real
      final label = HereRoutingService.destinationBlockedLabel([
        _span(0),
        _span(0, violated: true, mode: true),
      ], pts);
      expect(label, 'Últimos 220 metros proibidos para caminhão');
    });
  });
}
