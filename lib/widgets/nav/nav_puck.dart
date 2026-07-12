import 'package:flutter/material.dart';

/// Puck (seta) do usuário como widget Flutter fixo, FORA do method channel do
/// mapa. Atualizar posição de um Marker a cada frame era o gargalo do lag
/// (flutter#33430); aqui a seta é estática e o mapa desliza por baixo. Câmera é
/// heading-up, então a seta sempre aponta pra cima. Réplica de _buildUserArrow.
class NavPuck extends StatelessWidget {
  const NavPuck({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 40,
        height: 40,
        child: CustomPaint(painter: PuckPainter()),
      );
}

class PuckPainter extends CustomPainter {
  const PuckPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final path = Path()
      ..moveTo(s / 2, 2)            // ponta superior (frente)
      ..lineTo(s - 4, s - 6)       // canto direito
      ..lineTo(s / 2, s * 0.60)    // entalhe central
      ..lineTo(4, s - 6)           // canto esquerdo
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(path, Paint()..color = const Color(0xFF1565C0));
  }

  @override
  bool shouldRepaint(covariant PuckPainter oldDelegate) => false;
}
