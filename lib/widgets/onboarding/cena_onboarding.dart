import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'onboarding_logic.dart';

const kNeon = Color(0xFF5DFF3C);
const kFundo = Color(0xFF0E1720);
const kFundoEscuro = Color(0xFF050A14);

/// Cena de uma tela de apresentação: gradiente da marca, pista neon desenhada
/// (a mesma em todas as telas, é o que amarra o conjunto), caminhão balançando
/// e o elemento da dor entrando por deslize. Tudo animado pelo Flutter, sem
/// dependência nova. Com "reduzir animações" do sistema fica estático.
///
/// ponytail: hoje o caminhão é o SVG do loader e o elemento é um ícone num
/// selo neon. As imagens geradas (spec 24/09) entram trocando estes dois
/// widgets por `Image.asset`, sem tocar no fluxo.
class CenaOnboarding extends StatefulWidget {
  final TelaOnboarding tela;
  final bool ativa; // página visível: dispara o deslize do elemento
  const CenaOnboarding({super.key, required this.tela, required this.ativa});

  @override
  State<CenaOnboarding> createState() => _CenaOnboardingState();
}

class _CenaOnboardingState extends State<CenaOnboarding> with TickerProviderStateMixin {
  late final AnimationController _pista =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final AnimationController _entrada =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void initState() {
    super.initState();
    if (widget.ativa) _entrada.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final estatico = MediaQuery.of(context).disableAnimations;
    if (estatico) {
      _pista.stop();
      _pista.value = 0;
      _entrada.value = 1;
    } else if (!_pista.isAnimating) {
      _pista.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant CenaOnboarding old) {
    super.didUpdateWidget(old);
    if (widget.ativa && !old.ativa) _entrada.forward(from: 0);
  }

  @override
  void dispose() {
    _pista.dispose();
    _entrada.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entrada = CurvedAnimation(parent: _entrada, curve: Curves.easeOutCubic);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      return Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [kFundo, kFundoEscuro],
              ),
            ),
          ),
          // Brilho verde no alto, como na arte da marca.
          Positioned(
            left: -w * .2, top: -h * .35, width: w * .9, height: h * .7,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Color(0x335DFF3C), Color(0x005DFF3C)]),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _pista,
            builder: (_, _) => CustomPaint(painter: _PistaNeonPainter(_pista.value)),
          ),
          // Caminhão: balanço senoidal de 3 px, preso à pista.
          AnimatedBuilder(
            animation: _pista,
            builder: (_, child) => Positioned(
              left: w * .22, width: w * .56, bottom: h * .12 + math.sin(_pista.value * 2 * math.pi) * 3,
              child: child!,
            ),
            child: SvgPicture.asset('assets/loader/truck_carreta.svg', fit: BoxFit.contain),
          ),
          // Elemento da dor: entra da direita, sobre a pista, à frente do caminhão.
          AnimatedBuilder(
            animation: entrada,
            builder: (_, child) => Positioned(
              right: w * .08 + (1 - entrada.value) * w * .5, top: h * .12,
              child: Opacity(opacity: entrada.value, child: child),
            ),
            child: _SeloNeon(icone: widget.tela.icone, tamanho: math.min(w * .26, 120)),
          ),
        ],
      );
    });
  }
}

class _SeloNeon extends StatelessWidget {
  final IconData icone;
  final double tamanho;
  const _SeloNeon({required this.icone, required this.tamanho});

  @override
  Widget build(BuildContext context) => Container(
        width: tamanho, height: tamanho,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: kFundo,
          border: Border.all(color: kNeon, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x885DFF3C), blurRadius: 28)],
        ),
        child: Icon(icone, color: kNeon, size: tamanho * .5),
      );
}

/// Pista em perspectiva vindo do horizonte, bordas neon com brilho e
/// tracejado central correndo em direção ao motorista.
class _PistaNeonPainter extends CustomPainter {
  final double t; // 0..1, fase do tracejado
  _PistaNeonPainter(this.t);

  @override
  void paint(Canvas canvas, Size s) {
    final horizonte = s.height * .42;
    final base = s.height;
    final cx = s.width / 2;
    final larguraTopo = s.width * .08;
    final larguraBase = s.width * 1.1;

    final pista = Path()
      ..moveTo(cx - larguraTopo / 2, horizonte)
      ..lineTo(cx + larguraTopo / 2, horizonte)
      ..lineTo(cx + larguraBase / 2, base)
      ..lineTo(cx - larguraBase / 2, base)
      ..close();
    canvas.drawPath(pista, Paint()..color = const Color(0xFF0B1119));

    final brilho = Paint()
      ..color = kNeon.withValues(alpha: .55)
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    final borda = Paint()
      ..color = kNeon
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    for (final lado in [-1, 1]) {
      final linha = Path()
        ..moveTo(cx + lado * larguraTopo / 2, horizonte)
        ..lineTo(cx + lado * larguraBase / 2, base);
      canvas.drawPath(linha, brilho);
      canvas.drawPath(linha, borda);
    }

    // Tracejado central: posição em perspectiva (quadrática) pra acelerar
    // perto do motorista; a fase [t] faz ele correr.
    final tracejado = Paint()..color = Colors.white.withValues(alpha: .85);
    const n = 7;
    for (var i = 0; i < n; i++) {
      final f0 = ((i + t) / n);
      final f1 = ((i + t + .35) / n).clamp(0.0, 1.0);
      if (f0 >= 1) continue;
      final y0 = horizonte + (base - horizonte) * f0 * f0;
      final y1 = horizonte + (base - horizonte) * f1 * f1;
      final w0 = 2 + 10 * f0 * f0;
      final w1 = 2 + 10 * f1 * f1;
      final seg = Path()
        ..moveTo(cx - w0 / 2, y0)
        ..lineTo(cx + w0 / 2, y0)
        ..lineTo(cx + w1 / 2, y1)
        ..lineTo(cx - w1 / 2, y1)
        ..close();
      canvas.drawPath(seg, tracejado);
    }
  }

  @override
  bool shouldRepaint(_PistaNeonPainter old) => old.t != t;
}
