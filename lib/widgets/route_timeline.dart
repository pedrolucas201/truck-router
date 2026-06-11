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

  IconData get _icon => switch (event.type) {
        RouteEventType.radar       => Icons.speed,
        RouteEventType.restriction => Icons.block,
        RouteEventType.police      => Icons.local_police,
        RouteEventType.scale       => Icons.monitor_weight,
        RouteEventType.restArea    => Icons.local_hotel,
      };

  String _fmtDist(double m) {
    if (m >= 10000) return '${(m / 1000).round()}km';
    if (m >= 1000)  return '${(m / 1000).toStringAsFixed(1)}km';
    return '${m.round()}m';
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: _accentColor.withAlpha(220),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _fmtDist(event.distanceM),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 7,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 3),
        box,
      ],
    );
  }
}
