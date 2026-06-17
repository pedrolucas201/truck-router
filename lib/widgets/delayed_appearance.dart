import 'dart:async';
import 'package:flutter/widgets.dart';

/// Só renderiza [child] depois de [delay] montado. Antes disso ocupa zero espaço.
/// Usado pra evitar o "flash" do loader em operações que terminam rápido.
class DelayedAppearance extends StatefulWidget {
  final Duration delay;
  final Widget child;

  const DelayedAppearance({
    super.key,
    required this.delay,
    required this.child,
  });

  @override
  State<DelayedAppearance> createState() => _DelayedAppearanceState();
}

class _DelayedAppearanceState extends State<DelayedAppearance> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _visible ? widget.child : const SizedBox.shrink();
}
