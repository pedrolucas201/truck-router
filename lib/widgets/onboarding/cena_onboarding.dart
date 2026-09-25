import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'onboarding_logic.dart';

const kNeon = Color(0xFF5DFF3C);
const kFundo = Color(0xFF0E1720);
const kFundoEscuro = Color(0xFF050A14);
const _ambar = Color(0xFFFFB300);
const _vermelho = Color(0xFFFF3B3B);
const _branco = Color(0xFFFFF4D6);
const _vermelhoEscuro = Color(0xFF8A1F1F);

/// Radar: velocidade do herói em função do avanço do evento. Chega a 98 e
/// cai pra 90 entre -1.35 e -.95, antes de a câmera (em -.85) fotografar.
double kmhRadar(double avanco) => (98 - 8 * ((avanco + 1.35) / .4).clamp(0.0, 1.0)).roundToDouble();

/// Cena de uma tela de apresentação: side-scroller visto de lado, à noite.
/// O nosso caminhão (sprite `heroi.webp`, com o alien na janela) fica parado
/// no centro e o mundo passa por ele em três velocidades: morros e cidade ao
/// fundo (devagar), árvores (meio), pista com postes e tracejado (rápido).
/// Cada tela traz o seu evento vindo da direita, no ritmo da pista: pórtico
/// com as placas, radar com flash, praça com cancela subindo, caminhão parado
/// (sprite `parado.webp`) em que o nosso freia atrás. Os selos aparecem na
/// hora do evento com os números reais do app.
///
/// Relógio: um [Ticker] integra a distância percorrida (`_dist`, em larguras
/// de tela) com a velocidade da cena, que só cai a zero no S.O.S. Tudo que
/// passa é função de `_dist`; o que pulsa é função do tempo. "Reduzir
/// animações" = um quadro parado com o evento à vista.
class CenaOnboarding extends StatefulWidget {
  final TelaOnboarding tela;
  final bool ativa;
  const CenaOnboarding({super.key, required this.tela, required this.ativa});

  @override
  State<CenaOnboarding> createState() => _CenaOnboardingState();
}

class _CenaOnboardingState extends State<CenaOnboarding> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration _ultimo = Duration.zero;
  double _dist = 0;     // larguras de tela percorridas
  double _tempo = 0;    // segundos desde que a página ficou ativa
  double _x0 = -10;     // posição (mundo) onde o evento desta tela começa
  double _v = 1;        // velocidade atual, 0..1
  double? _tParou;      // _tempo em que a velocidade chegou a zero (S.O.S.)
  bool _estatico = false;

  /// Velocidade da pista, em larguras de tela por segundo.
  static const _vel = .55;

  @override
  void initState() {
    super.initState();
    if (widget.ativa) _armaEvento();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _estatico = MediaQuery.of(context).disableAnimations;
    if (widget.tela.cena == Cena.sos) precacheImage(const AssetImage('assets/onboarding/acena.webp'), context);
    if (_estatico) {
      _ticker.stop();
      _dist = 0;
      _x0 = .75; // evento no meio da tela, quadro parado
      _tempo = 10;
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(covariant CenaOnboarding old) {
    super.didUpdateWidget(old);
    if (widget.ativa && !old.ativa) _armaEvento();
  }

  void _armaEvento() {
    _tempo = 0;
    _tParou = null;
    _x0 = _dist + 1.5; // entra pela direita ~1 s depois de abrir
  }

  void _tick(Duration agora) {
    final dt = ((agora - _ultimo).inMicroseconds / 1e6).clamp(0.0, .05);
    _ultimo = agora;
    _v = _velocidade();
    if (_v == 0) {
      _tParou ??= _tempo;
    } else {
      _tParou = null;
    }
    setState(() {
      _dist += dt * _vel * _v;
      _tempo += dt;
      // O evento repete em loop (como no Radarbot): quando já passou, volta
      // pela direita. O S.O.S. não repete: o caminhão fica parado.
      // Renasce fora da tela: o aviso do radar dispara em -1.35 e um evento
      // rearmado em .9 nasceria já avisado.
      if (widget.tela.cena != Cena.sos && _dist - _x0 > 1.7) _x0 = _dist + 1.5;
    });
  }

  /// No S.O.S. o nosso caminhão freia atrás do parado; nas outras telas a
  /// pista corre sempre.
  /// Abertura: o herói entra pela esquerda (0 → 1 em 1,4 s, easeOut); a
  /// pista só começa a correr quando ele está quase no lugar.
  double _entrada() {
    if (widget.tela.cena != Cena.abertura || _estatico) return 1;
    return Curves.easeOutCubic.transform((_tempo / 1.4).clamp(0.0, 1.0));
  }

  double _velocidade() {
    if (widget.tela.cena == Cena.abertura && !_estatico) return ((_tempo - 1.0) / .6).clamp(0.0, 1.0);
    if (widget.tela.cena == Cena.radar) return .85 + .15 * (kmhRadar(_dist - _x0) - 90) / 8;
    if (widget.tela.cena == Cena.pedagio) {
      // Folga entre o para-choque e a cancela (pivô em x0 + .25): freia até
      // um quarto da velocidade, espera a cancela subir, arranca.
      final folga = -(_dist - _x0) - .55;
      if (folga > .45) return 1;
      if (folga > .05) return .25 + .75 * (folga - .05) / .4;
      if (folga > -.05) return .25;
      return (.25 + .75 * (-folga - .05) / .3).clamp(.25, 1.0);
    }
    if (widget.tela.cena != Cena.sos) return 1;
    final folga = (_x0 - _dist) - _Geo.heroDirSosF - .04; // distância até o parado
    if (folga < .012) return 0;
    return (folga / .5).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cena = widget.tela.cena;
    final q = _Quadro(cena: cena, dist: _dist, x0: _x0, tempo: _tempo, v: _v, estatico: _estatico,
        farol: cena != Cena.abertura || _estatico || _tempo > .9,
        paradoHa: _tParou == null ? -1 : _tempo - _tParou!);
    return ClipRect(
      child: LayoutBuilder(builder: (_, box) {
        final g = _Geo(Size(box.maxWidth, box.maxHeight), sos: cena == Cena.sos);
        g.heroDx = -(g.w * _Geo.heroEsqF + g.heroLarg) * (1 - _entrada());
        final bob = _estatico ? 0.0 : math.sin(_tempo * 2 * math.pi * 1.3) * 2 * _v;
        return Stack(fit: StackFit.expand, children: [
          CustomPaint(painter: _FundoPainter(q, g)),
          // Parou atrás do S.O.S.: o alien acena (mesmo sprite, braço fora).
          _Sprite(asset: cena == Cena.sos && _v == 0 ? 'acena' : 'heroi',
              esq: g.heroEsq, larg: g.heroLarg, chao: g.chao, dy: bob, g: g,
              rodas: _Roda.heroi, giro: (_dist * g.w + g.heroDx) / (g.heroLarg * _Roda.pneuF)),
          if (cena == Cena.sos)
            _Sprite(asset: 'parado', esq: g.x(q.x0), larg: g.paradoLarg, chao: g.chao, dy: 0, g: g),
          CustomPaint(painter: _FrentePainter(q, g)),
        ]);
      }),
    );
  }
}

/// Sprite apoiado no chão, com reflexo no asfalto molhado (o mesmo sprite de
/// cabeça pra baixo, esmaecido e cortado na pista).
class _Sprite extends StatelessWidget {
  final String asset;
  final double esq, larg, chao, dy;
  final _Geo g;
  /// Aros que giram: cópia do próprio sprite recortada em círculo e rodada
  /// em [giro] radianos (positivo = horário = caminhão indo pra direita).
  final List<_Roda> rodas;
  final double giro;
  const _Sprite({required this.asset, required this.esq, required this.larg, required this.chao, required this.dy, required this.g,
      this.rodas = const [], this.giro = 0});

  @override
  Widget build(BuildContext context) {
    // Os sprites foram gerados com a cabine pra esquerda; o mundo passa da
    // direita pra esquerda, então o caminhão anda pra DIREITA: espelhar.
    final img = Transform.flip(flipX: true, child: Image.asset('assets/onboarding/$asset.webp', width: larg, fit: BoxFit.fitWidth,
        gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox.shrink()));
    return Stack(children: [
      Positioned(
        left: esq, top: chao + dy, width: larg, height: g.s.height - chao,
        child: ClipRect(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (r) => LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.white.withValues(alpha: .22), Colors.white.withValues(alpha: 0)],
              stops: const [0, .8],
            ).createShader(r),
            child: Align(alignment: Alignment.topCenter, child: Transform.flip(flipY: true, child: img)),
          ),
        ),
      ),
      Positioned(left: esq, bottom: g.s.height - chao - dy, width: larg, child: img),
      for (final r in rodas)
        Positioned(
          left: esq + larg * r.cx - larg * r.r, top: chao + dy - alt + alt * r.cy - larg * r.r,
          width: larg * r.r * 2, height: larg * r.r * 2,
          child: ClipOval(
            child: Transform.rotate(
              angle: giro,
              child: OverflowBox(
                alignment: Alignment.topLeft, minWidth: 0, maxWidth: larg, minHeight: 0, maxHeight: alt,
                child: Transform.translate(offset: Offset(larg * r.r - larg * r.cx, larg * r.r - alt * r.cy), child: img),
              ),
            ),
          ),
        ),
    ]);
  }

  double get alt => larg * (567 / 1200);
}

/// Um aro do sprite: centro em frações (já espelhadas) do sprite e raio em
/// fração da largura. Medidos no `heroi.webp` (1200×567): aros em x=330,
/// 930 e 1045, y=487; raio do aro 40/35 px, do pneu 78 px.
class _Roda {
  final double cx, cy, r;
  const _Roda(this.cx, this.cy, this.r);
  static const pneuF = 78 / 1200;
  static const heroi = [
    _Roda(1 - 330 / 1200, 487 / 567, 38 / 1200),
    _Roda(1 - 930 / 1200, 487 / 567, 33 / 1200),
    _Roda(1 - 1045 / 1200, 487 / 567, 33 / 1200),
  ];
}

/// Geometria da cena em frações do box. Tudo que é posição mora aqui.
class _Geo {
  final Size s;
  final bool sos;
  _Geo(this.s, {this.sos = false});
  double get w => s.width;
  double get h => s.height;
  double get horizonte => h * .60;
  double get pistaTopo => h * .74;
  double get chao => h * .87;         // linha das rodas
  // No S.O.S. o herói encosta na esquerda (corta um pouco do baú) pra sobrar
  // tela pro caminhão parado, cabine com capô aberto à vista.
  static const heroEsqF = .10, heroEsqSosF = -.08, heroLargF = .70;
  static const heroDirF = heroEsqF + heroLargF;
  static const heroDirSosF = heroEsqSosF + heroLargF;
  /// Deslocamento horizontal do herói (entrada pela esquerda na abertura).
  double heroDx = 0;
  double get heroEsq => w * (sos ? heroEsqSosF : heroEsqF) + heroDx;
  double get heroLarg => w * heroLargF;
  double get heroDir => w * (sos ? heroDirSosF : heroDirF) + heroDx;
  double get heroTopo => chao - heroLarg * (567 / 1200);
  double get paradoLarg => w * .36; // menor: parado mais à frente, cabine com capô à vista
  /// Posição de mundo (em larguras) → x na tela, na velocidade da pista.
  double x(double mundo) => w * (mundo - _distAtual);
  double _distAtual = 0;
}

/// Estado de um quadro: o que o painter precisa pra desenhar.
class _Quadro {
  final Cena cena;
  final double dist, x0, tempo, v;
  final bool estatico;
  /// Faróis e lanternas acesos (na abertura acendem quando o herói chega).
  final bool farol;
  /// Segundos desde que o herói parou (S.O.S.); -1 se está andando.
  final double paradoHa;
  _Quadro({required this.cena, required this.dist, required this.x0, required this.tempo, required this.v, required this.estatico,
      this.farol = true, this.paradoHa = -1});
  /// Pisca-farol de caminhoneiro: duas piscadas logo depois de parar.
  bool get piscaFarol => paradoHa >= 0 && ((paradoHa >= .4 && paradoHa < .6) || (paradoHa >= .8 && paradoHa < 1.0));
  /// Progresso do evento: 0 quando entra pela direita, 1 quando o centro dele
  /// cruza o centro do herói (em larguras de tela).
  double get avanco => dist - x0;
  double get seno => .5 + .5 * math.sin(tempo * 2 * math.pi);
}

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
void _luz(Canvas c, Offset centro, double raio, Color cor, double k) {
  if (k <= 0) return;
  c.drawCircle(centro, raio, Paint()
    ..shader = RadialGradient(colors: [cor.withValues(alpha: k), cor.withValues(alpha: 0)])
        .createShader(Rect.fromCircle(center: centro, radius: raio)));
}
void _texto(Canvas c, String s, Offset centro, double tam,
    {Color cor = Colors.white, FontWeight peso = FontWeight.w800}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(color: cor, fontSize: tam, fontWeight: peso, letterSpacing: .3)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, centro - Offset(tp.width / 2, tp.height / 2));
}
/// Hash determinístico 0..1 pra espalhar árvores, luzes e estrelas.
double _hash(int i) {
  var x = (i * 0x9E3779B1) & 0xFFFFFFFF;
  x ^= x >> 15; x = (x * 0x85EBCA6B) & 0xFFFFFFFF; x ^= x >> 13;
  return (x & 0xFFFF) / 0xFFFF;
}

// ═══════════════════════════════════════════════════════════════════════════
// Fundo: céu, camadas em parallax, pista e o objeto do evento (atrás do herói).
// ═══════════════════════════════════════════════════════════════════════════
class _FundoPainter extends CustomPainter {
  final _Quadro q;
  final _Geo g;
  _FundoPainter(this.q, this.g) {
    g._distAtual = q.dist;
  }

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    c.drawRect(Offset.zero & s, Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [kFundoEscuro, kFundo]).createShader(Offset.zero & s));
    _estrelas(c, w, h);
    _lua(c, w, h);
    _morrosECidade(c, w, h);
    _arvores(c, w, h);
    _pista(c, w, h);
    switch (q.cena) {
      case Cena.abertura:
        _placaKm(c);
      case Cena.rota:
        _portico(c);
      case Cena.radar:
        _radar(c);
      case Cena.pedagio:
        _pedagio(c);
      case Cena.sos:
        break;
    }
    _postes(c, w, h);
  }

  void _estrelas(Canvas c, double w, double h) {
    for (var i = 0; i < 40; i++) {
      final x = _hash(i) * w, y = _hash(i + 100) * g.horizonte * .85;
      final cint = .25 + .45 * (.5 + .5 * math.sin(q.tempo * 1.5 + i));
      c.drawCircle(Offset(x, y), i % 6 == 0 ? 1.5 : 1, Paint()..color = Colors.white.withValues(alpha: cint));
    }
  }

  void _lua(Canvas c, double w, double h) {
    final centro = Offset(w * .82, h * .17);
    final r = w * .055;
    c.drawCircle(centro, r * 1.6, Paint()..shader = RadialGradient(
        colors: [_branco.withValues(alpha: .25), _branco.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: centro, radius: r * 1.6)));
    c.drawCircle(centro, r, Paint()..color = const Color(0xFFE8FFE0));
    c.drawCircle(centro + Offset(r * .35, -r * .2), r * .92, Paint()..color = kFundoEscuro);
  }

  /// Camada longe (12% da pista): silhueta de morros e luzes de cidade.
  void _morrosECidade(Canvas c, double w, double h) {
    const k = .12;
    final base = g.horizonte;
    final alt = h * .10;
    final p = Path()..moveTo(0, base + 2);
    for (var i = 0; i <= 48; i++) {
      final x = w * i / 48;
      final u = (x / w + q.dist * k) * 2 * math.pi;
      final y = base - alt * (.45 + .3 * math.sin(u * .9) + .2 * math.sin(u * 2.3 + 1.2) + .1 * math.sin(u * 5.1));
      p.lineTo(x, y);
    }
    p..lineTo(w, base + 2)..close();
    c.drawPath(p, Paint()..color = const Color(0xFF08111B));
    c.drawPath(p, _linha(kNeon.withValues(alpha: .15), 1));
    // Luzes: uma a cada 3% de largura no mundo, com hash decidindo se existe.
    final passo = w * .03;
    final ini = (q.dist * k * w / passo).floor();
    for (var i = ini; i < ini + (w / passo).ceil() + 1; i++) {
      final hx = _hash(i);
      if (hx > .55) continue;
      final x = i * passo - q.dist * k * w;
      final u = (x / w + q.dist * k) * 2 * math.pi;
      final topo = base - alt * (.45 + .3 * math.sin(u * .9) + .2 * math.sin(u * 2.3 + 1.2) + .1 * math.sin(u * 5.1));
      final y = base - (base - topo) * (.15 + .7 * _hash(i + 7));
      final cor = i % 5 == 0 ? _ambar : Colors.white;
      final cint = .5 + .5 * (.5 + .5 * math.sin(q.tempo * 2 + i));
      c.drawCircle(Offset(x, y), 1.2, Paint()..color = cor.withValues(alpha: cint));
    }
  }

  /// Camada do meio (45%): árvores em silhueta com um fio de neon.
  void _arvores(Canvas c, double w, double h) {
    const k = .45;
    final passo = w * .19;
    final ini = (q.dist * k * w / passo).floor() - 1;
    for (var i = ini; i < ini + (w / passo).ceil() + 2; i++) {
      if (_hash(i + 300) > .7) continue;
      final x = i * passo + (_hash(i + 400) - .5) * passo * .6 - q.dist * k * w;
      final alt = h * (.08 + .07 * _hash(i + 500));
      final base = g.pistaTopo - h * .01;
      final copa = Path()
        ..moveTo(x, base - alt)
        ..lineTo(x + alt * .38, base - alt * .35)
        ..lineTo(x + alt * .18, base - alt * .35)
        ..lineTo(x + alt * .5, base - alt * .05)
        ..lineTo(x - alt * .5, base - alt * .05)
        ..lineTo(x - alt * .18, base - alt * .35)
        ..lineTo(x - alt * .38, base - alt * .35)
        ..close();
      c.drawPath(copa, Paint()..color = const Color(0xFF0A1622));
      c.drawPath(copa, _linha(kNeon.withValues(alpha: .35), 1));
      c.drawLine(Offset(x, base - alt * .05), Offset(x, base), _linha(const Color(0xFF0A1622), 3));
    }
  }

  /// Pista: banda de asfalto, linha neon em cima, tracejado correndo.
  void _pista(Canvas c, double w, double h) {
    final topo = g.pistaTopo;
    c.drawRect(Rect.fromLTRB(0, topo, w, h), Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF111A24), Color(0xFF070C13)]).createShader(Rect.fromLTRB(0, topo, w, h)));
    _neon(c, Path()..moveTo(0, topo)..lineTo(w, topo), w: 2.5);
    // Tracejado da faixa da frente.
    final y = h * .945;
    final passo = w * .22, comp = w * .10;
    final ini = (q.dist * w / passo).floor() - 1;
    for (var i = ini; i < ini + (w / passo).ceil() + 2; i++) {
      final x = i * passo - q.dist * w;
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y - 2, comp, 4), const Radius.circular(2)),
          Paint()..color = Colors.white.withValues(alpha: .7));
    }
  }

  /// Postes de luz na beira da pista, na velocidade da pista, atrás do herói.
  void _postes(Canvas c, double w, double h) {
    final passo = w * 1.1;
    final ini = (q.dist * w / passo).floor() - 1;
    for (var i = ini; i < ini + (w / passo).ceil() + 2; i++) {
      final mundo = (i * passo + w * .35) / w;
      if (mundo > q.x0 - .2 && mundo < q.x0 + 1.35) continue; // não atravessa o evento
      final x = mundo * w - q.dist * w;
      final base = g.pistaTopo, topo = h * .30;
      c.drawLine(Offset(x, base), Offset(x, topo), _linha(const Color(0xFF2A3A4C), 4));
      c.drawLine(Offset(x, topo), Offset(x - w * .06, topo + h * .02), _linha(const Color(0xFF2A3A4C), 4));
      final lamp = Offset(x - w * .06, topo + h * .03);
      _luz(c, lamp, w * .16, _branco, .22);
      c.drawCircle(lamp, 3, Paint()..color = _branco);
      // Cone no asfalto.
      final cone = Path()
        ..moveTo(lamp.dx, lamp.dy)
        ..lineTo(lamp.dx - w * .16, base)
        ..lineTo(lamp.dx + w * .10, base)
        ..close();
      c.drawPath(cone, Paint()..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [_branco.withValues(alpha: .10), _branco.withValues(alpha: 0)]).createShader(cone.getBounds()));
    }
  }

  // ── cena 1: placa de km passando ────────────────────────────────────────
  void _placaKm(Canvas c) {
    final x = g.x(q.x0 + .3);
    final base = g.pistaTopo, alt = g.h * .12;
    c.drawLine(Offset(x, base), Offset(x, base - alt), _linha(const Color(0xFF9AA5B1), 3));
    final placa = Rect.fromCenter(center: Offset(x, base - alt - g.h * .035), width: g.w * .14, height: g.h * .07);
    c.drawRRect(RRect.fromRectAndRadius(placa, const Radius.circular(4)), Paint()..color = const Color(0xFF16263A));
    c.drawRRect(RRect.fromRectAndRadius(placa, const Radius.circular(4)), _linha(Colors.white70, 1.5));
    _texto(c, 'km 142', placa.center, placa.height * .42);
  }

  // ── cena 2: pórtico com as placas ───────────────────────────────────────
  void _portico(Canvas c) {
    final esq = g.x(q.x0), dir = g.x(q.x0 + .55);
    final topo = g.heroTopo - g.h * .20, base = g.pistaTopo;
    final trave = Path()
      ..moveTo(esq, base)..lineTo(esq, topo)..lineTo(dir, topo)..lineTo(dir, base);
    _neon(c, trave, w: 3);
    final tre = Path();
    const n = 8;
    for (var i = 0; i < n; i++) {
      tre.moveTo(esq + (dir - esq) * i / n, topo);
      tre.lineTo(esq + (dir - esq) * (i + 1) / n, topo + g.h * .03);
    }
    _neon(c, tre, w: 1.2);
    final raio = g.w * .045;
    final placas = ['4,20 m', '25 t', '5 eixos'];
    for (var i = 0; i < 3; i++) {
      final cx = esq + (dir - esq) * (.25 + .25 * i);
      final cy = topo + g.h * .03 + raio * 1.5;
      _neon(c, Path()..moveTo(cx, topo + g.h * .03)..lineTo(cx, cy - raio), w: 1.2);
      c.drawCircle(Offset(cx, cy), raio, Paint()..color = Colors.white);
      c.drawCircle(Offset(cx, cy), raio, _linha(_vermelho, raio * .18));
      _texto(c, placas[i], Offset(cx, cy), raio * .46, cor: const Color(0xFF0B1119));
    }
  }

  // ── cena 3: poste do radar, câmera virada pro caminhão ──────────────────
  void _radar(Canvas c) {
    final x = g.x(q.x0);
    final base = g.pistaTopo, topo = g.heroTopo - g.h * .12;
    _neon(c, Path()..moveTo(x, base)..lineTo(x, topo)..lineTo(x - g.w * .08, topo), w: 3);
    final caixa = Rect.fromCenter(center: Offset(x - g.w * .08, topo + g.h * .035), width: g.w * .075, height: g.h * .06);
    c.drawRRect(RRect.fromRectAndRadius(caixa, const Radius.circular(4)), Paint()..color = const Color(0xFF101C2A));
    _neon(c, Path()..addRRect(RRect.fromRectAndRadius(caixa, const Radius.circular(4))), w: 2);
    final lente = caixa.centerLeft + Offset(caixa.width * .3, 0);
    c.drawCircle(lente, caixa.height * .22, Paint()..color = const Color(0xFF05080D));
    c.drawCircle(lente, caixa.height * .22, _linha(kNeon, 1.5));
    // Seta no asfalto, no sentido do caminhão, um pouco antes do radar.
    final sx = x - g.w * .30, sy = g.h * .80;
    final comp = g.w * .12, alt = g.h * .035;
    final seta = Path()
      ..moveTo(sx, sy - alt * .4)..lineTo(sx + comp * .6, sy - alt * .4)..lineTo(sx + comp * .6, sy - alt)
      ..lineTo(sx + comp, sy)..lineTo(sx + comp * .6, sy + alt)..lineTo(sx + comp * .6, sy + alt * .4)
      ..lineTo(sx, sy + alt * .4)..close();
    c.drawPath(seta, _glow(kNeon, 6));
    c.drawPath(seta, Paint()..color = kNeon.withValues(alpha: .9));
  }

  // ── cena 4: praça de pedágio com cancela que sobe ───────────────────────
  void _pedagio(Canvas c) {
    final esq = g.x(q.x0), dir = g.x(q.x0 + 1.15);
    final topo = g.heroTopo - g.h * .19, base = g.pistaTopo;
    final cob = Rect.fromLTRB(esq, topo, dir, topo + g.h * .06);
    c.drawRRect(RRect.fromRectAndRadius(cob, const Radius.circular(4)), Paint()..color = const Color(0xFF101C2A));
    _neon(c, Path()..addRRect(RRect.fromRectAndRadius(cob, const Radius.circular(4))), w: 3);
    for (final px in [esq + 6, esq + (dir - esq) * .5, dir - 6]) {
      _neon(c, Path()..moveTo(px, cob.bottom)..lineTo(px, base), w: 3);
    }
    for (var i = 1; i < 8; i++) {
      final x = esq + (dir - esq) * i / 8;
      _luz(c, Offset(x, cob.bottom + 4), g.w * .045, _branco, .22);
      c.drawCircle(Offset(x, cob.bottom + 3), 2.5, Paint()..color = Colors.white);
    }
    // Cabine.
    final cab = Rect.fromLTWH(esq + (dir - esq) * .12, base - g.h * .16, g.w * .11, g.h * .16);
    c.drawRect(cab, Paint()..color = const Color(0xFF101C2A));
    _neon(c, Path()..addRect(cab), w: 2);
    c.drawRect(Rect.fromLTWH(cab.left + cab.width * .2, cab.top + cab.height * .18, cab.width * .6, cab.height * .35),
        Paint()..color = _ambar.withValues(alpha: .85));
    // Cancela: sobe quando o caminhão se aproxima.
    final pivo = Offset(cab.right + 6, base - g.h * .02);
    final sobe = ((g.heroDir + g.w * .30 - pivo.dx) / (g.w * .30)).clamp(0.0, 1.0);
    final ang = -math.pi / 2.2 * Curves.easeOutBack.transform(sobe);
    final comp = g.w * .26;
    final ponta = pivo + Offset(math.cos(ang) * comp, math.sin(ang) * comp);
    c.drawLine(pivo, ponta, _glow(_vermelho, 10));
    c.drawLine(pivo, ponta, _linha(Colors.white, 5));
    for (var i = 0; i < 5; i++) {
      c.drawLine(pivo + (ponta - pivo) * (i / 5 + .05), pivo + (ponta - pivo) * (i / 5 + .13), _linha(_vermelho, 5));
    }
    c.drawCircle(pivo, 5, Paint()..color = kNeon);
    // Semáforo da faixa: vermelho fechado, verde aberto.
    final sem = Offset(pivo.dx, cob.bottom + g.h * .05);
    _luz(c, sem, g.w * .05, sobe > .8 ? kNeon : _vermelho, .8);
    c.drawCircle(sem, 4, Paint()..color = sobe > .8 ? kNeon : _vermelho);
  }

  @override
  bool shouldRepaint(_FundoPainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
// Frente: luzes do herói e do parado, flash, selos.
// ═══════════════════════════════════════════════════════════════════════════
class _FrentePainter extends CustomPainter {
  final _Quadro q;
  final _Geo g;
  _FrentePainter(this.q, this.g) {
    g._distAtual = q.dist;
  }

  @override
  void paint(Canvas c, Size s) {
    if (q.farol) _luzes(c);
    _eventos(c, s);
  }

  /// Faróis do herói (frente = direita): pulsam de leve, iluminam a pista à
  /// frente. Lanternas atrás.
  void _luzes(Canvas c) {
    final farol = Offset(g.heroDir - g.heroLarg * .06, g.heroTopo + g.heroLarg * (567 / 1200) * .78);
    final alto = q.piscaFarol ? 2.4 : 1.0;
    _luz(c, farol, g.w * .10 * alto, _branco, (.35 + .1 * q.seno) * alto);
    final cone = Path()
      ..moveTo(farol.dx, farol.dy - 6)
      ..lineTo(farol.dx + g.w * .28, g.pistaTopo + 2)
      ..lineTo(farol.dx + g.w * .02, g.chao)
      ..close();
    c.drawPath(cone, Paint()..shader = LinearGradient(
        begin: Alignment.centerLeft, end: Alignment.centerRight,
        colors: [_branco.withValues(alpha: .16 * alto), _branco.withValues(alpha: 0)]).createShader(cone.getBounds()));
    // Lanternas do herói (traseira = esquerda).
    final lant = Offset(g.heroEsq + g.heroLarg * .005, g.heroTopo + g.heroLarg * (567 / 1200) * .78);
    _luz(c, lant, g.w * .05, _vermelho, .5 + .3 * q.seno);
  }

  void _eventos(Canvas c, Size s) {
    switch (q.cena) {
      case Cena.abertura:
        break;
      case Cena.rota:
        // Check verde quando o pórtico passa por cima do caminhão.
        _selo(c, 'Passa', kNeon, gatilho: q.avanco - .55 + _Geo.heroDirF, icone: Icons.check_rounded);
      case Cena.radar:
        // História: o app avisa ANTES de o radar aparecer, o velocímetro cai
        // de 98 (vermelho piscando) a 90 (verde), a câmera fotografa em cima
        // da cabine e o chip some quando o poste fica pra trás.
        _flash(c, s);
        _velocimetro(c);
      case Cena.pedagio:
        // O valor aparece antes de a praça entrar na tela: "antes de sair,
        // você sabe quanto vai gastar".
        _selo(c, 'R\$ 28,50', kNeon, gatilho: q.avanco + 1.3);
      case Cena.sos:
        _sos(c);
    }
  }

  /// Flash do radar: um estouro branco na cena inteira quando a câmera cruza
  /// a frente do caminhão, decaindo em 15% de largura percorrida.
  /// O poste está em `x0`: entra pela direita com `avanco` = -1 e sai pela
  /// esquerda em 0; o gatilho cresce com o avanço. A câmera fica 8% à
  /// esquerda do poste e fotografa quando está em cima da cabine
  /// (`avanco` = -.85), com o estouro na lente e um clarão curto na cena.
  void _flash(Canvas c, Size s) {
    final k = (q.avanco + .85) / .15;
    if (k < 0 || k > 1) return;
    final lente = Offset(g.x(q.x0) - g.w * .08, g.heroTopo - g.h * .085);
    c.drawCircle(lente, g.w * .04 * (1 + 2 * k), Paint()..color = Colors.white.withValues(alpha: 1 - k));
    _luz(c, lente, g.w * .35 * (1 + k), Colors.white, .9 * (1 - k));
    c.drawRect(Offset.zero & s, Paint()..color = Colors.white.withValues(alpha: .30 * (1 - k)));
  }

  /// Velocímetro do radar: número caindo até o limite, vermelho piscando
  /// acima dele e verde no limite; ao lado, a placa do radar. Depois da foto,
  /// ganha o check.
  void _velocimetro(Canvas c) {
    final kmh = kmhRadar(q.avanco).round();
    final acima = kmh > 90;
    final pisca = q.estatico || (q.tempo % .5) < .3;
    final cor = acima ? (pisca ? _vermelho : _vermelhoEscuro) : kNeon;
    const g0 = 1.45;
    _selo(c, '$kmh km/h', cor, gatilho: q.avanco + g0, fim: g0, dx: -g.w * .05,
        icone: q.avanco > -.85 ? Icons.check_rounded : null);
    _selo(c, '90', kNeon, gatilho: q.avanco + g0, fim: g0, sub: 'km/h', anel: true, escala: .6, dx: g.w * .16);
  }

  /// Selo acima do herói, entrando com mola quando [gatilho] passa de zero e,
  /// se [fim] for dado, encolhendo até sumir quando o gatilho passa dele.
  void _selo(Canvas c, String texto, Color cor,
      {required double gatilho, double? fim, String? sub, bool anel = false, IconData? icone,
      double dx = 0, double escala = 1}) {
    if (gatilho < 0 && !q.estatico) return; // quadro parado mostra o selo sempre
    var k = q.estatico ? 1.0 : Curves.elasticOut.transform((gatilho / .12).clamp(0.0, 1.0));
    if (fim != null && !q.estatico) k *= 1 - ((gatilho - fim) / .1).clamp(0.0, 1.0);
    if (k <= 0) return;
    final centro = Offset(g.heroEsq + g.heroLarg * .5 + dx, g.heroTopo - g.h * .11);
    c.save();
    c.translate(centro.dx, centro.dy);
    c.scale(k * escala);
    final r = g.w * (anel ? .065 : .085);
    final tcor = cor == _vermelho || cor == _vermelhoEscuro ? Colors.white : const Color(0xFF06140A);
    _luz(c, Offset.zero, r * 1.6, cor, .35 + .15 * q.seno);
    if (anel) {
      c.drawCircle(Offset.zero, r, Paint()..color = Colors.white);
      c.drawCircle(Offset.zero, r, _linha(_vermelho, r * .18));
      _texto(c, texto, Offset(0, -r * .08), r * .7, cor: const Color(0xFF0B1119));
      if (sub != null) _texto(c, sub, Offset(0, r * .5), r * .28, cor: const Color(0xFF0B1119), peso: FontWeight.w600);
    } else {
      final tp = TextPainter(
        text: TextSpan(text: texto, style: TextStyle(color: tcor, fontSize: r * .55, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.ltr,
      )..layout();
      final larg = tp.width + r * .9 + (icone != null ? r * .7 : 0);
      final caixa = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: larg, height: r * 1.1), Radius.circular(r));
      c.drawRRect(caixa, Paint()..color = cor);
      var x = -larg / 2 + r * .45;
      if (icone != null) {
        final ic = TextPainter(
          text: TextSpan(text: String.fromCharCode(icone.codePoint),
              style: TextStyle(fontFamily: icone.fontFamily, package: icone.fontPackage, fontSize: r * .7, color: tcor)),
          textDirection: TextDirection.ltr,
        )..layout();
        ic.paint(c, Offset(x, -ic.height / 2));
        x += r * .7;
      }
      tp.paint(c, Offset(x, -tp.height / 2));
    }
    c.restore();
  }

  /// S.O.S.: pisca-alerta do parado, selo S.O.S. pulsando em cima dele e a
  /// distância caindo no selo do herói até "Chegou".
  void _sos(Canvas c) {
    final esq = g.x(q.x0);
    final larg = g.paradoLarg;
    final alt = larg * (412 / 1180);
    final topo = g.chao - alt;
    // Luzes âmbar do sprite (posições lidas do parado.webp, em frações).
    final acesa = q.estatico || (q.tempo % .8) < .4;
    if (acesa) {
      // Sprite espelhado: u vira 1 - u.
      for (final p in const [(.16, .19), (.24, .19), (.13, .80), (.15, .70), (.45, .69), (.60, .69), (.74, .69), (.86, .69), (.97, .63)]) {
        _luz(c, Offset(esq + larg * (1 - p.$1), topo + alt * p.$2), g.w * .03, _ambar, .8);
      }
      _luz(c, Offset(esq + larg * .7, g.chao), g.w * .22, _ambar, .18);
    }
    // Selo S.O.S. em cima do parado.
    final pulso = q.seno;
    final centro = Offset(esq + larg * .55, topo - g.h * .10);
    final r = g.w * .06 * (1 + .06 * pulso);
    _luz(c, centro, r * 2, _vermelho, .25 + .25 * pulso);
    c.drawCircle(centro, r, Paint()..color = _vermelho);
    c.drawCircle(centro, r, _linha(Colors.white, 2));
    _texto(c, 'SOS', centro, r * .6);
    // Distância até ele, no selo do herói.
    final folga = (q.x0 - q.dist) - _Geo.heroDirSosF - .04;
    final km = (folga / 1.25 * 1.2).clamp(0.0, 1.2);
    final String txt = q.v == 0 ? 'Chegou' : km < .1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
    _selo(c, txt, q.v == 0 ? kNeon : Colors.white, gatilho: 1);
  }

  @override
  bool shouldRepaint(_FrentePainter old) => true;
}
