import 'package:flutter/material.dart';

class MapCrosshair extends StatelessWidget {
  const MapCrosshair({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(60, 60),
      painter: MapCrosshairPainter(Theme.of(context).colorScheme.primary),
    );
  }
}

class MapCrosshairPainter extends CustomPainter {
  final Color primaryColor;
  const MapCrosshairPainter(this.primaryColor);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const gap = 8.0;

    final shadow = Paint()
      ..color = Colors.black38
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final line = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(0, cy), Offset(cx - gap, cy), shadow);
    canvas.drawLine(Offset(cx + gap, cy), Offset(size.width, cy), shadow);
    canvas.drawLine(Offset(cx, 0), Offset(cx, cy - gap), shadow);
    canvas.drawLine(Offset(cx, cy + gap), Offset(cx, size.height), shadow);

    canvas.drawLine(Offset(0, cy), Offset(cx - gap, cy), line);
    canvas.drawLine(Offset(cx + gap, cy), Offset(size.width, cy), line);
    canvas.drawLine(Offset(cx, 0), Offset(cx, cy - gap), line);
    canvas.drawLine(Offset(cx, cy + gap), Offset(cx, size.height), line);

    canvas.drawCircle(Offset(cx, cy), 5, Paint()..color = primaryColor);
    canvas.drawCircle(Offset(cx, cy), 2.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
