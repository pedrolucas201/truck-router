import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Loader "Calculando rota…": caminhão atravessa trilha de pontinhos (loop).
///
/// [bare] = false (padrão): pílula com fundo próprio — uso como overlay.
/// [bare] = true: só a track + texto, cores brancas — uso dentro de FilledButton.
class RouteLoadingIndicator extends StatefulWidget {
  final String truckAsset;
  final bool bare;

  const RouteLoadingIndicator({
    super.key,
    required this.truckAsset,
    this.bare = false,
  });

  @override
  State<RouteLoadingIndicator> createState() => _RouteLoadingIndicatorState();
}

class _RouteLoadingIndicatorState extends State<RouteLoadingIndicator>
    with SingleTickerProviderStateMixin {
  static const double _trackW = 130;
  static const double _trackH = 24;
  static const double _dotR = 7;
  static const double _truckSize = 22;
  static const double _start = -26;
  static const double _end = 156;
  static const double _front = 17;
  static const double _pop = 10;
  static const List<double> _dotsX = [14, 31, 48, 65, 82, 99, 116];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _truck(double left) => Positioned(
        left: left,
        top: (_trackH - _truckSize) / 2,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(-1, 1, 1),
          child: SvgPicture.asset(
            widget.truckAsset,
            width: _truckSize,
            height: _truckSize,
          ),
        ),
      );

  Widget _dot(double x, double opacity, double dy, double scale, Color color) =>
      Positioned(
        left: x - _dotR / 2,
        top: (_trackH - _dotR) / 2,
        child: Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: _dotR,
                height: _dotR,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      );

  Widget _animatedTrack(double v, Color dotColor) {
    final left = _start + v * (_end - _start);
    final front = left + _front;
    final children = <Widget>[
      for (final x in _dotsX)
        () {
          final p = ((front - x) / _pop).clamp(0.0, 1.0);
          return _dot(x, 1 - p, -7 * p, 1 - 0.8 * p, dotColor);
        }(),
      _truck(left),
    ];
    return ClipRect(
      child: SizedBox(
        width: _trackW,
        height: _trackH,
        child: Stack(children: children),
      ),
    );
  }

  Widget _staticTrack(Color dotColor) {
    final children = <Widget>[
      for (final x in _dotsX) _dot(x, 1, 0, 1, dotColor),
      _truck((_trackW - _truckSize) / 2),
    ];
    return ClipRect(
      child: SizedBox(
        width: _trackW,
        height: _trackH,
        child: Stack(children: children),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final Color dotColor;
    final Color textColor;
    if (widget.bare) {
      dotColor = Colors.white70;
      textColor = Colors.white;
    } else {
      dotColor = dark ? const Color(0xFF5A5F66) : const Color(0xFFCFD4D8);
      textColor = dark ? Colors.white : const Color(0xFF1C1C1E);
    }

    final track = reduce ? _staticTrack(dotColor) : AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => _animatedTrack(_controller.value, dotColor),
    );

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        track,
        const SizedBox(width: 12),
        Text(
          'Calculando rota…',
          style: TextStyle(fontSize: 13, color: textColor),
        ),
      ],
    );

    if (widget.bare) return content;

    final pillColor = dark ? const Color(0xFF2A2A2E) : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: pillColor,
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: content,
    );
  }
}
