import 'package:flutter/material.dart';

class MarkingOnboardingSheet extends StatelessWidget {
  const MarkingOnboardingSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.add_location_alt, color: primary, size: 22),
              const SizedBox(width: 10),
              Text('Marcar restrição de via',
                  style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Use quando encontrar:',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 10),
          OnboardingItem(Icons.height,         'Viaduto com altura limitada'),
          OnboardingItem(Icons.monitor_weight, 'Via com restrição de peso'),
          OnboardingItem(Icons.swap_horiz,     'Passagem com largura baixa'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primary.withAlpha(15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: primary.withAlpha(40)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Arraste o mapa até o local exato, confirme e informe o valor. '
                    'Os dados coletados melhoram as rotas para todos os motoristas.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const OnboardingItem(this.icon, this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
