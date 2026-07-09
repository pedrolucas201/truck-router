import 'package:flutter/material.dart';

/// Placa de limite de velocidade (padrão R-19 brasileiro): círculo branco, anel
/// vermelho grosso, número preto grande + "km/h". Usada nos chips de curadoria
/// de radar (o passo em que o motorista escolhe a velocidade real). Pedido do
/// Gilberto (2026-07-09): a plaquinha de trânsito é o que ele lê num relance.
///
/// Só aqui — no mapa e no bottom bar o número segue no formato antigo (decisão
/// do Pedro na mesma data).
class SpeedPlate extends StatelessWidget {
  final int kmh;
  final double size;
  final VoidCallback? onTap;

  const SpeedPlate({super.key, required this.kmh, this.size = 54, this.onTap});

  @override
  Widget build(BuildContext context) {
    final ring = size * 0.09;
    final plate = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: Colors.red.shade700, width: ring),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$kmh',
              style: TextStyle(
                  color: Colors.black,
                  fontSize: size * 0.37,
                  fontWeight: FontWeight.w800,
                  height: 1.0)),
          Text('km/h',
              style: TextStyle(
                  color: Colors.black,
                  fontSize: size * 0.15,
                  fontWeight: FontWeight.w600,
                  height: 1.0)),
        ],
      ),
    );
    if (onTap == null) return plate;
    // Círculo → borda circular no ripple.
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: plate,
    );
  }
}
