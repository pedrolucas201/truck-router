import 'package:flutter/material.dart';

import '../../models/bridge_restriction.dart';
import '../../models/truck_profile.dart';
import '../../utils/meters.dart';

// ── BlockedSheet — restrição que o roteador não conseguiu contornar ─────────
//
// Cores do TEMA (não rosa/cinza fixos): em tema escuro o texto herdava cor
// clara em fundo claro e ficava ilegível (print do Pedro, 26/09). Texto sem
// nome de fornecedor (regra: o motorista vê resultado, nunca processo interno).

class BlockedSheet extends StatelessWidget {
  final List<BridgeRestriction> blocked;
  final VoidCallback onAddWaypoint;
  // Toque no card → fecha a sheet e leva a câmera ao ponto restrito, pro
  // motorista ver ONDE é (separar restrição real da via de baixo / de um prédio).
  final void Function(BridgeRestriction)? onSelect;
  /// Caminhão ativo, pra pôr a medida dele do lado do limite.
  final TruckProfile? caminhao;

  const BlockedSheet({
    super.key,
    required this.blocked,
    required this.onAddWaypoint,
    this.onSelect,
    this.caminhao,
  });

  static IconData _iconFor(String type) => switch (type) {
        'maxheight' => Icons.height,
        'maxweight' => Icons.monitor_weight,
        'maxwidth'  => Icons.swap_horiz,
        _           => Icons.warning_amber_rounded,
      };

  /// "Passagem de 4,20 m" / "Limite de 30 t" / "Largura de 2,50 m".
  static String limite(BridgeRestriction r) {
    String m(double v) => cmToMeters((v * 100).round());
    return switch (r.type) {
      'maxheight' => 'Passagem de ${m(r.value)} m',
      'maxweight' => 'Limite de ${r.value.toStringAsFixed(0)} t',
      'maxwidth'  => 'Largura de ${m(r.value)} m',
      _           => r.label,
    };
  }

  /// "Seu caminhão: 4,40 m". Null sem caminhão ou tipo sem medida.
  static String? doCaminhao(BridgeRestriction r, TruckProfile? t) {
    if (t == null) return null;
    return switch (r.type) {
      'maxheight' => 'Seu caminhão: ${cmToMeters(t.heightCm)} m',
      'maxweight' => 'Seu caminhão: ${(t.weightKg / 1000).toStringAsFixed(0)} t',
      'maxwidth'  => 'Seu caminhão: ${cmToMeters(t.widthCm)} m',
      _           => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            blocked.length == 1
                ? 'Passagem mais baixa que o seu caminhão'
                : '${blocked.length} pontos que não cabem no seu caminhão',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Não achei outro caminho que evite. Confira no mapa: às vezes a passagem é de outra via, '
            'por baixo da ponte por onde você passa.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 16),
          ...blocked.map((r) {
            final meu = doCaminhao(r, caminhao);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onSelect == null ? null : () => onSelect!(r),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(_iconFor(r.type), color: cs.onErrorContainer, size: 26),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(limite(r),
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cs.onErrorContainer)),
                              if (meu != null)
                                Text(meu, style: TextStyle(fontSize: 14, color: cs.onErrorContainer)),
                              if (r.roadName != null && r.roadName!.isNotEmpty)
                                Text(r.roadName!, style: TextStyle(fontSize: 13, color: cs.onErrorContainer.withValues(alpha: .8))),
                            ],
                          ),
                        ),
                        if (onSelect != null)
                          Text('Ver no mapa ›',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cs.onErrorContainer)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 4),
          Text(
            'Se for mesmo no seu caminho, adicione uma parada antes dela pra forçar outro trajeto.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
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
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Continuar mesmo assim'),
            ),
          ),
        ],
      ),
    );
  }
}
