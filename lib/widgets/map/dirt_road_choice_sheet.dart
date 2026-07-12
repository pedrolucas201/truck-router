import 'package:flutter/material.dart';

import '../../models/route_result.dart';

// ── Sheet de escolha: rota segura vs rota com estrada de terra ─────────────────

class DirtRoadChoiceSheet extends StatelessWidget {
  final RouteResult safeRoute;
  final RouteResult dirtyRoute;
  final String? selectedRoute;
  final VoidCallback onChooseSafe;
  final VoidCallback onChooseDirty;

  const DirtRoadChoiceSheet({
    super.key,
    required this.safeRoute,
    required this.dirtyRoute,
    required this.selectedRoute,
    required this.onChooseSafe,
    required this.onChooseDirty,
  });

  @override
  Widget build(BuildContext context) {
    final savingMin = (safeRoute.durationSeconds - dirtyRoute.durationSeconds) ~/ 60;
    final pavedSelected = selectedRoute == 'paved';
    final dirtSelected  = selectedRoute == 'dirt';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fork_right, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Duas rotas disponíveis',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              if (selectedRoute == null)
                Text('Toque na rota no mapa',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 16),
          RouteOption(
            icon: Icons.verified_outlined,
            iconColor: Colors.green.shade700,
            title: 'Rota pavimentada',
            subtitle: '${safeRoute.durationText}  •  ${safeRoute.distanceText}',
            note: null,
            highlighted: pavedSelected,
            highlightColor: const Color(0xFF1565C0),
          ),
          const SizedBox(height: 10),
          RouteOption(
            icon: Icons.warning_amber_rounded,
            iconColor: Colors.orange.shade700,
            title: 'Rota com estrada de terra',
            subtitle: '${dirtyRoute.durationText}  •  ${dirtyRoute.distanceText}',
            note: '$savingMin min mais rápida — pode ser intransitável para carretas',
            highlighted: dirtSelected,
            highlightColor: Colors.orange.shade700,
          ),
          const SizedBox(height: 20),
          if (selectedRoute != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: pavedSelected ? const Color(0xFF1565C0) : Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    pavedSelected ? 'Confirmando rota pavimentada…' : 'Confirmando rota com terra…',
                    style: TextStyle(
                      fontSize: 12,
                      color: pavedSelected ? const Color(0xFF1565C0) : Colors.orange.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onChooseSafe,
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Rota segura'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                  ),
                  onPressed: onChooseDirty,
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('Eu decido'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RouteOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? note;
  final bool highlighted;
  final Color highlightColor;

  const RouteOption({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.note,
    this.highlighted = false,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlighted ? highlightColor.withAlpha(18) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlighted ? highlightColor : Colors.grey.shade300,
          width: highlighted ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade700)),
                if (note != null) ...[
                  const SizedBox(height: 4),
                  Text(note!,
                      style: TextStyle(
                          fontSize: 12, color: Colors.orange.shade800)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
