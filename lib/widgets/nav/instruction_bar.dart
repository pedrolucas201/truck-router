import 'package:flutter/material.dart';

import '../../models/route_maneuver.dart';
import '../../utils/maneuver_phrase.dart';
import 'nav_ui_defs.dart';

class InstructionBar extends StatelessWidget {
  final RouteManeuver? maneuver;
  final double distance;
  final IconData dirIcon;
  final AudioLevel audioLevel;
  final bool rerouting;
  final bool isNight;
  final VoidCallback onAudioCycle;
  final VoidCallback onClose;
  final String Function(double) fmtDist;

  const InstructionBar({
    super.key,
    required this.maneuver,
    required this.distance,
    required this.dirIcon,
    required this.audioLevel,
    required this.rerouting,
    required this.isNight,
    required this.onAudioCycle,
    required this.onClose,
    required this.fmtDist,
  });

  @override
  Widget build(BuildContext context) {
    const bg           = Colors.black;
    final instrColor   = isNight ? const Color(0xFF4FC3F7) : Colors.white;
    final distColor    = Colors.white;

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Fechar
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: onClose,
            tooltip: 'Encerrar navegação',
          ),
          const SizedBox(width: 4),
          // Seta de direção
          Icon(dirIcon, color: Colors.white, size: 40),
          const SizedBox(width: 12),
          // Instrução + distância
          Expanded(
            child: rerouting
                ? const Row(
                    children: [
                      SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('Recalculando rota…',
                          style: TextStyle(color: Colors.white, fontSize: 15)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        maneuver == null
                            ? '—'
                            : resolveManeuverText(maneuver!.instruction, maneuver!.action, maneuver!.direction),
                        style: TextStyle(
                            color: instrColor, fontSize: 16, fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (distance.isFinite && distance < 50000)
                        Text(
                          'Em ${fmtDist(distance)}',
                          style: TextStyle(
                              color: distColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
          ),
          // Nível de áudio
          IconButton(
            icon: Icon(
              switch (audioLevel) {
                AudioLevel.completo   => Icons.volume_up,
                AudioLevel.essencial  => Icons.volume_down,
                AudioLevel.silencioso => Icons.volume_off,
              },
              color: Colors.white,
            ),
            onPressed: onAudioCycle,
            tooltip: switch (audioLevel) {
              AudioLevel.completo   => 'Áudio: Completo',
              AudioLevel.essencial  => 'Áudio: Essencial',
              AudioLevel.silencioso => 'Áudio: Silencioso',
            },
          ),
        ],
      ),
    );
  }
}
