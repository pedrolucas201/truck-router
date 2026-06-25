import 'package:flutter/material.dart';
import '../models/route_event.dart';

class RouteTimeline extends StatelessWidget {
  final List<RouteEvent> events;

  static const _maxItems = 4;

  const RouteTimeline({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    final display = events.take(_maxItems).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < display.length; i++) ...[
          _TimelineItem(event: display[i], isNext: i == 0),
          if (i < display.length - 1)
            Container(width: 1, height: 4, color: Colors.white.withAlpha(30)),
        ],
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final RouteEvent event;
  final bool isNext;

  const _TimelineItem({required this.event, required this.isNext});

  Color get _accentColor => switch (event.type) {
        RouteEventType.radar       => Colors.red.shade600,
        RouteEventType.restriction => Colors.red.shade600,
        RouteEventType.police      => Colors.blue.shade600,
        RouteEventType.scale       => Colors.purple.shade600,
        RouteEventType.restArea    => Colors.green.shade600,
      };

  // Ícones interinos do Material — distintos por tipo. Custom (conezinho etc.)
  // virão do Afonso depois.
  IconData get _icon => switch (event.type) {
        RouteEventType.radar       => Icons.camera_alt,            // câmera/radar
        RouteEventType.restriction => Icons.warning_amber_rounded, // bloqueio (cone)
        RouteEventType.police      => Icons.local_police,
        RouteEventType.scale       => Icons.monitor_weight,
        RouteEventType.restArea    => Icons.local_hotel,
      };

  String get _label => switch (event.type) {
        RouteEventType.radar       => 'Radar',
        RouteEventType.restriction => 'Restrição',
        RouteEventType.police      => 'Polícia',
        RouteEventType.scale       => 'Balança',
        RouteEventType.restArea    => 'Descanso',
      };

  String _fmtDist(double m) {
    if (m >= 10000) return '${(m / 1000).round()} km';
    if (m >= 1000)  return '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
    return '${m.round()} m';
  }

  @override
  Widget build(BuildContext context) {
    final size     = isNext ? 28.0 : 24.0;
    final iconSize = isNext ? 14.0 : 12.0;

    final box = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isNext
            ? _accentColor.withAlpha(50)
            : Colors.black.withAlpha(180),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: isNext ? _accentColor : Colors.white.withAlpha(25),
          width: isNext ? 1.5 : 1.0,
        ),
      ),
      child: Center(
        child: Opacity(
          opacity: isNext ? 1.0 : 0.35,
          child: Icon(_icon, size: iconSize, color: Colors.white),
        ),
      ),
    );

    if (!isNext) return box;

    // Próximo evento: chip rotulado e legível de relance — ícone + palavra
    // (Radar/Restrição/...) + distância. Resolve a ambiguidade do ícone-só.
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _accentColor.withAlpha(230),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 16, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            _label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _fmtDist(event.distanceM),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );

    // Pulsa só quando o evento está próximo — chama atenção na hora certa,
    // sem piscar à toa na periferia da visão quando ainda está longe.
    return event.distanceM < 800 ? _PulseWrap(child: chip) : chip;
  }
}

// Pulso sutil (escala) para destacar o próximo evento iminente.
class _PulseWrap extends StatefulWidget {
  final Widget child;
  const _PulseWrap({required this.child});

  @override
  State<_PulseWrap> createState() => _PulseWrapState();
}

class _PulseWrapState extends State<_PulseWrap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.06)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}
