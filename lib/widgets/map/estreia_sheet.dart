import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/radar_point.dart';
import '../../models/route_result.dart';
import '../../models/truck_profile.dart';
import '../../services/field_log.dart';
import '../../utils/meters.dart';
import '../onboarding/trecho.dart' show ehRadarDeVelocidade, faixa;

/// Cartão de estreia: na PRIMEIRA rota que o motorista calcula de verdade, uma
/// vez só, o que o app fez pelo caminhão dele. Fecha a promessa do onboarding
/// ("na sua primeira rota eu te mostro o pedágio do seu eixo e os radares do
/// caminho") sem chamada extra: usa a rota que ele ia calcular de qualquer jeito.
/// Spec: docs/superpowers/specs/2026-09-25-onboarding-monta-caminhao-design.md.

const kEstreiaVista = 'estreia_vista';

/// Linhas do cartão. Vazio = rota sem nada pra mostrar: não abre o cartão e
/// guarda a estreia pra uma rota que tenha pedágio, radar ou desvio.
/// "Desviou" só conta o desvio CONFIRMADO na linha (`restrictionsAvoided`);
/// restrição que ficou no caminho não é vitória.
List<(IconData, String)> linhasEstreia({
  required int pedagios,
  required String tollText,
  required int radares,
  required int desvios,
}) =>
    [
      if (pedagios > 0) (Icons.toll, '$tollText, no valor do seu eixo'),
      if (radares > 0) (Icons.speed, '$radares ${radares == 1 ? 'radar' : 'radares'} no caminho, no limite de caminhão'),
      if (desvios > 0)
        (Icons.alt_route, 'Desviou de $desvios ${desvios == 1 ? 'ponto que não cabe' : 'pontos que não cabem'} no seu caminhão'),
    ];

/// Abre o cartão se for a primeira rota com conteúdo. Devolve true se o
/// motorista tocou em "Iniciar viagem".
Future<bool> mostrarEstreiaSeFor({
  required BuildContext context,
  required RouteResult rota,
  required List<RadarPoint> radaresNaRota,
  required TruckProfile caminhao,
}) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(kEstreiaVista) ?? false) return false;
  final radares = radaresNaRota.where(ehRadarDeVelocidade).length;
  final linhas = linhasEstreia(
    pedagios: rota.tolls.length,
    tollText: rota.tollText,
    radares: radares,
    desvios: rota.restrictionsAvoided.length,
  );
  if (linhas.isEmpty) return false;
  await prefs.setBool(kEstreiaVista, true);
  FieldLog.event('estreia_vista', {
    'pedagios': rota.tolls.length, 'radares': faixa(radares), 'desvios': rota.restrictionsAvoided.length,
  });
  if (!context.mounted) return false;
  final iniciar = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pro seu caminhão', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('${caminhao.axleCount} eixos · ${cmToMeters(caminhao.heightCm)} m de altura',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            for (final (icone, texto) in linhas)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Icon(icone, color: Theme.of(ctx).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text(texto, style: const TextStyle(fontSize: 16, height: 1.3))),
                ]),
              ),
            const SizedBox(height: 4),
            FilledButton.icon(
              key: const Key('estreia_iniciar'),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.navigation),
              label: const Text('Iniciar viagem'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ver rota')),
          ],
        ),
      ),
    ),
  );
  return iniciar ?? false;
}
