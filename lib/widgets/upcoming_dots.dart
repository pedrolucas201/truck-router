import 'package:flutter/material.dart';
import '../models/route_event.dart';
import 'route_event_style.dart';

/// Pontinhos mínimos dos eventos seguintes (2-4), sobre o mapa, sem texto.
/// Preserva a antecipação de sequência (SP/pistas sobrepostas) sem poluir.
class UpcomingDots extends StatelessWidget {
  final List<RouteEvent> events;
  static const _max = 3;

  const UpcomingDots({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    final shown = events.take(_max).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final e in shown)
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: e.type.accentColor.withAlpha(200),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withAlpha(180), width: 1.5),
            ),
          ),
      ],
    );
  }
}
