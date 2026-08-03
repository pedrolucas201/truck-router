import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:truck_router/models/route_result.dart';
import 'package:truck_router/screens/navigation_screen.dart';

RouteResult _rota({
  bool hasRestriction = true,
  String? label,
  bool blocked = false,
}) =>
    RouteResult(
      polylinePoints: const [LatLng(-23, -45.6), LatLng(-23.001, -45.6)],
      distanceMeters: 1000,
      durationSeconds: 60,
      hasTimeRestriction: hasRestriction,
      restrictionLabel: label,
      destinationBlocked: blocked,
    );

void main() {
  group('restrictionSpeech', () {
    test('destino inalcançável fala o texto específico', () {
      expect(
        restrictionSpeech(_rota(
          label: 'Últimos 230 metros proibidos para caminhão',
          blocked: true,
        )),
        'Últimos 230 metros proibidos para caminhão',
      );
    });

    test('restrição de dimensão mantém a frase genérica', () {
      // O rótulo de dimensão vai pro BANNER, não pra voz: "3,5 m" abreviado é
      // loteria de TTS. Se um dia virar por extenso, este teste é quem avisa.
      expect(
        restrictionSpeech(_rota(label: 'Restrição: altura máx 3,5 m')),
        'Restrição para caminhões nesta via',
      );
    });

    test('destino bloqueado sem rótulo cai na genérica em vez de falar null', () {
      expect(
        restrictionSpeech(_rota(label: null, blocked: true)),
        'Restrição para caminhões nesta via',
      );
    });

    test('sem rótulo nenhum fala a genérica', () {
      expect(restrictionSpeech(_rota()), 'Restrição para caminhões nesta via');
    });

    test('a frase MUDA quando o motivo muda — é isso que o dedup por texto pega',
        () {
      // Regressão do bool: rota A (dimensão) e rota B (destino bloqueado) têm
      // hasTimeRestriction=true nas duas. Com guard booleano a frase de B nunca
      // saía. Guard por conteúdo só funciona se as frases forem distintas.
      final a = restrictionSpeech(_rota(label: 'Restrição: altura máx 3,5 m'));
      final b = restrictionSpeech(_rota(
        label: 'Últimos 230 metros proibidos para caminhão',
        blocked: true,
      ));
      expect(a, isNot(b));
    });
  });
}
