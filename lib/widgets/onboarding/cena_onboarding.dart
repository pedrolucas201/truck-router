import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'onboarding_logic.dart';

const kNeon = Color(0xFF5DFF3C);
const kFundo = Color(0xFF0E1720);
const kFundoEscuro = Color(0xFF050A14);
const _ambar = Color(0xFFFFB300);
const _vermelho = Color(0xFFFF3B3B);

/// Cena de uma tela de apresentação, toda desenhada ("neon wireframe"): a
/// gente vê a traseira do nosso caminhão seguindo pela pista, e cada tela traz
/// o que aparece à frente dele — pórtico com as placas, radar com flash,
/// cancela que sobe, caminhão parado no acostamento com o pisca.
///
/// Tudo é Canvas + dois AnimationControllers: [_loop] (pista correndo, piscas,
/// flash, balanço) e [_entrada] (o elemento da tela vem do horizonte quando a
/// página abre). Sem imagem, sem dependência. "Reduzir animações" = estático.
class CenaOnboarding extends StatefulWidget {
  final TelaOnboarding tela;
  final bool ativa;
  const CenaOnboarding({super.key, required this.tela, required this.ativa});

  @override
  State<CenaOnboarding> createState() => _CenaOnboardingState();
}

class _CenaOnboardingState extends State<CenaOnboarding> with TickerProviderStateMixin {
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final AnimationController _entrada =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.ativa) _entrada.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _loop.stop();
      _loop.value = 0.3;
      _entrada.value = 1;
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant CenaOnboarding old) {
    super.didUpdateWidget(old);
    if (widget.ativa && !old.ativa) _entrada.forward(from: 0);
  }

  @override
  void dispose() {
    _loop.dispose();
    _entrada.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entrada = CurvedAnimation(parent: _entrada, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: Listenable.merge([_loop, entrada]),
      builder: (_, _) => CustomPaint(
        painter: _CenaPainter(cena: widget.tela.cena, t: _loop.value, entrada: entrada.value),
        size: Size.infinite,
      ),
    );
  }
}

/// Geometria da pista em perspectiva: trapézio reto do horizonte (h·0,42) à
/// base. "Profundidade" d ∈ [0,1] vira y linear e meia-largura linear, e a
/// escala dos objetos acompanha a meia-largura — perspectiva de cartaz, não de
/// câmera, mas lê certo e é barata.
class _Pista {
  final Size s;
  late final double horizonte = s.height * .42;
  late final double base = s.height;
  late final double cx = s.width / 2;
  late final double hwTopo = s.width * .04;
  late final double hwBase = s.width * .55;
  _Pista(this.s);

  double y(double d) => horizonte + (base - horizonte) * d;
  double hw(double d) => hwTopo + (hwBase - hwTopo) * d;
  double escala(double d) => hw(d) / hwBase;
  /// Ponto na pista: [lateral] −1..1 (bordas), [d] profundidade.
  Offset p(double lateral, double d) => Offset(cx + lateral * hw(d), y(d));
}

class _CenaPainter extends CustomPainter {
  final Cena cena;
  final double t;       // fase do loop 0..1
  final double entrada; // 0..1, elemento chegando do horizonte
  _CenaPainter({required this.cena, required this.t, required this.entrada});

  // ── utilitários de traço ────────────────────────────────────────────────
  Paint _glow(Color c, double w, {double blur = 10}) => Paint()
    ..color = c.withValues(alpha: .55)
    ..strokeWidth = w
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
  Paint _linha(Color c, double w) => Paint()
    ..color = c
    ..strokeWidth = w
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _neon(Canvas c, Path p, {Color cor = kNeon, double w = 2.5}) {
    c.drawPath(p, _glow(cor, w * 3.5));
    c.drawPath(p, _linha(cor, w));
  }

  void _texto(Canvas c, String s, Offset centro, double tam,
      {Color cor = Colors.white, FontWeight peso = FontWeight.w800}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: cor, fontSize: tam, fontWeight: peso, letterSpacing: .5)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, centro - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = _Pista(size);
    _fundo(canvas, size, r);
    _pista(canvas, r);
    // Elementos à frente do caminhão: chegam do horizonte com a entrada.
    switch (cena) {
      case Cena.abertura:
        _lua(canvas, size);
      case Cena.rota:
        _portico(canvas, r, .38 * entrada + .02);
      case Cena.radar:
        _radar(canvas, r, .46 * entrada + .02);
      case Cena.pedagio:
        _pedagio(canvas, r, .36 * entrada + .02);
      case Cena.sos:
        _caminhaoParado(canvas, r, .42 * entrada + .02);
    }
    // Nosso caminhão, sempre no mesmo lugar, balançando.
    final bob = math.sin(t * 2 * math.pi) * 2.5;
    _caminhao(canvas, r, d: .70, lateral: 0, escalaExtra: 1, dy: bob,
        lanterna: _vermelho, pisca: false);
  }

  // ── fundo e pista ───────────────────────────────────────────────────────
  void _fundo(Canvas c, Size s, _Pista r) {
    c.drawRect(Offset.zero & s,
        Paint()..shader = const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [kFundo, kFundoEscuro]).createShader(Offset.zero & s));
    // Brilho verde no horizonte, como se a cidade estivesse lá na frente.
    c.drawCircle(Offset(r.cx, r.horizonte), s.width * .5,
        Paint()..shader = RadialGradient(colors: [kNeon.withValues(alpha: .16), kNeon.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: Offset(r.cx, r.horizonte), radius: s.width * .5)));
    // Estrelas fixas (determinísticas): pontinhos sem custo.
    final estrela = Paint()..color = Colors.white.withValues(alpha: .35);
    for (var i = 0; i < 26; i++) {
      final x = (i * 137.5) % s.width;
      final y = ((i * 71.3) % (r.horizonte * .9));
      c.drawCircle(Offset(x, y), i % 5 == 0 ? 1.6 : 1.0, estrela);
    }
  }

  void _pista(Canvas c, _Pista r) {
    final asfalto = Path()
      ..moveTo(r.p(-1, 0).dx, r.horizonte)
      ..lineTo(r.p(1, 0).dx, r.horizonte)
      ..lineTo(r.p(1, 1).dx, r.base)
      ..lineTo(r.p(-1, 1).dx, r.base)
      ..close();
    c.drawPath(asfalto, Paint()..color = const Color(0xFF0B1119));
    for (final lado in [-1.0, 1.0]) {
      _neon(c, Path()..moveTo(r.p(lado, 0).dx, r.horizonte)..lineTo(r.p(lado, 1).dx, r.base), w: 3);
    }
    // Tracejado central correndo em direção ao motorista.
    final tinta = Paint()..color = Colors.white.withValues(alpha: .85);
    const n = 7;
    for (var i = 0; i < n; i++) {
      final f0 = (i + t) / n;
      final f1 = ((i + t + .35) / n).clamp(0.0, 1.0);
      if (f0 >= 1) continue;
      final d0 = f0 * f0, d1 = f1 * f1;
      final w0 = 2 + 10 * d0, w1 = 2 + 10 * d1;
      c.drawPath(
          Path()
            ..moveTo(r.cx - w0 / 2, r.y(d0))
            ..lineTo(r.cx + w0 / 2, r.y(d0))
            ..lineTo(r.cx + w1 / 2, r.y(d1))
            ..lineTo(r.cx - w1 / 2, r.y(d1))
            ..close(),
          tinta);
    }
  }

  void _lua(Canvas c, Size s) {
    final centro = Offset(s.width * .8, s.height * .16);
    c.drawCircle(centro, s.width * .075, _glow(kNeon, 6, blur: 18));
    c.drawCircle(centro, s.width * .075, Paint()..color = const Color(0xFFE8FFE0));
    c.drawCircle(centro + Offset(s.width * .025, -s.width * .015), s.width * .07, Paint()..color = kFundo);
  }

  // ── nosso caminhão, visto de trás ───────────────────────────────────────
  void _caminhao(Canvas c, _Pista r,
      {required double d, required double lateral, required double escalaExtra,
      double dy = 0, required Color lanterna, required bool pisca}) {
    final e = r.escala(d) * escalaExtra;
    final larg = r.hwBase * 1.05 * e;        // baú ocupa boa parte da pista
    final alt = larg * 1.05;
    final base = r.p(lateral, d) + Offset(0, dy);
    final bau = Rect.fromCenter(center: base - Offset(0, alt / 2 + larg * .12), width: larg, height: alt);
    final rr = RRect.fromRectAndRadius(bau, Radius.circular(larg * .06));
    c.drawRRect(rr, Paint()..color = const Color(0xFF101C2A));
    c.drawRRect(rr, _glow(kNeon, 9));
    c.drawRRect(rr, _linha(kNeon, 2.5));
    // Portas do baú: linha central e dobradiças.
    _neon(c, Path()..moveTo(bau.center.dx, bau.top + alt * .08)..lineTo(bau.center.dx, bau.bottom - alt * .06), w: 1.5);
    // Faixa refletiva.
    c.drawRect(Rect.fromLTWH(bau.left + larg * .06, bau.bottom - alt * .16, larg * .88, alt * .03),
        Paint()..color = Colors.white.withValues(alpha: .55));
    // Para-choque e rodas.
    final pc = Rect.fromCenter(center: base - Offset(0, larg * .06), width: larg * 1.02, height: larg * .07);
    c.drawRRect(RRect.fromRectAndRadius(pc, const Radius.circular(3)), Paint()..color = const Color(0xFF223042));
    for (final lx in [-.36, -.24, .24, .36]) {
      c.drawOval(Rect.fromCenter(center: base + Offset(larg * lx, 0), width: larg * .12, height: larg * .09),
          Paint()..color = const Color(0xFF05080D));
    }
    // Lanternas: vermelhas normais; âmbar piscando quando é o parado.
    final acesa = !pisca || (t % .5) < .25;
    final corLuz = acesa ? lanterna : lanterna.withValues(alpha: .25);
    for (final lx in [-.42, .42]) {
      final centro = Offset(bau.left + larg * (.5 + lx), bau.bottom - alt * .07);
      if (acesa) c.drawCircle(centro, larg * .06, _glow(lanterna, 6, blur: 14));
      c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: centro, width: larg * .09, height: larg * .05), const Radius.circular(2)),
          Paint()..color = corLuz);
    }
  }

  // ── cena 2: pórtico com as placas ───────────────────────────────────────
  void _portico(Canvas c, _Pista r, double d) {
    final e = r.escala(d);
    final altura = r.s.height * .34 * e + r.s.height * .06;
    final esq = r.p(-1.18, d), dir = r.p(1.18, d);
    final topo = esq.dy - altura;
    final trave = Path()
      ..moveTo(esq.dx, esq.dy)..lineTo(esq.dx, topo)
      ..lineTo(dir.dx, topo)..lineTo(dir.dx, dir.dy);
    _neon(c, trave, w: 3);
    // Treliça na trave.
    final passo = (dir.dx - esq.dx) / 8;
    final tre = Path();
    for (var i = 0; i < 8; i++) {
      tre.moveTo(esq.dx + passo * i, topo);
      tre.lineTo(esq.dx + passo * (i + 1), topo + altura * .09);
    }
    _neon(c, tre, w: 1.2);
    // Três placas penduradas: altura, peso, eixos.
    final raio = math.max(10.0, (dir.dx - esq.dx) * .075);
    final placas = ['4,20 m', '25 t', '5 eixos'];
    for (var i = 0; i < 3; i++) {
      final cx = esq.dx + (dir.dx - esq.dx) * (.28 + .22 * i);
      final cy = topo + altura * .09 + raio * 1.6;
      _neon(c, Path()..moveTo(cx, topo + altura * .09)..lineTo(cx, cy - raio), w: 1.2);
      c.drawCircle(Offset(cx, cy), raio, Paint()..color = Colors.white);
      c.drawCircle(Offset(cx, cy), raio, _linha(_vermelho, raio * .18));
      _texto(c, placas[i], Offset(cx, cy), raio * .5, cor: const Color(0xFF0B1119));
    }
  }

  // ── cena 3: radar com flash e seta no sentido ───────────────────────────
  void _radar(Canvas c, _Pista r, double d) {
    final e = r.escala(d);
    final pe = r.p(1.12, d);
    final alturaPoste = r.s.height * .26 * e + r.s.height * .05;
    final topo = Offset(pe.dx, pe.dy - alturaPoste);
    _neon(c, Path()..moveTo(pe.dx, pe.dy)..lineTo(topo.dx, topo.dy)..lineTo(topo.dx - alturaPoste * .28, topo.dy), w: 3);
    final caixa = Rect.fromCenter(center: topo + Offset(-alturaPoste * .28, alturaPoste * .1), width: alturaPoste * .26, height: alturaPoste * .2);
    c.drawRRect(RRect.fromRectAndRadius(caixa, const Radius.circular(4)), Paint()..color = const Color(0xFF101C2A));
    _neon(c, Path()..addRRect(RRect.fromRectAndRadius(caixa, const Radius.circular(4))), w: 2);
    final lente = caixa.center + Offset(0, caixa.height * .05);
    c.drawCircle(lente, caixa.height * .22, Paint()..color = const Color(0xFF05080D));
    c.drawCircle(lente, caixa.height * .22, _linha(kNeon, 1.5));
    // Flash: um estouro curto por ciclo.
    final fase = t % 1;
    if (fase < .12) {
      final k = 1 - fase / .12;
      c.drawCircle(lente, caixa.height * (.5 + 1.8 * (1 - k)), Paint()..color = Colors.white.withValues(alpha: .75 * k));
    }
    // Seta no asfalto, no sentido do caminhão (pra frente), um pouco antes do radar.
    final dSeta = math.min(1.0, d + .16);
    final es = r.escala(dSeta);
    final base = r.p(0, dSeta);
    final comp = r.s.height * .09 * es + 8;
    final larg = r.hw(dSeta) * .35;
    final seta = Path()
      ..moveTo(base.dx, base.dy - comp)
      ..lineTo(base.dx - larg, base.dy - comp * .45)
      ..lineTo(base.dx - larg * .4, base.dy - comp * .45)
      ..lineTo(base.dx - larg * .4, base.dy)
      ..lineTo(base.dx + larg * .4, base.dy)
      ..lineTo(base.dx + larg * .4, base.dy - comp * .45)
      ..lineTo(base.dx + larg, base.dy - comp * .45)
      ..close();
    c.drawPath(seta, Paint()..color = kNeon.withValues(alpha: .9));
    c.drawPath(seta, _glow(kNeon, 6));
  }

  // ── cena 4: praça de pedágio com cancela subindo ────────────────────────
  void _pedagio(Canvas c, _Pista r, double d) {
    final e = r.escala(d);
    final altura = r.s.height * .30 * e + r.s.height * .06;
    final esq = r.p(-1.25, d), dir = r.p(1.25, d);
    final topo = esq.dy - altura;
    // Cobertura: trave grossa com "telhado" e pilares nas pontas.
    final cob = Rect.fromLTRB(esq.dx, topo, dir.dx, topo + altura * .14);
    c.drawRRect(RRect.fromRectAndRadius(cob, const Radius.circular(4)), Paint()..color = const Color(0xFF101C2A));
    _neon(c, Path()..addRRect(RRect.fromRectAndRadius(cob, const Radius.circular(4))), w: 3);
    _neon(c, Path()..moveTo(esq.dx + 4, cob.bottom)..lineTo(esq.dx + 4, esq.dy)..moveTo(dir.dx - 4, cob.bottom)..lineTo(dir.dx - 4, dir.dy), w: 3);
    // Luzes da cobertura.
    for (var i = 1; i < 6; i++) {
      final x = esq.dx + (dir.dx - esq.dx) * i / 6;
      c.drawCircle(Offset(x, cob.bottom + 3), 2.5, Paint()..color = Colors.white);
      c.drawCircle(Offset(x, cob.bottom + 3), 6, Paint()..color = Colors.white.withValues(alpha: .18));
    }
    // Cabine à esquerda e placa com o valor.
    final cab = Rect.fromLTWH(esq.dx + (dir.dx - esq.dx) * .12, esq.dy - altura * .48, (dir.dx - esq.dx) * .16, altura * .48);
    c.drawRect(cab, Paint()..color = const Color(0xFF101C2A));
    _neon(c, Path()..addRect(cab), w: 2);
    c.drawRect(Rect.fromLTWH(cab.left + cab.width * .2, cab.top + cab.height * .15, cab.width * .6, cab.height * .35),
        Paint()..color = _ambar.withValues(alpha: .85));
    final placa = Rect.fromCenter(center: Offset(cob.center.dx, cob.bottom + altura * .2), width: (dir.dx - esq.dx) * .34, height: altura * .16);
    c.drawRRect(RRect.fromRectAndRadius(placa, const Radius.circular(4)), Paint()..color = kNeon);
    _texto(c, 'R\$ 28,50', placa.center, placa.height * .55, cor: const Color(0xFF06140A));
    // Cancela: horizontal enquanto chega, sobe no fim da entrada.
    final sobe = ((entrada - .55) / .45).clamp(0.0, 1.0);
    final ang = -math.pi / 2.2 * Curves.easeOutBack.transform(sobe);
    final pivo = Offset(cab.right + 4, cab.bottom - cab.height * .25);
    final comp = (dir.dx - esq.dx) * .62;
    final ponta = pivo + Offset(math.cos(ang) * comp, math.sin(ang) * comp);
    c.drawLine(pivo, ponta, _glow(_vermelho, 10));
    c.drawLine(pivo, ponta, _linha(Colors.white, 5));
    // Listras vermelhas da cancela.
    for (var i = 0; i < 5; i++) {
      final a = pivo + (ponta - pivo) * (i / 5 + .05);
      final b = pivo + (ponta - pivo) * (i / 5 + .13);
      c.drawLine(a, b, _linha(_vermelho, 5));
    }
    c.drawCircle(pivo, 5, Paint()..color = kNeon);
  }

  // ── cena 5: caminhão parado no acostamento, pisca-alerta ligado ─────────
  void _caminhaoParado(Canvas c, _Pista r, double d) {
    // Um pouco à direita da pista, menor porque está mais longe.
    _caminhao(c, r, d: d, lateral: 1.05, escalaExtra: .8, lanterna: _ambar, pisca: true);
    // Selo S.O.S. pulsando acima dele.
    final topo = r.p(1.05, d) - Offset(0, r.hwBase * 1.05 * r.escala(d) * .8 * 1.3);
    final pulso = .5 + .5 * math.sin(t * 2 * math.pi);
    final raio = math.max(14.0, r.s.width * .055) * (1 + .08 * pulso);
    c.drawCircle(topo, raio, Paint()..color = _vermelho.withValues(alpha: .18 + .18 * pulso));
    c.drawCircle(topo, raio * .78, Paint()..color = _vermelho);
    c.drawCircle(topo, raio * .78, _linha(Colors.white, 2));
    _texto(c, 'SOS', topo, raio * .6);
  }

  @override
  bool shouldRepaint(_CenaPainter old) => old.t != t || old.entrada != entrada || old.cena != cena;
}
