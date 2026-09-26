import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/route_result.dart';
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
  });

  static String _etaString(DateTime? departureTime, int durationSeconds) {
    final base = departureTime ?? DateTime.now();
    final eta  = base.add(Duration(seconds: durationSeconds));
    return '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final trucks = context.watch<TruckProfileProvider>();
    final truck = trucks.profile;
    // Nome do caminhão só pra quem tem mais de um: é aí que a rota pode ter
    // saído pro caminhão errado. Com um só, seria repetir o menu.
    final qual = trucks.profiles.length > 1 ? ' · ${truck.name}' : '';
    final eta = _etaString(departureTime, result.durationSeconds);
    final alerta = alertaDaRota(weatherAlerts);
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
                    TextSpan(text: '   ${result.durationText} · ${result.distanceText}$qual',
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
          _Alerta(alerta: alerta),
        // Uma linha só, rolando: o card fica baixo e sobra mapa.
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: RouteChips(result: result, radares: radares, onConferir: onBlockedTap),
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

/// O alerta do card: só clima severo. Restrição que o roteador não contornou
/// virou chip âmbar "a conferir" (Pedro, 26/09: o bannerzão vermelho gritava
/// num falso positivo de ponte). O aviso de segurança dela é o da navegação, a
/// 300 m, na hora em que o motorista age; esse não mudou.
class AlertaRota {
  final String texto;
  final IconData icone;
  const AlertaRota(this.texto, this.icone);
}

AlertaRota? alertaDaRota(List<WeatherAlert> clima) {
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

class _Alerta extends StatelessWidget {
  final AlertaRota alerta;
  const _Alerta({required this.alerta});

  @override
  Widget build(BuildContext context) {
    final cor = Colors.deepOrange.shade700;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        key: const Key('rota_alerta'),
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(color: Colors.deepOrange.shade50, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(alerta.icone, color: cor, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(alerta.texto,
              style: TextStyle(fontSize: 14, color: cor, fontWeight: FontWeight.w600, height: 1.3))),
        ]),
      ),
    );
  }
}

/// Chips do que o app faz pelo caminhão nesta rota. Só aparece o que existe:
/// sem pedágio vira "sem pedágio" (informação útil), sem terra some.
class RouteChips extends StatelessWidget {
  final RouteResult result;
  final int radares;
  /// Toque no chip "a conferir" (abre a lista e o mapa dos pontos).
  final VoidCallback? onConferir;
  const RouteChips({super.key, required this.result, this.radares = 0, this.onConferir});

  @override
  Widget build(BuildContext context) {
    final conferir = textoConferir(result.restrictionsBlocked.length);
    final chips = <Widget>[
        if (conferir != null)
          ActionChip(
            key: const Key('rota_conferir'),
            avatar: Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.shade800),
            label: Text('$conferir  ›', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.orange.shade900)),
            visualDensity: VisualDensity.compact,
            backgroundColor: Colors.orange.shade50,
            side: BorderSide(color: Colors.orange.shade300),
            onPressed: onConferir,
          ),
        for (final c in chipsDaRota(result, radares))
          Chip(
            avatar: Icon(c.$1, size: 16, color: c.$3),
            label: Text(c.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            visualDensity: VisualDensity.compact,
            side: BorderSide(color: c.$3.withValues(alpha: .35)),
          ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        for (final (i, c) in chips.indexed) ...[if (i > 0) const SizedBox(width: 6), c],
      ]),
    );
  }
}

/// "1 passagem a conferir" — restrição que o roteador não conseguiu contornar.
/// Null = nenhuma.
String? textoConferir(int n) => n == 0 ? null : n == 1 ? '1 passagem a conferir' : '$n passagens a conferir';

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
