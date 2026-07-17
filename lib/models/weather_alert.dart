import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Célula de clima severo na rota, na hora projetada de passagem. Vem digerida
/// pelo backend (`/weather/route`) — o app não vê forecast cru, só o que virou
/// alerta. `kind`: rain | wind | fog.
class WeatherAlert {
  final LatLng position;
  final DateTime time; // hora projetada de passagem (com offset da fonte)
  final String kind;
  final String label; // pronto pro usuário ("Chuva forte")
  final String icon;

  const WeatherAlert({
    required this.position,
    required this.time,
    required this.kind,
    required this.label,
    required this.icon,
  });

  factory WeatherAlert.fromJson(Map<String, dynamic> j) => WeatherAlert(
        position: LatLng(
          (j['lat'] as num).toDouble(),
          (j['lng'] as num).toDouble(),
        ),
        time: DateTime.tryParse(j['time'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        kind: j['kind'] as String? ?? '',
        label: j['label'] as String? ?? 'Clima adverso',
        icon: j['icon'] as String? ?? '',
      );

  /// "14:30" no fuso do aparelho.
  String get timeLabel =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}
