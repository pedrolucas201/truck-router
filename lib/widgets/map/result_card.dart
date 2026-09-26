import 'package:flutter/material.dart';
import '../../utils/meters.dart';
import 'package:provider/provider.dart';

import '../../models/bridge_restriction.dart';
import '../../models/route_result.dart';
import '../../models/truck_profile.dart';
import '../../models/weather_alert.dart';
import '../../providers/truck_profile_provider.dart';

/// Card da rota antes de sair (redesenho 26/09, sujeito a mudança): uma linha
/// de resposta (chegada · duração · distância), UM alerta (o mais grave, em
/// português de cabine, com a ação do lado), chips com o que o app faz pelo
/// caminhão (radares, pedágio do eixo, terra, desvios), o caminhão tocável e
/// o "Iniciar viagem". Copiar, compartilhar e abrir fora vão pro ⋮.
class ResultCard extends StatelessWidget {
  final RouteResult result;
  final List<WeatherAlert> weatherAlerts;
  final DateTime? departureTime;
  /// Radares de velocidade na rota (a lista que o mapa desenha). Chega depois
  /// da rota: até lá o chip não aparece.
  final int radares;
  final VoidCallback onStartNavigation;
  final VoidCallback onOpenExternal;
  final VoidCallback onShare;
  final VoidCallback onCopy;
  final VoidCallback? onBlockedTap;
  final VoidCallback? onTruckTap;

  const ResultCard({
    super.key,
    required this.result,
    this.weatherAlerts = const [],
    required this.departureTime,
    this.radares = 0,
    required this.onStartNavigation,
    required this.onOpenExternal,
    required this.onShare,
    required this.onCopy,
    this.onBlockedTap,
    this.onTruckTap,
  });

  static String _etaString(DateTime? departureTime, int durationSeconds) {
    final base = departureTime ?? DateTime.now();
    final eta  = base.add(Duration(seconds: durationSeconds));
    return '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final truck = context.watch<TruckProfileProvider>().profile;
    final eta = _etaString(departureTime, result.durationSeconds);
    final alerta = alertaDaRota(result, weatherAlerts, truck);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Center(
            child: Container(
              width: 32, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),
        // Resposta: quando chega, quanto demora, quanto anda.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Chega $eta',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    TextSpan(text: '   ${result.durationText} · ${result.distanceText}',
                        style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
              PopupMenuButton<String>(
                key: const Key('rota_mais'),
                icon: Icon(Icons.more_vert, color: cs.onSurfaceVariant),
                onSelected: (v) => switch (v) {
                  'copiar' => onCopy(),
                  'compartilhar' => onShare(),
                  _ => onOpenExternal(),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'copiar', child: ListTile(leading: Icon(Icons.copy), title: Text('Copiar texto'))),
                  PopupMenuItem(value: 'compartilhar', child: ListTile(leading: Icon(Icons.share), title: Text('Compartilhar'))),
                  PopupMenuItem(value: 'fora', child: ListTile(leading: Icon(Icons.open_in_new), title: Text('Abrir em outro app'))),
                ],
              ),
            ],
          ),
        ),
        if (alerta != null)
          _Alerta(alerta: alerta, onTap: alerta.bloqueio ? onBlockedTap : null),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: RouteChips(result: result, radares: radares),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              key: const Key('rota_caminhao'),
              avatar: Icon(Icons.local_shipping, size: 18, color: cs.primary),
              label: Text('${cmToMeters(truck.heightCm)} m · ${truck.axleCount} eixos · '
                  '${(truck.weightKg / 1000).toStringAsFixed(0)} t  ›'),
              onPressed: onTruckTap,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: FilledButton.icon(
            onPressed: onStartNavigation,
            icon: const Icon(Icons.navigation),
            label: const Text('Iniciar viagem', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ),
      ],
    );
  }
}

/// O alerta do card: um só, o mais grave. Bloqueio físico > clima severo.
class AlertaRota {
  final String texto;
  final IconData icone;
  final bool bloqueio;
  const AlertaRota(this.texto, this.icone, {this.bloqueio = false});
}

AlertaRota? alertaDaRota(RouteResult r, List<WeatherAlert> clima, TruckProfile truck) {
  final b = r.restrictionsBlocked;
  if (b.isNotEmpty) return AlertaRota(textoBloqueio(b, truck), Icons.block, bloqueio: true);
  if (clima.isEmpty) return null;
  final sorted = [...clima]..sort((a, b) => a.time.compareTo(b.time));
  final first = sorted.first;
  final texto = sorted.length == 1
      ? '${first.label} na rota, por volta das ${first.timeLabel}'
      : '${sorted.length} avisos de clima na rota, a partir das ${first.timeLabel}';
  return AlertaRota(texto, switch (first.kind) {
    'rain' => Icons.umbrella,
    'wind' => Icons.air,
    'fog' => Icons.foggy,
    _ => Icons.cloud_outlined,
  });
}

/// "Passagem de 4,20 m no caminho. Seu caminhão tem 4,40." O limite ao lado
/// da medida dele, pra ele julgar (a base tem contaminação conhecida).
String textoBloqueio(List<BridgeRestriction> b, TruckProfile t) {
  if (b.length > 1) return '${b.length} pontos no caminho que não cabem no seu caminhão.';
  final r = b.first;
  String m(double v) => cmToMeters((v * 100).round());
  return switch (r.type) {
    'maxheight' => 'Passagem de ${m(r.value)} m no caminho. Seu caminhão tem ${cmToMeters(t.heightCm)}.',
    'maxweight' => 'Limite de ${r.value.toStringAsFixed(0)} t no caminho. Seu caminhão tem ${(t.weightKg / 1000).toStringAsFixed(0)} t.',
    'maxwidth' => 'Largura de ${m(r.value)} m no caminho. Seu caminhão tem ${cmToMeters(t.widthCm)}.',
    _ => '${r.label} no caminho.',
  };
}

class _Alerta extends StatelessWidget {
  final AlertaRota alerta;
  final VoidCallback? onTap;
  const _Alerta({required this.alerta, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cor = alerta.bloqueio ? Colors.red.shade700 : Colors.deepOrange.shade700;
    final fundo = alerta.bloqueio ? Colors.red.shade50 : Colors.deepOrange.shade50;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: fundo,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: const Key('rota_alerta'),
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(children: [
              Icon(alerta.icone, color: cor, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(alerta.texto,
                  style: TextStyle(fontSize: 14, color: cor, fontWeight: FontWeight.w600, height: 1.3))),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Text('Ver no mapa', style: TextStyle(color: cor, fontWeight: FontWeight.w800, fontSize: 13)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Chips do que o app faz pelo caminhão nesta rota. Só aparece o que existe:
/// sem pedágio vira "sem pedágio" (informação útil), sem terra some.
class RouteChips extends StatelessWidget {
  final RouteResult result;
  final int radares;
  const RouteChips({super.key, required this.result, this.radares = 0});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final c in chipsDaRota(result, radares))
          Chip(
            avatar: Icon(c.$1, size: 16, color: c.$3),
            label: Text(c.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            visualDensity: VisualDensity.compact,
            side: BorderSide(color: c.$3.withValues(alpha: .35)),
          ),
      ],
    );
  }
}

/// Ícone, texto e cor de cada chip. Puro, pra teste.
List<(IconData, String, Color)> chipsDaRota(RouteResult r, int radares) => [
      if (radares > 0) (Icons.speed, '$radares ${radares == 1 ? 'radar' : 'radares'}', Colors.teal.shade700),
      if (r.tolls.isEmpty)
        (Icons.toll, 'sem pedágio', Colors.blueGrey.shade600)
      else
        (Icons.toll, r.tollText, Colors.blue.shade700),
      if (r.dirtSegments.isNotEmpty)
        (
          Icons.terrain,
          r.dirtSegments.length == 1 ? '${r.dirtText} de terra' : '${r.dirtText} de terra, em ${r.dirtSegments.length} trechos',
          Colors.brown.shade700,
        ),
      if (r.restrictionsAvoided.isNotEmpty)
        (
          Icons.alt_route,
          '${r.restrictionsAvoided.length} ${r.restrictionsAvoided.length == 1 ? 'desvio' : 'desvios'} pro seu caminhão',
          Colors.green.shade700,
        ),
    ];

class InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const InfoItem({super.key, required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        const SizedBox(height: 1),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }
}
