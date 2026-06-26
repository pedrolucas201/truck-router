import 'package:flutter/material.dart';
import '../models/route_event.dart';
import 'route_event_style.dart';

/// Degrau de proximidade do próximo evento. Controla visibilidade e destaque
/// da faixa. Breakpoints ajustados com o feedback do Gilberto (25/06): badge
/// vinho aparece em ~1 km, vira vermelho perto. Tunáveis no teste de estrada.
enum BadgeTier { far, mid, near }

/// FAR: > 1 km · MID (vinho): 500 m–1 km (inclusivo nas pontas) · NEAR (vermelho): < 500 m.
BadgeTier tierFor(double distanceM) {
  if (distanceM < 500) return BadgeTier.near;
  if (distanceM <= 1000) return BadgeTier.mid;
  return BadgeTier.far;
}

/// Faixa do próximo evento, renderizada na zona da barra preta do topo.
/// FAR → nada (mapa limpo). MID → discreta. NEAR → destacada + glow.
/// Hierarquia: nunca supera a instrução de manobra em peso visual.
class NextEventStrip extends StatelessWidget {
  final RouteEvent event;
  const NextEventStrip({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final tier = tierFor(event.distanceM);
    if (tier == BadgeTier.far) return const SizedBox.shrink();

    final near = tier == BadgeTier.near;
    final accent = event.type.accentColor;
    // MID: vermelho dessaturado (acento sobre preto). NEAR: acento cheio.
    final bg = near ? accent : Color.alphaBlend(accent.withAlpha(120), Colors.black);

    final inner = Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: near ? 8 : 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(near ? 10 : 9),
        border: Border.all(color: Colors.white.withAlpha(near ? 64 : 40)),
      ),
      child: Row(
        children: [
          Icon(event.type.icon, size: near ? 20 : 15, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            event.type.label.toUpperCase(),
            style: TextStyle(
              color: Colors.white,
              fontSize: near ? 16 : 13,
              fontWeight: near ? FontWeight.w800 : FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          Text(
            _fmtDist(event.distanceM),
            style: TextStyle(
              color: Colors.white,
              fontSize: near ? 16 : 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );

    return Container(
      color: Colors.black, // continua a barra preta do topo
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: near ? _GlowPulse(color: accent, child: inner) : inner,
    );
  }
}

String _fmtDist(double m) {
  if (m >= 10000) return '${(m / 1000).round()} km';
  if (m >= 1000) return '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  return '${m.round()} m';
}

/// Pulso via glow (box-shadow), NÃO via escala — sombra não afeta layout,
/// então não empurra a instrução de manobra na barra.
class _GlowPulse extends StatefulWidget {
  final Color color;
  final Widget child;
  const _GlowPulse({required this.color, required this.child});

  @override
  State<_GlowPulse> createState() => _GlowPulseState();
}

class _GlowPulseState extends State<_GlowPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _spread;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _spread = Tween<double>(begin: 2, end: 7)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        key: const ValueKey('next-event-glow'),
        animation: _spread,
        builder: (_, child) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: widget.color.withAlpha(90),
                spreadRadius: _spread.value,
                blurRadius: _spread.value * 2,
              ),
            ],
          ),
          child: child,
        ),
        child: widget.child,
      );
}
