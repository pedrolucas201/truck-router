import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bridge_restriction.dart';
import '../../models/route_result.dart';
import '../../models/weather_alert.dart';
import '../../providers/truck_profile_provider.dart';

class ResultCard extends StatelessWidget {
  final RouteResult result;
  final List<WeatherAlert> weatherAlerts;
  final DateTime? departureTime;
  final VoidCallback onStartNavigation;
  final VoidCallback onOpenExternal;
  final VoidCallback onShare;
  final VoidCallback onCopy;
  final VoidCallback? onBlockedTap;

  const ResultCard({
    super.key,
    required this.result,
    this.weatherAlerts = const [],
    required this.departureTime,
    required this.onStartNavigation,
    required this.onOpenExternal,
    required this.onShare,
    required this.onCopy,
    this.onBlockedTap,
  });

  static String _etaString(DateTime? departureTime, int durationSeconds) {
    final base = departureTime ?? DateTime.now();
    final eta  = base.add(Duration(seconds: durationSeconds));
    return '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final primary  = Theme.of(context).colorScheme.primary;
    final etaLabel = _etaString(departureTime, result.durationSeconds);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        if (result.restrictionsAvoided.isNotEmpty ||
            result.restrictionsBlocked.isNotEmpty)
          RestrictionsBanner(
            avoided: result.restrictionsAvoided,
            blocked: result.restrictionsBlocked,
            onBlockedTap: onBlockedTap,
          ),
        if (weatherAlerts.isNotEmpty) WeatherBanner(alerts: weatherAlerts),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              InfoItem(icon: Icons.straighten, label: 'Distância', value: result.distanceText, color: primary),
              InfoItem(icon: Icons.schedule, label: result.durationText, value: etaLabel, color: primary),
              Consumer<TruckProfileProvider>(
                builder: (context, p, child) => InfoItem(
                  icon: Icons.local_shipping,
                  label: 'Caminhão',
                  value: '${p.profile.heightCm}cm · ${(p.profile.weightKg / 1000).toStringAsFixed(0)}t',
                  color: primary,
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy, size: 20, color: primary),
                onPressed: onCopy,
                tooltip: 'Copiar texto',
              ),
              IconButton(
                icon: Icon(Icons.share, size: 20, color: primary),
                onPressed: onShare,
                tooltip: 'Compartilhar',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onStartNavigation,
              icon: const Icon(Icons.navigation),
              label: const Text('Iniciar viagem'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onOpenExternal,
              icon: Icon(Icons.open_in_new, size: 16, color: Colors.grey.shade600),
              label: Text(
                'Abrir em Waze / Google Maps',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const InfoItem({super.key, required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        const SizedBox(height: 1),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }
}

class RestrictionsBanner extends StatelessWidget {
  final List<BridgeRestriction> avoided;
  final List<BridgeRestriction> blocked;
  final VoidCallback? onBlockedTap;

  const RestrictionsBanner({super.key, required this.avoided, required this.blocked, this.onBlockedTap});

  @override
  Widget build(BuildContext context) {
    final hasBlocked = blocked.isNotEmpty;
    final color   = hasBlocked ? Colors.red.shade700    : Colors.green.shade600;
    final bgColor = hasBlocked ? Colors.red.shade50     : Colors.green.shade50;
    final border  = hasBlocked ? Colors.red.shade200    : Colors.green.shade200;
    final icon    = hasBlocked ? Icons.block            : Icons.check_circle_outline;

    final String message;
    if (hasBlocked) {
      final labels = blocked.map((r) => r.label).join(', ');
      message = blocked.length == 1
          ? 'Restrição não contornável: $labels'
          : '${blocked.length} restrições não contornáveis: $labels';
    } else {
      final total      = avoided.length;
      final unverified = avoided.where((r) => !r.isVerified).length;
      if (unverified == 0) {
        message = total == 1
            ? '1 restrição contornada automaticamente'
            : '$total restrições contornadas automaticamente';
      } else if (unverified == total) {
        message = total == 1
            ? '1 restrição contornada (aguardando confirmação de outros motoristas)'
            : '$total restrições contornadas (não verificadas — aguardando mais relatos)';
      } else {
        final verified = total - unverified;
        message = '$total restrições contornadas ($verified verificadas, $unverified aguardando confirmação)';
      }
    }

    final banner = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w500),
            ),
          ),
          if (hasBlocked) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: color, size: 18),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: hasBlocked
          ? GestureDetector(onTap: onBlockedTap, child: banner)
          : banner,
    );
  }
}

/// Aviso de clima severo na rota (fatia A) — resumo glanceável no card de
/// preview, antes de sair. Só aparece quando há célula severa.
class WeatherBanner extends StatelessWidget {
  final List<WeatherAlert> alerts;
  const WeatherBanner({super.key, required this.alerts});

  static IconData _iconFor(String kind) => switch (kind) {
        'rain' => Icons.umbrella,
        'wind' => Icons.air,
        'fog' => Icons.foggy,
        _ => Icons.cloud_outlined,
      };

  @override
  Widget build(BuildContext context) {
    // Ordena por hora de passagem: o primeiro é o que vem antes na viagem.
    final sorted = [...alerts]..sort((a, b) => a.time.compareTo(b.time));
    final first = sorted.first;
    final message = sorted.length == 1
        ? '${first.label} na rota · ~${first.timeLabel}'
        : '${sorted.length} avisos de clima na rota · a partir de ~${first.timeLabel}';

    final color = Colors.amber.shade800;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.shade200),
        ),
        child: Row(
          children: [
            Icon(_iconFor(first.kind), color: color, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
