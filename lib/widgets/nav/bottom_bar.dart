import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/radar_point.dart';
import '../../models/route_result.dart' show brl;
import '../../services/radar_direction.dart';
import 'nav_ui_defs.dart';

class BottomBar extends StatefulWidget {
  final double speedKmh;
  final int? limitKmh; // limite de caminhão do trecho atual (null = sem dado)
  final String remainingDist;
  final String eta;
  final RadarPoint? radarAlert;
  final RadarDirMatch dirMatch; // sentido do radar vs motorista (só decora)

  const BottomBar({
    super.key,
    required this.speedKmh,
    required this.limitKmh,
    required this.remainingDist,
    required this.eta,
    required this.radarAlert,
    this.dirMatch = RadarDirMatch.unknown,
  });

  @override
  State<BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<BottomBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  // Limite que colore o velocímetro. NA ÁREA DE RADAR manda a velocidade do radar
  // (curada) — não o trecho da HERE, que crava valores errados e deixava o círculo
  // vermelho em velocidade legal do lado de um radar de 90 (report Gilberto
  // 2026-07-09). Fora de radar, cai no postado da via (HERE) capado no teto — a
  // rodovia posta 110 do carro, mas o velocímetro fica vermelho nos 90.
  int get _limit {
    final radar = widget.radarAlert;
    if (radar != null && radar.speedKmh > 0) {
      return truckRadarLimit(radar.speedKmh,
              officialTruckLimit: radar.truckLimitOff) ??
          kTruckCapKmh;
    }
    return min(widget.limitKmh ?? kTruckCapKmh, kTruckCapKmh);
  }

  @override
  void didUpdateWidget(BottomBar old) {
    super.didUpdateWidget(old);
    if (widget.speedKmh >= _limit && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    } else if (widget.speedKmh < _limit - 2 && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Color get _borderColor {
    if (widget.speedKmh >= _limit) return Colors.red.shade600;
    if (widget.speedKmh >= _limit - 10) return Colors.amber.shade600;
    return Colors.white24;
  }

  @override
  Widget build(BuildContext context) {
    final isOver = widget.speedKmh >= _limit;
    final isWarn = widget.speedKmh >= _limit - 10;
    final isLombada = widget.radarAlert != null &&
        widget.radarAlert!.type.toLowerCase().contains('lombada');

    return Container(
      color: const Color(0xFF212121),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, _) {
              final t = isOver ? _pulseAnim.value : 0.0;
              final borderColor = isOver
                  ? Color.lerp(Colors.red.shade600, Colors.red.shade300, t)!
                  : _borderColor;
              final borderW = isOver ? 2.0 + t * 2.5 : (isWarn ? 2.5 : 2.0);
              final bgColor = isOver
                  ? Color.lerp(
                      const Color(0xFF2C2C2C), Colors.red.shade900, t * 0.35)!
                  : const Color(0xFF2C2C2C);

              return Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bgColor,
                  border: Border.all(color: borderColor, width: borderW),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${widget.speedKmh.round()}',
                      style: TextStyle(
                        color: isOver
                            ? Color.lerp(
                                Colors.white, Colors.red.shade200, t)
                            : Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                    ),
                    Text(
                      'km/h',
                      style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 10,
                          height: 1.2),
                    ),
                  ],
                ),
              );
            },
          ),
          // Placa de limite da via removida (report Gilberto): o velocímetro que
          // muda de cor (amarelo→vermelho) já comunica o limite; a plaquinha era
          // ruído. limitKmh segue chegando pra alimentar o _limit das cores.
          const SizedBox(width: 16),
          Expanded(
            child: widget.radarAlert != null
                ? _RadarChip(
                    radar: widget.radarAlert!,
                    dirMatch: widget.dirMatch,
                    isLombada: isLombada,
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      BarItem(
                          top: widget.remainingDist, bottom: 'restante'),
                      BarItem(top: widget.eta, bottom: 'chegada'),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Chip do radar na barra inferior. A direção (dirMatch) e o status são
/// DECORAÇÃO: o chip aparece sempre (invariante — nunca suprime). Só muda a cor
/// e ganha uma etiqueta glanceável.
///  - same     → seta (radar fiscaliza o seu sentido), cor de alerta normal
///  - opposite → cor neutra + "sentido oposto" (é do outro lado, mas te avisa)
///  - inactive → cor neutra + "desativado" (fonte oficial rebaixou; ver voz→bip)
///  - unknown  → exatamente o visual de hoje, sem etiqueta
class _RadarChip extends StatelessWidget {
  final RadarPoint radar;
  final RadarDirMatch dirMatch;
  final bool isLombada;

  const _RadarChip({
    required this.radar,
    required this.dirMatch,
    required this.isLombada,
  });

  @override
  Widget build(BuildContext context) {
    final isInactive = radar.status == 'inactive';
    final isOpposite = dirMatch == RadarDirMatch.opposite;

    // Radar MÓVEL (ponto de fiscalização com radar portátil): mesmo alerta, só
    // não passa por câmera fixa — igual ao ícone do mapa. Drive 2026-09-02.
    final isMovel = radar.isMovel;
    // Pedágio: sem velocidade, nome da praça quando veio da HERE.
    final isPedagio = radar.type.toLowerCase().contains('pedagio');
    final Color color = isInactive
        ? Colors.blueGrey.shade700
        : isOpposite
            ? Colors.grey.shade700
            : isPedagio
                ? Colors.blue.shade700
                : isLombada
                    ? Colors.orange.shade700
                    : (isMovel ? kMovelColor : Colors.red.shade700);

    final eff =
        truckRadarLimit(radar.speedKmh, officialTruckLimit: radar.truckLimitOff);
    final mainText = isPedagio
        ? (radar.name == null ? 'Pedágio' : 'Pedágio ${radar.name}')
        : eff != null
            ? '$eff km/h'
            : (isLombada ? 'Lombada' : 'Radar');
    final tag = isInactive
        ? 'desativado'
        : isOpposite
            ? 'sentido oposto'
            : isPedagio
                ? (radar.priceBrl == null ? null : brl(radar.priceBrl!))
                : (isMovel ? 'móvel' : null);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isPedagio ? Icons.toll : (isMovel ? kMovelIcon : Icons.camera_alt),
              color: Colors.white, size: 20),
          const SizedBox(width: 8),
          if (dirMatch == RadarDirMatch.same && !isInactive) ...[
            const Icon(Icons.arrow_upward, color: Colors.white, size: 16),
            const SizedBox(width: 2),
          ],
          Flexible(
            child: Text(
              mainText,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
          ),
          if (tag != null) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                tag,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class BarItem extends StatelessWidget {
  final String top;
  final String bottom;

  const BarItem({super.key, required this.top, required this.bottom});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(top,
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        Text(bottom,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
      ],
    );
  }
}
