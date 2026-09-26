import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cena_onboarding.dart' show kNeon, kFundo, kFundoEscuro;
import 'trecho.dart';

/// Radar de varredura neon do "seu trecho": o caminhão no centro, anéis de
/// distância, e os pontos reais do asset acendendo quando o feixe passa por
/// eles. Sem [resumo] = procurando (só o feixe girando). Sem GoogleMap de
/// propósito: platform view pesada no onboarding e histórico de tela cinza.
class RadarVarredura extends StatefulWidget {
  final ResumoTrecho? resumo;
  final bool visivel;
  const RadarVarredura({super.key, this.resumo, this.visivel = true});

  @override
  State<RadarVarredura> createState() => _RadarVarreduraState();
}

class _RadarVarreduraState extends State<RadarVarredura> with SingleTickerProviderStateMixin {
  late final AnimationController _giro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
  /// Voltas completas desde que o resumo chegou: na 1ª volta os pontos acendem
  /// conforme o feixe passa; depois ficam acesos.
  double _voltasDesdeResumo = -1;
  double _ultimoValor = 0;
  /// Ângulo do feixe (rad) quando o resumo chegou: a revelação conta daí.
  double _inicio = 0;
  bool _estatico = false;

  @override
  void initState() {
    super.initState();
    _giro.addListener(_conta);
    if (widget.resumo != null) _voltasDesdeResumo = 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _estatico = MediaQuery.of(context).disableAnimations;
    _ajustaRelogio();
  }

  @override
  void didUpdateWidget(covariant RadarVarredura old) {
    super.didUpdateWidget(old);
    if (widget.resumo != null && old.resumo == null) {
      _voltasDesdeResumo = 0;
      _inicio = _giro.value * 2 * math.pi;
    }
    _ajustaRelogio();
  }

  void _ajustaRelogio() {
    final anda = widget.visivel && !_estatico;
    if (anda && !_giro.isAnimating) _giro.repeat();
    if (!anda && _giro.isAnimating) _giro.stop();
  }

  void _conta() {
    if (_voltasDesdeResumo >= 0) {
      final d = _giro.value - _ultimoValor;
      _voltasDesdeResumo += d < 0 ? d + 1 : d;
    }
    _ultimoValor = _giro.value;
  }

  @override
  void dispose() {
    _giro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.visivel ? 1 : 0,
      duration: const Duration(milliseconds: 350),
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _giro,
          builder: (_, _) => CustomPaint(
            painter: _Painter(
              resumo: widget.resumo,
              feixe: _estatico ? 0 : _giro.value * 2 * math.pi,
              revelado: _estatico ? 99 : _voltasDesdeResumo,
              inicio: _inicio,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  final ResumoTrecho? resumo;
  final double feixe; // rad, 0 = norte
  final double revelado; // voltas desde o resumo
  final double inicio; // feixe quando o resumo chegou
  _Painter({required this.resumo, required this.feixe, required this.revelado, required this.inicio});

  static const _vermelho = Color(0xFFFF3B3B);

  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [kFundoEscuro, kFundo]).createShader(Offset.zero & s));
    final centro = Offset(s.width / 2, s.height * .52);
    final r = math.min(s.width, s.height) * .44;
    final raioKm = resumo?.raioKm ?? 30;

    // Anéis e cruz.
    final anel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = kNeon.withValues(alpha: .25);
    for (var i = 1; i <= 3; i++) {
      c.drawCircle(centro, r * i / 3, anel);
      _texto(c, '${(raioKm * i / 3).round()} km', centro + Offset(6, -r * i / 3 + 4), 11,
          kNeon.withValues(alpha: .55));
    }
    c.drawLine(centro - Offset(r, 0), centro + Offset(r, 0), anel);
    c.drawLine(centro - Offset(0, r), centro + Offset(0, r), anel);

    // Feixe: setor com rastro.
    final ret = Rect.fromCircle(center: centro, radius: r);
    final inicio = feixe - math.pi / 2; // 0 = norte → canvas começa no leste
    c.drawArc(ret, inicio - .9, .9, true, Paint()
      ..shader = SweepGradient(
        startAngle: 0, endAngle: 2 * math.pi,
        transform: GradientRotation(inicio - .9),
        colors: [kNeon.withValues(alpha: 0), kNeon.withValues(alpha: .28)],
        stops: const [0, .143],
      ).createShader(ret));
    c.drawLine(centro, centro + Offset(math.cos(inicio), math.sin(inicio)) * r,
        Paint()..color = kNeon..strokeWidth = 2);

    // Pontos: acendem quando o feixe passa na 1ª volta.
    final pontos = resumo?.pontos ?? const <PontoTrecho>[];
    for (final p in pontos) {
      final aceso = revelado >= 1 || _feixePassou(p.rumo);
      if (!aceso) continue;
      final pos = centro + Offset(math.sin(p.rumo), -math.cos(p.rumo)) * (r * (p.km / raioKm).clamp(0.0, 1.0));
      // Brilho de "acabou de ser varrido": decai com a distância angular.
      final atras = _normaliza(feixe - p.rumo);
      final brilho = (1 - atras / (2 * math.pi)).clamp(.35, 1.0);
      if (p.tipo == TipoPonto.radar) {
        c.drawCircle(pos, 7, Paint()..color = kNeon.withValues(alpha: .25 * brilho)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
        c.drawCircle(pos, 3.2, Paint()..color = kNeon.withValues(alpha: brilho));
      } else {
        final t = Path()
          ..moveTo(pos.dx, pos.dy - 6)
          ..lineTo(pos.dx + 6, pos.dy + 5)
          ..lineTo(pos.dx - 6, pos.dy + 5)
          ..close();
        c.drawPath(t, Paint()..color = _vermelho.withValues(alpha: .3 * brilho)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        c.drawPath(t, Paint()..color = _vermelho.withValues(alpha: brilho));
      }
    }

    // Você, no centro.
    c.drawCircle(centro, 16, Paint()..color = kNeon.withValues(alpha: .18));
    const ic = Icons.local_shipping;
    final tp = TextPainter(
      text: TextSpan(text: String.fromCharCode(ic.codePoint),
          style: TextStyle(fontFamily: ic.fontFamily, package: ic.fontPackage, fontSize: 22, color: kNeon)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, centro - Offset(tp.width / 2, tp.height / 2));
  }

  bool _feixePassou(double rumo) {
    if (revelado < 0) return false;
    // Na 1ª volta, acende o que o feixe já cruzou desde que o resumo chegou.
    return _normaliza(rumo - inicio) <= revelado * 2 * math.pi;
  }

  static double _normaliza(double a) {
    final m = a % (2 * math.pi);
    return m < 0 ? m + 2 * math.pi : m;
  }

  void _texto(Canvas c, String s, Offset o, double tam, Color cor) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: cor, fontSize: tam, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, o);
  }

  @override
  bool shouldRepaint(_Painter old) => true;
}
