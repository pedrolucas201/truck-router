import 'dart:async';

import 'package:flutter/material.dart';

/// Abertura dentro do app: a mesma arte da abertura nativa, segurada por
/// [kSplashDuration] antes de entrar no mapa. A nativa some no primeiro quadro
/// do Flutter (fração de segundo); o Gilberto pediu pra dar tempo de ver.
const kSplashDuration = Duration(seconds: 3);

class SplashScreen extends StatefulWidget {
  final Widget next;
  const SplashScreen({super.key, required this.next});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(kSplashDuration, _go);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _go() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, a, _) => FadeTransition(opacity: a, child: widget.next),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF030E22);
    const neon = Color(0xFF5DFF3C);
    return Scaffold(
      backgroundColor: bg,
      body: GestureDetector(
        onTap: _go, // toque pula a espera
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/brand/abertura.jpg', fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(0, 0.1),
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, bg],
                ),
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 72,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'NO TRECHO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'tô no trecho',
                    style: TextStyle(color: neon, fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
