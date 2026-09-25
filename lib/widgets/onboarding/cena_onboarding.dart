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

/// Radar: velocidade do herói em função do avanço do evento. Chega a 88 e
/// cai pra 80 entre -1.35 e -.95, antes de a câmera (em -.85) fotografar.
double kmhRadar(double avanco) => (88 - 8 * ((avanco + 1.35) / .4).clamp(0.0, 1.0)).roundToDouble();

/// Cena da apresentação: side-scroller visto de lado, UMA só atrás de todas
/// as páginas (o mundo não corta ao trocar de tela). O nosso caminhão
/// (sprite `heroi.webp`, com o alien na janela) fica parado no centro e o
/// mundo passa por ele em três velocidades: morros e cidade ao fundo
/// (devagar), árvores (meio), pista com postes e tracejado (rápido).
/// Cada tela arma o seu evento vindo da direita: pórtico com as placas,
/// radar com flash, praça com cancela subindo, caminhão parado
/// (sprite `parado.webp`) em que o nosso freia atrás. O evento da tela
/// anterior continua até sair pela esquerda; o cenário e o dia fazem lerp.
///
/// Relógio: um [Ticker] integra a distância percorrida (`_dist`, em larguras
/// de tela) com a velocidade da cena. Tudo que passa é função de `_dist`; o
/// que pulsa é função do tempo. "Reduzir animações" = um quadro parado com o
/// evento à vista.
class CenaOnboarding extends StatefulWidget {
  final Cena cena;
  /// Falso nas páginas sem apresentação (cadastro, permissões): a cena
  /// esmaece e o relógio para.
  final bool visivel;
  const CenaOnboarding({super.key, required this.cena, this.visivel = true});

  @override
  State<CenaOnboarding> createState() => _CenaOnboardingState();
}

class _CenaOnboardingState extends State<CenaOnboarding> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration _ultimo = Duration.zero;
  double _dist = 0;        // larguras de tela percorridas
  double _tempo = 0;       // segundos desde que a tela atual armou
  double _tempoTotal = 0;  // segundos desde a abertura (entrada, faróis)
  double _x0 = -10;        // posição (mundo) onde o evento desta tela começa
  double _v = 1;           // velocidade atual, 0..1
  double? _tParou;         // _tempo em que a velocidade chegou a zero
  double _zoom = 1;        // câmera, suavizada a cada tick
  double _sosK = 0;        // 0 = enquadramento normal, 1 = enquadramento do S.O.S.
  bool _estatico = false;
  // Tela anterior: o evento dela continua na tela até sair pela esquerda e o
  // cenário dela vira o novo em 1,2 s.
  Cena? _cenaAnt;
  double _x0Ant = -10;
  _Mundo _mundoAntes = _Mundo.de(Cena.abertura);

  /// Velocidade da pista, em larguras de tela por segundo.
  static const _vel = .55;

  Cena get _cena => widget.cena;

  @override
  void initState() {
    super.initState();
    _mundoAntes = _Mundo.de(_cena);
    _armaEvento();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _estatico = MediaQuery.of(context).disableAnimations;
    for (final a in const ['heroi', 'acena', 'parado']) {
      precacheImage(AssetImage('assets/onboarding/$a.webp'), context);
    }
    if (_estatico) {
      _ticker.stop();
      _dist = 0;
      _x0 = .75; // evento no meio da tela, quadro parado
      _tempo = 10;
      _tempoTotal = 10;
      _cenaAnt = null;
      _sosK = _cena == Cena.sos ? 1 : 0;
    } else if (!_ticker.isActive && widget.visivel) {
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(covariant CenaOnboarding old) {
    super.didUpdateWidget(old);
    if (widget.cena != old.cena) {
      _mundoAntes = _mundo();
      // O evento anterior só continua se JÁ está na tela; se estava rearmado
      // à direita (fora da tela), some, senão entraria junto com o novo.
      if (!_estatico && _x0 - _dist < 1.0) {
        _cenaAnt = old.cena;
        _x0Ant = _x0;
      } else {
        _cenaAnt = null;
      }
      _armaEvento();
      // O novo nasce depois do fim do anterior, sem sobrepor.
      if (_cenaAnt != null) _x0 = math.max(_x0, _x0Ant + _largura(_cenaAnt!) + .4);
      if (_estatico) _x0 = .75;
    }
    if (widget.visivel && !old.visivel && !_estatico && !_ticker.isActive) _ticker.start();
    if (!widget.visivel && old.visivel) _ticker.stop();
  }

  /// Largura do objeto de cada evento, em larguras de tela (a partir de x0).
  static double _largura(Cena c) => switch (c) {
        Cena.abertura => .4,
        Cena.rota => .55,
        Cena.radar => .1,
        Cena.pedagio => 1.15,
        Cena.sos => .4,
        Cena.fechamento => 0,
      };

  void _armaEvento() {
    _tempo = 0;
    _tParou = null;
    _x0 = _dist + 1.5; // entra pela direita ~1 s depois de abrir
  }

  /// Cenário atual: lerp do anterior pro desta tela em 1,2 s.
  _Mundo _mundo() => _Mundo.lerp(_mundoAntes, _Mundo.de(_cena), Curves.easeInOut.transform((_tempo / 1.2).clamp(0.0, 1.0)));

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
      _tempoTotal += dt;
      // O evento repete em loop (como no Radarbot): quando já passou, volta
      // pela direita, renascendo fora da tela (o aviso do radar dispara em
      // -1.35). S.O.S. e fechamento não repetem.
      if (_cena != Cena.sos && _cena != Cena.fechamento && _dist - _x0 > 1.7) _x0 = _dist + 1.5;
      // No fechamento, o caminhão socorrido arranca e vai embora.
      if (_cena == Cena.fechamento && _cenaAnt == Cena.sos) _x0Ant += dt * _vel * 1.1;
      if (_cenaAnt != null && (_dist - _x0Ant > 1.7 || _x0Ant - _dist > 1.2)) _cenaAnt = null;
      // Câmera e enquadramento, suavizados.
      final s = (dt * 3).clamp(0.0, 1.0);
      _zoom += (_zoomAlvo() - _zoom) * s;
      _sosK += ((_cena == Cena.sos ? 1 : 0) - _sosK) * s;
    });
  }

  double _zoomAlvo() {
    if (_cena == Cena.sos && _tParou != null) return 1.14;
    if (_cena == Cena.radar) {
      final k = ((_dist - _x0) + .85) / .15;
      if (k >= 0 && k <= 1) return 1.06;
    }
    return 1;
  }

  /// Abertura: o herói entra pela esquerda (0 → 1 em 1,4 s, easeOut); a
  /// pista só começa a correr quando ele está quase no lugar. Só na primeira
  /// tela, uma vez.
  bool get _entrando => _cena == Cena.abertura && _cenaAnt == null && !_estatico;
  double _entrada() => _entrando ? Curves.easeOutCubic.transform((_tempoTotal / 1.4).clamp(0.0, 1.0)) : 1;

  double _velocidade() {
    switch (_cena) {
      case Cena.abertura:
        return _entrando ? ((_tempoTotal - 1.0) / .6).clamp(0.0, 1.0) : 1;
      case Cena.rota:
        return 1;
      case Cena.radar:
        return .85 + .15 * (kmhRadar(_dist - _x0) - 80) / 8;
      case Cena.pedagio:
        // Folga entre o para-choque e a 1ª cancela (pivô em x0 + .25): freia
        // até um quarto da velocidade, espera a cancela subir, arranca.
        final folga = -(_dist - _x0) - .55;
        if (folga > .45) return 1;
        if (folga > .05) return .25 + .75 * (folga - .05) / .4;
        if (folga > -.05) return .25;
        return (.25 + .75 * (-folga - .05) / .3).clamp(.25, 1.0);
      case Cena.sos:
        final folga = (_x0 - _dist) - _Geo.heroDirSosF - .04; // distância até o parado
        if (folga < .012) return 0;
        return (folga / .5).clamp(0.0, 1.0);
      case Cena.fechamento:
        // Espera o socorrido ir embora (1,6 s), aí arranca.
        if (_cenaAnt == Cena.sos) return ((_tempo - 1.6) / 1.2).clamp(0.0, 1.0);
        return 1;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cena = _cena;
    final mundo = _mundo();
    final q = _Quadro(cena: cena, dist: _dist, x0: _x0, tempo: _tempo, v: _v, estatico: _estatico, mundo: mundo,
        farol: !_entrando || _tempoTotal > .9,
        paradoHa: _tParou == null ? -1 : _tempo - _tParou!);
    final qAnt = _cenaAnt == null
        ? null
        : _Quadro(cena: _cenaAnt!, dist: _dist, x0: _x0Ant, tempo: _tempo + 10, v: _v, estatico: _estatico, mundo: mundo, anterior: true);
    // Alien acena: parado atrás do S.O.S. e no fechamento.
    final acena = (cena == Cena.sos && _v == 0) || cena == Cena.fechamento;
    return AnimatedOpacity(
      opacity: widget.visivel ? 1 : 0,
      duration: const Duration(milliseconds: 350),
      child: ClipRect(
        child: LayoutBuilder(builder: (_, box) {
          final g = _Geo(Size(box.maxWidth, box.maxHeight), sosK: _sosK);
          g.heroDx = -(g.w * _Geo.heroEsqF + g.heroLarg) * (1 - _entrada());
          final bob = _estatico ? 0.0 : math.sin(_tempo * 2 * math.pi * 1.3) * 2 * _v;
          return Transform.scale(
            scale: _estatico ? 1 : _zoom,
            alignment: const Alignment(.55, .75), // entre o herói e o parado
            child: Stack(fit: StackFit.expand, children: [
              CustomPaint(painter: _FundoPainter(q, g, qAnt)),
              if (qAnt?.cena == Cena.sos)
                _Sprite(asset: 'parado', esq: g.x(qAnt!.x0), larg: g.paradoLarg, chao: g.chao, dy: 0, g: g),
              _Sprite(asset: acena ? 'acena' : 'heroi',
                  esq: g.heroEsq, larg: g.heroLarg, chao: g.chao, dy: bob, g: g,
                  rodas: _Roda.heroi, giro: (_dist * g.w + g.heroDx) / (g.heroLarg * _Roda.pneuF)),
              if (cena == Cena.sos)
                _Sprite(asset: 'parado', esq: g.x(q.x0), larg: g.paradoLarg, chao: g.chao, dy: 0, g: g),
              CustomPaint(painter: _FrentePainter(q, g, qAnt)),
            ]),
          );
        }),
      ),
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
  /// 0 = enquadramento normal; 1 = S.O.S. (herói encostado na esquerda pra
  /// sobrar tela pro parado). Faz lerp na troca de tela.
  final double sosK;
  _Geo(this.s, {this.sosK = 0});
  double get w => s.width;
  double get h => s.height;
  double get horizonte => h * .60;
  double get pistaTopo => h * .74;
  double get chao => h * .87;         // linha das rodas
  static const heroEsqF = .10, heroEsqSosF = -.08, heroLargF = .70;
  static const heroDirF = heroEsqF + heroLargF;
  static const heroDirSosF = heroEsqSosF + heroLargF;
  /// Deslocamento horizontal do herói (entrada pela esquerda na abertura).
  double heroDx = 0;
  double get heroEsq => w * (heroEsqF + (heroEsqSosF - heroEsqF) * sosK) + heroDx;
  double get heroLarg => w * heroLargF;
  double get heroDir => heroEsq + heroLarg;
  double get heroTopo => chao - heroLarg * (567 / 1200);
  double get paradoLarg => w * .36; // menor: parado mais à frente, cabine com capô à vista
  /// Posição de mundo (em larguras) → x na tela, na velocidade da pista.
  double x(double mundo) => w * (mundo - _distAtual);
  double _distAtual = 0;
}

/// Cenário de cada tela (camadas de fundo e hora do dia). Os eventos não
/// mudam; o mundo em volta muda, e faz lerp na troca de tela.
class _Mundo {
  final double morros;    // altura dos morros, 0 = horizonte chapado
  final double predios;   // skyline de cidade no horizonte, 0..1 (alpha)
  final double luzes;     // densidade das luzes de cidade, 0..1
  final double arvores;   // densidade das árvores, 0..1
  final double cactos;    // densidade dos mandacarus, 0..1
  final double postes;    // presença dos postes, 0..1 (alpha)
  final double passo;     // distância entre postes, em larguras
  final double guardRail; // 0..1 (alpha)
  final double estrelas;  // quantas
  final double dia;       // 0 = noite, 1 = dia claro
  const _Mundo({this.morros = 1, this.predios = 0, this.luzes = .45, this.arvores = .3, this.cactos = 0,
      this.postes = 1, this.passo = 1.1, this.guardRail = 0, this.estrelas = 40, this.dia = 0});

  static _Mundo de(Cena c) => switch (c) {
        Cena.abertura => const _Mundo(morros: .4, predios: 1, luzes: .8, arvores: .15, passo: .8),
        Cena.rota => const _Mundo(morros: 1.8, luzes: .1, arvores: .7, passo: 1.6, dia: 1),
        Cena.radar => const _Mundo(morros: 0, luzes: .05, arvores: .08, passo: 1.0, guardRail: 1),
        Cena.pedagio => const _Mundo(morros: .5, predios: 1, luzes: .9, arvores: .2, passo: .6, dia: .45),
        Cena.sos => const _Mundo(morros: .3, luzes: 0, arvores: 0, postes: 0, passo: 1.0, cactos: 1, estrelas: 90),
        Cena.fechamento => const _Mundo(morros: 1.2, luzes: 0, arvores: .4, postes: 0, passo: 1.0, estrelas: 20, dia: .55),
      };

  static double _l(double a, double b, double t) => a + (b - a) * t;
  static _Mundo lerp(_Mundo a, _Mundo b, double t) => _Mundo(
        morros: _l(a.morros, b.morros, t), predios: _l(a.predios, b.predios, t), luzes: _l(a.luzes, b.luzes, t),
        arvores: _l(a.arvores, b.arvores, t), cactos: _l(a.cactos, b.cactos, t), postes: _l(a.postes, b.postes, t),
        passo: _l(a.passo, b.passo, t), guardRail: _l(a.guardRail, b.guardRail, t), estrelas: _l(a.estrelas, b.estrelas, t),
        dia: _l(a.dia, b.dia, t),
      );

  /// Cor entre a da noite e a do dia.
  Color cor(Color noite, Color dia_) => Color.lerp(noite, dia_, dia)!;

  /// Cor em três paradas: noite (0), crepúsculo (.5), dia (1). O
  /// entardecer e o amanhecer moram no meio.
  Color cor3(Color noite, Color crepusculo, Color dia_) =>
      dia < .5 ? Color.lerp(noite, crepusculo, dia / .5)! : Color.lerp(crepusculo, dia_, (dia - .5) / .5)!;

  /// 1 no crepúsculo, 0 na noite fechada e no dia claro.
  double get crepusculo => (1 - (dia - .5).abs() * 2).clamp(0.0, 1.0);
}

/// Estado de um quadro: o que o painter precisa pra desenhar.
class _Quadro {
  final Cena cena;
  final double dist, x0, tempo, v;
  final bool estatico;
  final _Mundo mundo;
  /// Faróis e lanternas acesos (na abertura acendem quando o herói chega).
  final bool farol;
  /// Segundos desde que o herói parou (S.O.S.); -1 se está andando.
  final double paradoHa;
  /// Evento da tela anterior, ainda saindo: só o objeto, sem selo nem reação.
  final bool anterior;
  _Quadro({required this.cena, required this.dist, required this.x0, required this.tempo, required this.v, required this.estatico,
      required this.mundo, this.farol = true, this.paradoHa = -1, this.anterior = false});
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
    ..shader = RadialGradient(colors: [cor.withValues(alpha: k.clamp(0.0, 1.0)), cor.withValues(alpha: 0)])
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
  final _Quadro? qAnt;
  _FundoPainter(this.q, this.g, this.qAnt) {
    g._distAtual = q.dist;
  }

  _Mundo get m => q.mundo;

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    // Céu: topo e horizonte em três paradas (noite, crepúsculo, dia); no
    // crepúsculo o horizonte fica laranja e o topo, roxo.
    final ceu = Rect.fromLTWH(0, 0, w, g.horizonte + 2);
    c.drawRect(Offset.zero & s, Paint()..color = m.cor3(kFundo, const Color(0xFF2A2238), const Color(0xFF6FA283)));
    c.drawRect(ceu, Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        stops: const [0, .55, 1],
        colors: [
          m.cor3(kFundoEscuro, const Color(0xFF1B1F4E), const Color(0xFF4F8FCB)),
          m.cor3(const Color(0xFF0A1220), const Color(0xFF6E3A6B), const Color(0xFF8DBDE6)),
          m.cor3(kFundo, const Color(0xFFE8873F), const Color(0xFFBFDCEF)),
        ]).createShader(ceu));
    _estrelas(c, w, h);
    _astro(c, w, h);
    _morrosECidade(c, w, h);
    _arvores(c, w, h);
    _pista(c, w, h);
    if (qAnt != null) _evento(c, qAnt!);
    _evento(c, q);
    _postes(c, w, h);
  }

  /// Objeto do evento de uma tela (o atual ou o anterior ainda saindo).
  void _evento(Canvas c, _Quadro e) {
    switch (e.cena) {
      case Cena.abertura:
        _placaKm(c, e);
      case Cena.rota:
        _portico(c, e);
      case Cena.radar:
        _radar(c, e);
      case Cena.pedagio:
        _pedagio(c, e);
      case Cena.sos:
      case Cena.fechamento:
        break;
    }
  }

  void _estrelas(Canvas c, double w, double h) {
    final vis = 1 - m.dia;
    if (vis <= 0) return;
    final n = m.estrelas.round();
    for (var i = 0; i < n; i++) {
      final x = _hash(i) * w, y = _hash(i + 100) * g.horizonte * .85;
      final cint = (.25 + .45 * (.5 + .5 * math.sin(q.tempo * 1.5 + i))) * vis;
      c.drawCircle(Offset(x, y), i % 6 == 0 ? 1.5 : 1, Paint()..color = Colors.white.withValues(alpha: cint));
    }
  }

  /// Lua à noite, sol de dia (mesmo lugar; a sombra da lua some com o dia).
  void _astro(Canvas c, double w, double h) {
    // No crepúsculo o sol desce até perto do horizonte e fica laranja.
    final baixo = m.crepusculo;
    final centro = Offset(w * .82, h * .17 + (g.horizonte - h * .06 - h * .17) * baixo);
    final r = w * .055 * (1 + .3 * m.dia + .5 * baixo);
    final cor = m.cor3(const Color(0xFFE8FFE0), const Color(0xFFFF9A3C), const Color(0xFFFFD34D));
    final halo = m.cor3(_branco, const Color(0xFFFF7A2F), const Color(0xFFFFB347));
    c.drawCircle(centro, r * 2.2, Paint()..shader = RadialGradient(
        colors: [halo.withValues(alpha: .25 + .35 * m.dia.clamp(0, .5) * 2), halo.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: centro, radius: r * 2.2)));
    c.drawCircle(centro, r, Paint()..color = cor);
    // Sombra da lua: some conforme amanhece.
    final sombra = (1 - m.dia * 2.2).clamp(0.0, 1.0);
    if (sombra > 0) {
      c.drawCircle(centro + Offset(r * .35, -r * .2), r * .92, Paint()..color = kFundoEscuro.withValues(alpha: sombra));
    }
  }

  /// Camada longe (12% da pista): silhueta de morros, prédios e luzes de
  /// cidade, na dose que o cenário da tela pede.
  void _morrosECidade(Canvas c, double w, double h) {
    const k = .12;
    final base = g.horizonte;
    if (m.predios > 0) _predios(c, w, h, k);
    final alt = h * .10 * m.morros;
    if (alt <= 0.5) {
      c.drawLine(Offset(0, base), Offset(w, base), _linha(kNeon.withValues(alpha: .15), 1));
      return;
    }
    // Serra ao longe (8% da pista): mais alta, enevoada, quase da cor do céu.
    final longe = Path()..moveTo(0, base + 2);
    for (var i = 0; i <= 48; i++) {
      final x = w * i / 48;
      final u = (x / w + q.dist * .08) * 2 * math.pi + 2.0;
      final y = base - alt * (1.1 + .5 * math.sin(u * .7) + .3 * math.sin(u * 1.9 + .6) + .12 * math.sin(u * 4.3));
      longe.lineTo(x, y);
    }
    longe..lineTo(w, base + 2)..close();
    c.drawPath(longe, Paint()..color = m.cor3(const Color(0xFF0A1420), const Color(0xFF5A3F6E), const Color(0xFF8FB6C9)));
    // Serra da frente: com volume (degradê do cume pro sopé) e um fio neon.
    final p = Path()..moveTo(0, base + 2);
    for (var i = 0; i <= 48; i++) {
      final x = w * i / 48;
      final u = (x / w + q.dist * k) * 2 * math.pi;
      final y = base - alt * (.45 + .3 * math.sin(u * .9) + .2 * math.sin(u * 2.3 + 1.2) + .1 * math.sin(u * 5.1));
      p.lineTo(x, y);
    }
    p..lineTo(w, base + 2)..close();
    final caixa = Rect.fromLTRB(0, base - alt * 1.05, w, base);
    c.drawPath(p, Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [
          m.cor3(const Color(0xFF0E1C2C), const Color(0xFF3B2A4A), const Color(0xFF5E9B78)),
          m.cor3(const Color(0xFF08111B), const Color(0xFF221A30), const Color(0xFF35634C)),
        ]).createShader(caixa));
    c.drawPath(p, _linha(kNeon.withValues(alpha: .15 + .1 * m.dia), 1));
    // Luzes: uma a cada 3% de largura no mundo, com hash decidindo se existe.
    final vis = 1 - m.dia * .85;
    final passo = w * .03;
    final ini = (q.dist * k * w / passo).floor();
    for (var i = ini; i < ini + (w / passo).ceil() + 1; i++) {
      final hx = _hash(i);
      if (hx > m.luzes) continue;
      final x = i * passo - q.dist * k * w;
      final u = (x / w + q.dist * k) * 2 * math.pi;
      final topo = base - alt * (.45 + .3 * math.sin(u * .9) + .2 * math.sin(u * 2.3 + 1.2) + .1 * math.sin(u * 5.1));
      final y = base - (base - topo) * (.15 + .7 * _hash(i + 7));
      final cor = i % 5 == 0 ? _ambar : Colors.white;
      final cint = (.5 + .5 * (.5 + .5 * math.sin(q.tempo * 2 + i))) * vis;
      c.drawCircle(Offset(x, y), 1.2, Paint()..color = cor.withValues(alpha: cint));
    }
  }

  /// Skyline atrás dos morros (mesma velocidade): prédios de alturas
  /// variadas com janelas acesas.
  void _predios(Canvas c, double w, double h, double k) {
    final base = g.horizonte;
    final passo = w * .055;
    final vis = m.predios;
    final janelas = vis * (1 - m.dia * .7);
    final ini = (q.dist * k * w / passo).floor() - 1;
    for (var i = ini; i < ini + (w / passo).ceil() + 2; i++) {
      if (_hash(i + 900) > .8) continue;
      final x = i * passo - q.dist * k * w;
      final larg = passo * (.6 + .5 * _hash(i + 910));
      final alt = h * (.05 + .13 * _hash(i + 920)) * vis;
      final r = Rect.fromLTWH(x, base - alt, larg, alt);
      c.drawRect(r, Paint()..color = m.cor(const Color(0xFF0B1520), const Color(0xFF5B7891)));
      c.drawRect(r, _linha(kNeon.withValues(alpha: .18 * vis), 1));
      final cols = (larg / 6).floor(), rows = (alt / 9).floor();
      for (var cx = 0; cx < cols; cx++) {
        for (var ry = 0; ry < rows; ry++) {
          if (_hash(i * 131 + cx * 17 + ry) > .35) continue;
          final acesa = .4 + .6 * (.5 + .5 * math.sin(q.tempo * .8 + cx + ry + i));
          c.drawRect(Rect.fromLTWH(x + 2 + cx * 6, base - alt + 3 + ry * 9, 2.5, 4),
              Paint()..color = (ry % 4 == 0 ? _ambar : Colors.white).withValues(alpha: acesa * .8 * janelas));
        }
      }
    }
  }

  /// Camada do meio (45%): árvores em silhueta com um fio de neon e/ou
  /// mandacarus no sertão, cada um na sua densidade.
  void _arvores(Canvas c, double w, double h) {
    const k = .45;
    if (m.cactos > 0) _cactos(c, w, h, k);
    if (m.arvores <= 0) return;
    final passo = w * .19;
    final ini = (q.dist * k * w / passo).floor() - 1;
    final cheio = m.cor(const Color(0xFF0A1622), const Color(0xFF1E6B4A));
    for (var i = ini; i < ini + (w / passo).ceil() + 2; i++) {
      if (_hash(i + 300) > m.arvores) continue;
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
      c.drawPath(copa, Paint()..color = cheio);
      c.drawPath(copa, _linha(kNeon.withValues(alpha: .35 * (1 - m.dia * .5)), 1));
      c.drawLine(Offset(x, base - alt * .05), Offset(x, base), _linha(cheio, 3));
    }
  }

  /// Mandacaru: tronco com dois braços, silhueta e fio neon.
  void _cactos(Canvas c, double w, double h, double k) {
    final passo = w * .30;
    final ini = (q.dist * k * w / passo).floor() - 1;
    final cheio = m.cor(const Color(0xFF0A1622), const Color(0xFF1E6B4A));
    for (var i = ini; i < ini + (w / passo).ceil() + 2; i++) {
      if (_hash(i + 700) > .6 * m.cactos) continue;
      final x = i * passo + (_hash(i + 710) - .5) * passo * .5 - q.dist * k * w;
      final alt = h * (.06 + .06 * _hash(i + 720));
      final base = g.pistaTopo - h * .01;
      final e = alt * .12;
      final p = Path()
        ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - e, base - alt, e * 2, alt), Radius.circular(e)))
        ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - e * 4, base - alt * .62, e * 1.6, alt * .38), Radius.circular(e)))
        ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - e * 4, base - alt * .62, e * 4, e * 1.6), Radius.circular(e)))
        ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + e * 2.4, base - alt * .75, e * 1.6, alt * .5), Radius.circular(e)))
        ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, base - alt * .42, e * 4, e * 1.6), Radius.circular(e)));
      c.drawPath(p, Paint()..color = cheio);
      c.drawPath(p, _linha(kNeon.withValues(alpha: .35), 1));
    }
  }

  /// Pista: banda de asfalto, linha neon em cima, tracejado correndo.
  void _pista(Canvas c, double w, double h) {
    final topo = g.pistaTopo;
    c.drawRect(Rect.fromLTRB(0, topo, w, h), Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [m.cor(const Color(0xFF111A24), const Color(0xFF4A5560)), m.cor(const Color(0xFF070C13), const Color(0xFF2E3740))])
        .createShader(Rect.fromLTRB(0, topo, w, h)));
    _neon(c, Path()..moveTo(0, topo)..lineTo(w, topo), w: 2.5);
    if (m.guardRail > 0) {
      // Guard-rail na beira: lâmina dupla com mourões passando.
      final y = topo - h * .022;
      final a = m.guardRail;
      c.drawLine(Offset(0, y), Offset(w, y), _linha(const Color(0xFF8A96A3).withValues(alpha: a), 3));
      c.drawLine(Offset(0, y + 5), Offset(w, y + 5), _linha(const Color(0xFF5A6673).withValues(alpha: a), 2));
      final passo = w * .09;
      final ini = (q.dist * w / passo).floor() - 1;
      for (var i = ini; i < ini + (w / passo).ceil() + 2; i++) {
        final x = i * passo - q.dist * w;
        c.drawLine(Offset(x, y + 5), Offset(x, topo), _linha(const Color(0xFF5A6673).withValues(alpha: a), 3));
      }
    }
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
    if (m.postes <= .02) return;
    final a = m.postes;
    final lampada = a * (1 - m.dia * .9);
    final passo = w * m.passo.clamp(.4, 3.0);
    final ini = (q.dist * w / passo).floor() - 1;
    final poste = const Color(0xFF2A3A4C).withValues(alpha: a);
    for (var i = ini; i < ini + (w / passo).ceil() + 2; i++) {
      final mundo = (i * passo + w * .35) / w;
      if (mundo > q.x0 - .7 && mundo < q.x0 + 1.35) continue; // não atravessa o evento
      if (qAnt != null && mundo > qAnt!.x0 - .7 && mundo < qAnt!.x0 + 1.35) continue;
      final x = mundo * w - q.dist * w;
      final base = g.pistaTopo, topo = h * .30;
      c.drawLine(Offset(x, base), Offset(x, topo), _linha(poste, 4));
      c.drawLine(Offset(x, topo), Offset(x - w * .06, topo + h * .02), _linha(poste, 4));
      final lamp = Offset(x - w * .06, topo + h * .03);
      _luz(c, lamp, w * .16, _branco, .22 * lampada);
      c.drawCircle(lamp, 3, Paint()..color = _branco.withValues(alpha: a));
      // Cone no asfalto.
      final cone = Path()
        ..moveTo(lamp.dx, lamp.dy)
        ..lineTo(lamp.dx - w * .16, base)
        ..lineTo(lamp.dx + w * .10, base)
        ..close();
      c.drawPath(cone, Paint()..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [_branco.withValues(alpha: .10 * lampada), _branco.withValues(alpha: 0)]).createShader(cone.getBounds()));
    }
  }

  // ── cena 1: placa de km passando ────────────────────────────────────────
  void _placaKm(Canvas c, _Quadro e) {
    final x = g.x(e.x0 + .3);
    final base = g.pistaTopo, alt = g.h * .12;
    c.drawLine(Offset(x, base), Offset(x, base - alt), _linha(const Color(0xFF9AA5B1), 3));
    final placa = Rect.fromCenter(center: Offset(x, base - alt - g.h * .035), width: g.w * .14, height: g.h * .07);
    c.drawRRect(RRect.fromRectAndRadius(placa, const Radius.circular(4)), Paint()..color = const Color(0xFF16263A));
    c.drawRRect(RRect.fromRectAndRadius(placa, const Radius.circular(4)), _linha(Colors.white70, 1.5));
    _texto(c, 'km 142', placa.center, placa.height * .42);
  }

  // ── cena 2: pórtico com as placas ───────────────────────────────────────
  void _portico(Canvas c, _Quadro e) {
    final esq = g.x(e.x0), dir = g.x(e.x0 + .55);
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
  void _radar(Canvas c, _Quadro e) {
    final x = g.x(e.x0);
    final base = g.pistaTopo, topo = g.heroTopo - g.h * .12;
    _neon(c, Path()..moveTo(x, base)..lineTo(x, topo)..lineTo(x - g.w * .08, topo), w: 3);
    final caixa = Rect.fromCenter(center: Offset(x - g.w * .08, topo + g.h * .035), width: g.w * .075, height: g.h * .06);
    c.drawRRect(RRect.fromRectAndRadius(caixa, const Radius.circular(4)), Paint()..color = const Color(0xFF101C2A));
    _neon(c, Path()..addRRect(RRect.fromRectAndRadius(caixa, const Radius.circular(4))), w: 2);
    final lente = caixa.centerLeft + Offset(caixa.width * .3, 0);
    c.drawCircle(lente, caixa.height * .22, Paint()..color = const Color(0xFF05080D));
    c.drawCircle(lente, caixa.height * .22, _linha(kNeon, 1.5));
    _coruja(c, Offset(x, topo), e);
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

  /// Coruja pousada no topo do poste do radar (pedido do Beto, 25/09):
  /// corpo em silhueta com fio neon, olhos grandes que piscam de vez em
  /// quando e viram pro caminhão quando ele chega perto.
  void _coruja(Canvas c, Offset poste, _Quadro e) {
    final r = g.w * .022; // raio do corpo
    final centro = poste + Offset(0, -r * 1.3);
    final corpo = Path()..addOval(Rect.fromCenter(center: centro, width: r * 2, height: r * 2.6));
    c.drawPath(corpo, Paint()..color = const Color(0xFF0A1622));
    _neon(c, corpo, w: 1.5);
    // Orelhas.
    final orelhas = Path()
      ..moveTo(centro.dx - r * .8, centro.dy - r * .9)..lineTo(centro.dx - r * .6, centro.dy - r * 1.7)..lineTo(centro.dx - r * .2, centro.dy - r * 1.15)
      ..moveTo(centro.dx + r * .8, centro.dy - r * .9)..lineTo(centro.dx + r * .6, centro.dy - r * 1.7)..lineTo(centro.dx + r * .2, centro.dy - r * 1.15);
    c.drawPath(orelhas, Paint()..color = const Color(0xFF0A1622));
    _neon(c, orelhas, w: 1.5);
    // Olhos: piscam a cada ~3 s; a pupila segue o caminhão (que está à esquerda).
    final pisca = !q.estatico && (q.tempo % 3.1) < .12;
    final olhoY = centro.dy - r * .55;
    for (final dx in [-r * .42, r * .42]) {
      final o = Offset(centro.dx + dx, olhoY);
      if (pisca) {
        c.drawLine(o - Offset(r * .3, 0), o + Offset(r * .3, 0), _linha(kNeon, 2));
        continue;
      }
      _luz(c, o, r * .7, kNeon, .35);
      c.drawCircle(o, r * .34, Paint()..color = const Color(0xFFF2FFEA));
      final perto = (g.x(e.x0) - g.heroDir) < g.w * .25;
      c.drawCircle(o + Offset(perto ? -r * .1 : 0, r * .02), r * .16, Paint()..color = const Color(0xFF05080D));
    }
    // Bico.
    final bico = Path()
      ..moveTo(centro.dx - r * .12, centro.dy - r * .25)..lineTo(centro.dx + r * .12, centro.dy - r * .25)..lineTo(centro.dx, centro.dy)..close();
    c.drawPath(bico, Paint()..color = _ambar);
  }

  // ── cena 4: praça de pedágio, em sequência ──────────────────────────────
  /// Placa "PEDÁGIO 500 m" antes, luzes da cobertura acendendo uma a uma
  /// conforme a praça entra, duas cabines com cancela que sobe quando o
  /// caminhão chega.
  void _pedagio(Canvas c, _Quadro e) {
    final esq = g.x(e.x0), dir = g.x(e.x0 + 1.15);
    final topo = g.heroTopo - g.h * .19, base = g.pistaTopo;
    // Placa antes da praça.
    final px = g.x(e.x0 - .45);
    c.drawLine(Offset(px, base), Offset(px, base - g.h * .12), _linha(const Color(0xFF9AA5B1), 3));
    final placa = Rect.fromCenter(center: Offset(px, base - g.h * .12 - g.h * .04), width: g.w * .17, height: g.h * .075);
    c.drawRRect(RRect.fromRectAndRadius(placa, const Radius.circular(4)), Paint()..color = const Color(0xFF1B5E20));
    c.drawRRect(RRect.fromRectAndRadius(placa, const Radius.circular(4)), _linha(Colors.white70, 1.5));
    _texto(c, 'PEDÁGIO', placa.center - Offset(0, placa.height * .18), placa.height * .32);
    _texto(c, '500 m', placa.center + Offset(0, placa.height * .22), placa.height * .28, peso: FontWeight.w600);
    // Cobertura.
    final cob = Rect.fromLTRB(esq, topo, dir, topo + g.h * .06);
    c.drawRRect(RRect.fromRectAndRadius(cob, const Radius.circular(4)), Paint()..color = const Color(0xFF101C2A));
    _neon(c, Path()..addRRect(RRect.fromRectAndRadius(cob, const Radius.circular(4))), w: 3);
    for (final x in [esq + 6, esq + (dir - esq) * .5, dir - 6]) {
      _neon(c, Path()..moveTo(x, cob.bottom)..lineTo(x, base), w: 3);
    }
    // Luzes: acendem da direita pra esquerda conforme a praça entra na tela.
    for (var i = 1; i < 8; i++) {
      final x = esq + (dir - esq) * i / 8;
      final acesa = e.estatico || (e.avanco + 1.15) > (8 - i) * .06;
      if (!acesa) {
        c.drawCircle(Offset(x, cob.bottom + 3), 2.5, Paint()..color = const Color(0xFF3A4A5C));
        continue;
      }
      _luz(c, Offset(x, cob.bottom + 4), g.w * .045, _branco, .22);
      c.drawCircle(Offset(x, cob.bottom + 3), 2.5, Paint()..color = Colors.white);
    }
    // Duas cabines, cada uma com a sua cancela.
    for (final f in [.12, .52]) {
      final cab = Rect.fromLTWH(esq + (dir - esq) * f, base - g.h * .16, g.w * .11, g.h * .16);
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
  final _Quadro? qAnt;
  _FrentePainter(this.q, this.g, this.qAnt) {
    g._distAtual = q.dist;
  }

  @override
  void paint(Canvas c, Size s) {
    if (q.farol) _luzes(c);
    // O socorrido indo embora no fechamento ainda pisca.
    if (qAnt?.cena == Cena.sos) _piscaAlerta(c, qAnt!);
    _eventos(c, s);
  }

  /// Faróis do herói (frente = direita): pulsam de leve, iluminam a pista à
  /// frente. Lanternas atrás. De dia, o cone quase some.
  void _luzes(Canvas c) {
    final farol = Offset(g.heroDir - g.heroLarg * .06, g.heroTopo + g.heroLarg * (567 / 1200) * .78);
    final alto = q.piscaFarol ? 2.4 : 1.0;
    final noite = 1 - q.mundo.dia * .8;
    _luz(c, farol, g.w * .10 * alto, _branco, (.35 + .1 * q.seno) * alto * (1 - q.mundo.dia * .5));
    final cone = Path()
      ..moveTo(farol.dx, farol.dy - 6)
      ..lineTo(farol.dx + g.w * .28, g.pistaTopo + 2)
      ..lineTo(farol.dx + g.w * .02, g.chao)
      ..close();
    c.drawPath(cone, Paint()..shader = LinearGradient(
        begin: Alignment.centerLeft, end: Alignment.centerRight,
        colors: [_branco.withValues(alpha: .16 * alto * noite), _branco.withValues(alpha: 0)]).createShader(cone.getBounds()));
    // Lanternas do herói (traseira = esquerda).
    final lant = Offset(g.heroEsq + g.heroLarg * .005, g.heroTopo + g.heroLarg * (567 / 1200) * .78);
    _luz(c, lant, g.w * .05, _vermelho, .5 + .3 * q.seno);
  }

  void _eventos(Canvas c, Size s) {
    switch (q.cena) {
      case Cena.abertura:
      case Cena.fechamento:
        break;
      case Cena.rota:
        // Check verde quando o pórtico passa por cima do caminhão.
        _selo(c, 'Passa', kNeon, gatilho: q.avanco - .55 + _Geo.heroDirF, icone: Icons.check_rounded);
      case Cena.radar:
        // História: o app avisa ANTES de o radar aparecer, o velocímetro cai
        // de 88 (vermelho piscando) a 80 (verde), a câmera fotografa em cima
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
    final acima = kmh > 80;
    final pisca = q.estatico || (q.tempo % .5) < .3;
    final cor = acima ? (pisca ? _vermelho : _vermelhoEscuro) : kNeon;
    const g0 = 1.45;
    _selo(c, '$kmh km/h', cor, gatilho: q.avanco + g0, fim: g0, dx: -g.w * .05,
        icone: q.avanco > -.85 ? Icons.check_rounded : null);
    _selo(c, '80', kNeon, gatilho: q.avanco + g0, fim: g0, sub: 'km/h', anel: true, escala: .6, dx: g.w * .16);
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

  /// Luzes âmbar do parado (posições lidas do parado.webp, em frações),
  /// piscando.
  void _piscaAlerta(Canvas c, _Quadro e) {
    final esq = g.x(e.x0);
    final larg = g.paradoLarg;
    final alt = larg * (412 / 1180);
    final topo = g.chao - alt;
    final acesa = e.estatico || (q.tempo % .8) < .4;
    if (!acesa) return;
    // Sprite espelhado: u vira 1 - u.
    for (final p in const [(.16, .19), (.24, .19), (.13, .80), (.15, .70), (.45, .69), (.60, .69), (.74, .69), (.86, .69), (.97, .63)]) {
      _luz(c, Offset(esq + larg * (1 - p.$1), topo + alt * p.$2), g.w * .03, _ambar, .8);
    }
    _luz(c, Offset(esq + larg * .7, g.chao), g.w * .22, _ambar, .18);
  }

  /// S.O.S.: pisca-alerta do parado, selo S.O.S. pulsando em cima dele e a
  /// distância caindo no selo do herói até "Chegou".
  void _sos(Canvas c) {
    _piscaAlerta(c, q);
    final esq = g.x(q.x0);
    final larg = g.paradoLarg;
    final topo = g.chao - larg * (412 / 1180);
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
