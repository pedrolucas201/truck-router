import 'dart:convert';
import 'dart:math';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/weather_alert.dart';
import 'auth_service.dart';
import 'field_log.dart';

/// Clima na rota. Amostra a polyline, projeta a hora de passagem de cada ponto e
/// pede ao backend SÓ as células severas (o HERE cru é ~86KB/ponto — o digest
/// fica no servidor). Fire-and-forget: qualquer falha vira lista vazia, NUNCA
/// derruba o cálculo de rota nem a navegação.
class WeatherService {
  // Espaçamento da amostragem. A grade horária do clima é grosseira (~11km+),
  // então < ~15km é desperdício; 20km pega serra/frente sem estourar chamadas.
  // ponytail: constante; se virar por-tipo-de-rota, sobe pra config.
  static const double _sampleMeters = 20000;

  static Future<List<WeatherAlert>> forecastAlongRoute({
    required List<LatLng> polyline,
    required DateTime departure,
    required int durationSeconds,
  }) async {
    if (polyline.length < 2 || durationSeconds <= 0 || backendUrl.isEmpty) {
      return const [];
    }
    try {
      final points = _sample(polyline, departure, durationSeconds);
      if (points.isEmpty) return const [];

      final headers = await AuthService.getHeaders();
      final resp = await http
          .post(
            Uri.parse('$backendUrl/weather/route'),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'points': points}),
          )
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = (data['alerts'] as List?) ?? const [];
      return list
          .map((e) => WeatherAlert.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      // Clima é opcional: loga pra diagnóstico, mas o motorista não vê nada.
      FieldLog.error('weather_route', e, st);
      return const [];
    }
  }

  /// Amostra a polyline a cada [_sampleMeters] e devolve {lat,lng,time} com a hora
  /// projetada LINEARMENTE pela fração de distância. A grade horária do clima
  /// engole o erro de assumir velocidade constante. Tempo em UTC (sufixo Z) —
  /// o parser RFC3339 do backend exige offset.
  static List<Map<String, dynamic>> _sample(
      List<LatLng> poly, DateTime dep, int durS) {
    final cum = <double>[0];
    for (var i = 1; i < poly.length; i++) {
      cum.add(cum[i - 1] + _haversine(poly[i - 1], poly[i]));
    }
    final total = cum.last;
    if (total <= 0) return const [];

    final out = <Map<String, dynamic>>[];
    var nextMark = 0.0;
    for (var i = 0; i < poly.length; i++) {
      if (cum[i] < nextMark) continue;
      final frac = cum[i] / total;
      final t = dep.add(Duration(seconds: (durS * frac).round()));
      out.add({
        'lat': poly[i].latitude,
        'lng': poly[i].longitude,
        'time': t.toUtc().toIso8601String(),
      });
      nextMark += _sampleMeters;
    }
    return out;
  }

  static double _haversine(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final la1 = a.latitude * pi / 180;
    final la2 = b.latitude * pi / 180;
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(la1) * cos(la2) * sin(dLng / 2) * sin(dLng / 2);
    return 2 * r * asin(sqrt(h));
  }
}
