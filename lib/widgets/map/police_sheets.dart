import 'package:flutter/material.dart';

import '../../models/police_alert.dart';
import '../../services/police_alert_service.dart';

/// Triângulo apontando pra cima (seta simples desenhada a mão).
class UpArrowPainter extends CustomPainter {
  final Color color;
  const UpArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(UpArrowPainter old) => old.color != color;
}

/// Folha de detalhe de um alerta de polícia/radar/blitz já existente:
/// confirmar ou marcar como "não está mais lá".
class PoliceAlertSheet extends StatelessWidget {
  final PoliceAlert alert;
  const PoliceAlertSheet({super.key, required this.alert});

  String get _typeLabel => switch (alert.type) {
    PoliceAlertType.radar  => 'Radar',
    PoliceAlertType.police => 'Polícia',
    PoliceAlertType.blitz  => 'Blitz / Fiscalização',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_typeLabel, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(alert.timeRemainingText,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    if (alert.id != null) {
                      await PoliceAlertService.notThere(alert.id!);
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Não está mais lá'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    if (alert.id != null) {
                      await PoliceAlertService.confirm(alert.id!);
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Confirmar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Folha pra reportar um novo avistamento; retorna o [PoliceAlertType] escolhido
/// via Navigator.pop.
class ReportPoliceSheet extends StatelessWidget {
  const ReportPoliceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('O que você viu?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          for (final type in PoliceAlertType.values)
            ListTile(
              leading: Icon(switch (type) {
                PoliceAlertType.radar  => Icons.speed,
                PoliceAlertType.police => Icons.local_police,
                PoliceAlertType.blitz  => Icons.assignment_late,
              }),
              title: Text(switch (type) {
                PoliceAlertType.radar  => 'Radar de velocidade',
                PoliceAlertType.police => 'Polícia na via',
                PoliceAlertType.blitz  => 'Blitz / Fiscalização',
              }),
              onTap: () => Navigator.pop(context, type),
            ),
        ],
      ),
    );
  }
}
