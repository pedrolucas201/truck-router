import 'package:flutter/material.dart';

import '../../models/poi.dart';
import '../../models/truck_profile.dart';

// ── Helpers de POI (nível de arquivo) ────────────────────────────────────────

IconData poiIconData(PoiCategory category) => switch (category) {
      PoiCategory.fuel     => Icons.local_gas_station,
      PoiCategory.scale    => Icons.monitor_weight,
      PoiCategory.restArea => Icons.local_hotel,
    };

Color poiCompatibleColor(PoiCategory category) => switch (category) {
      PoiCategory.fuel     => Colors.amber.shade700,
      PoiCategory.scale    => Colors.purple.shade600,
      PoiCategory.restArea => Colors.teal.shade600,
    };

class PoiSheet extends StatelessWidget {
  final Poi poi;
  final TruckProfile truck;
  final bool canAddWaypoint;
  final VoidCallback onAddToRoute;

  const PoiSheet({
    super.key,
    required this.poi,
    required this.truck,
    required this.canAddWaypoint,
    required this.onAddToRoute,
  });

  @override
  Widget build(BuildContext context) {
    final compatible = poi.isCompatibleWith(truck);
    final reason     = poi.incompatibilityReason(truck);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(poiIconData(poi.category),
                  color: poiCompatibleColor(poi.category), size: 20),
              const SizedBox(width: 8),
              Text(poi.categoryLabel,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Text(poi.name,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (poi.description != null) ...[
            const SizedBox(height: 4),
            Text(poi.description!,
                style:
                    TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ],
          const Divider(height: 24),
          Text('Restrições',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          InfoRow(Icons.height, 'Altura máx',
              poi.maxHeightCm != null
                  ? '${(poi.maxHeightCm! / 100).toStringAsFixed(2)}m'
                  : '—'),
          InfoRow(Icons.straighten, 'Comprimento máx',
              poi.maxLengthCm != null
                  ? '${(poi.maxLengthCm! / 100).toStringAsFixed(2)}m'
                  : '—'),
          InfoRow(Icons.scale, 'Peso máx',
              poi.maxWeightKg != null
                  ? '${(poi.maxWeightKg! / 1000).toStringAsFixed(0)}t'
                  : '—'),
          if (poi.category == PoiCategory.fuel)
            InfoRow(Icons.local_gas_station, 'Diesel',
                poi.hasDiesel ? 'Sim' : 'Não'),
          const SizedBox(height: 16),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: compatible
                  ? Colors.green.shade50
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  compatible ? Icons.check_circle : Icons.cancel,
                  color: compatible
                      ? Colors.green.shade600
                      : Colors.grey.shade500,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    compatible
                        ? 'Compatível com seu caminhão'
                        : reason ?? 'Incompatível com seu caminhão',
                    style: TextStyle(
                      fontSize: 13,
                      color: compatible
                          ? Colors.green.shade700
                          : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canAddWaypoint ? onAddToRoute : null,
              icon: const Icon(Icons.add_location_alt),
              label: Text(canAddWaypoint
                  ? 'Adicionar como parada'
                  : 'Máximo de paradas atingido (3)'),
            ),
          ),
        ],
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const InfoRow(this.icon, this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Text(label,
              style:
                  TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
