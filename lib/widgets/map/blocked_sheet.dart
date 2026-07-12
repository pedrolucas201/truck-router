import 'package:flutter/material.dart';

import '../../models/bridge_restriction.dart';

// ── BlockedSheet — detalhes de restrição não contornável ────────────────────

class BlockedSheet extends StatelessWidget {
  final List<BridgeRestriction> blocked;
  final VoidCallback onAddWaypoint;

  const BlockedSheet({super.key, required this.blocked, required this.onAddWaypoint});

  static IconData _iconFor(String type) => switch (type) {
        'maxheight' => Icons.height,
        'maxweight' => Icons.monitor_weight,
        'maxwidth'  => Icons.swap_horiz,
        _           => Icons.warning_amber_rounded,
      };

  static String _typeLabel(String type) => switch (type) {
        'maxheight' => 'Altura máxima',
        'maxweight' => 'Peso máximo',
        'maxwidth'  => 'Largura máxima',
        _           => 'Restrição',
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.block, color: Colors.red.shade700, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  blocked.length == 1
                      ? 'Passagem incompatível com seu caminhão'
                      : '${blocked.length} restrições incompatíveis com seu caminhão',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'HERE não encontrou rota alternativa automática para estas restrições.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          ...blocked.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(_iconFor(r.type), color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _typeLabel(r.type),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.red.shade700,
                                  fontWeight: FontWeight.w600),
                            ),
                            Text(
                              r.label,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      if (r.isVerified)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber.shade400),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.verified, size: 11, color: Colors.amber.shade700),
                            const SizedBox(width: 3),
                            Text('Verificada',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.amber.shade800,
                                    fontWeight: FontWeight.w600)),
                          ]),
                        ),
                    ],
                  ),
                ),
              )),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Adicione uma parada antes da restrição para forçar um desvio manual.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                onAddWaypoint();
              },
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Adicionar parada'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Continuar mesmo assim',
                  style: TextStyle(color: Colors.grey.shade600)),
            ),
          ),
        ],
      ),
    );
  }
}
