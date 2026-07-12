import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config.dart';
import 'auth_service.dart';
import '../models/route_maneuver.dart';
import '../models/route_result.dart';
import '../models/truck_profile.dart';
import 'flexible_polyline_decoder.dart';

class HereRoutingService {
  static Future<RouteResult> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    required TruckProfile truck,
    String? departureTime,
    double? course,
    List<LatLng> waypoints   = const [],
    List<String> avoidAreas  = const [],
    bool avoidDirtRoad        = true,
  }) async {
    // course = rumo de marcha (0-359, N=0). Informado, a HERE inicia a rota NESSE
    // sentido em vez de escolher a mais curta — evita o "dê meia-volta" no reroute.
    final originParam = course == null
        ? '${origin.latitude},${origin.longitude}'
        : '${origin.latitude},${origin.longitude};course=${course.round() % 360}';
    final params = <String, dynamic>{
      'transportMode':   'truck',
      'origin':          originParam,
      'destination':     '${destination.latitude},${destination.longitude}',
      'return':          'polyline,summary,actions',
      // spans é parâmetro PRÓPRIO — NÃO vai dentro de 'return' (isso dá E605001).
      // Com transportMode=truck a HERE já devolve o limite do CAMINHÃO por trecho.
      // dynamicSpeedInfo (sem departureTime) traz baseSpeed vs trafficSpeed = trânsito.
      // notices: cada span referencia o notice por índice + traz o offset → dá pra
      // fixar a restrição de caminhão num ponto do mapa (report Gilberto 12/07).
      'spans':           'speedLimit,dynamicSpeedInfo,notices',
      'lang':            'pt-BR',
      if (avoidDirtRoad) 'avoid[features]': 'dirtRoad',
      ...truck.toHereParams(),
      'departureTime': ?departureTime,
      if (waypoints.isNotEmpty)
        'via': waypoints.map((w) => '${w.latitude},${w.longitude}').toList(),
    };

    // Uri.https encodes brackets as %5B/%5D — HERE requires literal vehicle[height] notation.
    final parts = <String>[];
    params.forEach((key, value) {
      if (value == null) return;
      if (value is List) {
        for (final v in value) {
          parts.add('$key=${Uri.encodeQueryComponent(v.toString())}');
        }
      } else {
        parts.add('$key=${Uri.encodeQueryComponent(value.toString())}');
      }
    });
    // avoid[areas] usa ':' e '|' como delimitadores — não pode ser codificado.
    if (avoidAreas.isNotEmpty) {
      parts.add('avoid[areas]=${avoidAreas.join('|')}');
    }
    final uri = Uri.parse('$backendUrl/route/here?${parts.join('&')}');
    final response = await http.get(uri, headers: await AuthService.getHeaders());

    if (response.statusCode != 200) {
      throw Exception('HERE API error ${response.statusCode}: ${response.body}');
    }

    final data   = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = data['routes'] as List<dynamic>;
    if (routes.isEmpty) throw Exception('Nenhuma rota encontrada');

    final route0   = routes[0] as Map<String, dynamic>;
    final sections = route0['sections'] as List<dynamic>;

    // violatedVehicleRestriction inclui restrições de horário para caminhões.
    final routeNotices = route0['notices'] as List<dynamic>? ?? [];
    final sectionNotices = sections
        .cast<Map<String, dynamic>>()
        .expand((s) => s['notices'] as List<dynamic>? ?? [])
        .toList();
    final violatedNotices = [...routeNotices, ...sectionNotices]
        .cast<Map<String, dynamic>>()
        .where((n) => n['code'] == 'violatedVehicleRestriction')
        .toList();
    final hasTimeRestriction = violatedNotices.isNotEmpty;
    final restrictionLabel = _restrictionLabel(violatedNotices);

    final allPoints   = <LatLng>[];
    final allManeuvers = <RouteManeuver>[];
    var totalDistance = 0;
    var totalDuration = 0;
    final speedLimits = <SpeedLimitSpan>[];
    final trafficSpans = <TrafficSpan>[];
    final restrictionPoints = <RestrictionPoint>[];
    final seenRestriction = <String>{}; // dedup por posição+rótulo

    for (final s in sections) {
      final section      = s as Map<String, dynamic>;
      final summary      = section['summary'] as Map<String, dynamic>;
      final sectionOffset = allPoints.length;

      totalDistance += (summary['length'] as num).toInt();
      totalDuration += (summary['duration'] as num).toInt();

      final sectionPoints = FlexiblePolylineDecoder.decode(section['polyline'] as String);
      allPoints.addAll(sectionPoints);

      final actions = section['actions'] as List<dynamic>? ?? [];
      for (final a in actions) {
        final action = a as Map<String, dynamic>;
        final localOffset = (action['offset'] as num?)?.toInt() ?? 0;
        final globalOffset = sectionOffset + localOffset;
        final pos = globalOffset < allPoints.length
            ? allPoints[globalOffset]
            : allPoints.last;

        allManeuvers.add(RouteManeuver(
          instruction:     action['instruction'] as String? ?? '',
          action:          action['action'] as String? ?? 'continue',
          direction:       action['direction'] as String?,
          distanceMeters:  (action['length'] as num?)?.toInt() ?? 0,
          durationSeconds: (action['duration'] as num?)?.toInt() ?? 0,
          polylineOffset:  globalOffset,
          position:        pos,
        ));
      }

      // Limite de caminhão por trecho — HERE já dá ciente do modo (m/s).
      // offset do span é relativo à section: soma sectionOffset p/ virar índice
      // global na polyline (mesmo esquema das manobras acima).
      // Notices da seção: os índices em span['notices'] apontam pra CÁ.
      final secNotices =
          (section['notices'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final seenIdxInSection = <int>{}; // 1º offset de cada notice = início do trecho
      final spans = section['spans'] as List<dynamic>? ?? [];
      for (final sp in spans) {
        final span = sp as Map<String, dynamic>;
        final offset = sectionOffset + ((span['offset'] as num?)?.toInt() ?? 0);

        final speedMs = (span['speedLimit'] as num?)?.toDouble();
        if (speedMs != null && speedMs > 0) {
          speedLimits.add(SpeedLimitSpan(offset, (speedMs * 3.6).round()));
        }

        // Restrição de caminhão neste trecho → ponto no mapa. O span traz os
        // índices dos notices da seção; o 1º span que cita um notice = onde o
        // trecho restrito começa.
        for (final ni in (span['notices'] as List?)?.cast<num>() ?? const []) {
          final i = ni.toInt();
          if (i < 0 || i >= secNotices.length) continue;
          if (!seenIdxInSection.add(i)) continue;
          final n = secNotices[i];
          if (n['code'] != 'violatedVehicleRestriction') continue;
          final pos = offset < allPoints.length ? allPoints[offset] : allPoints.last;
          final label = _labelForNotice(n) ?? 'Restrição para caminhões nesta via';
          final key = '${pos.latitude},${pos.longitude}|$label';
          if (seenRestriction.add(key)) {
            restrictionPoints.add(RestrictionPoint(pos, label));
          }
        }

        // Trânsito: razão trafficSpeed/baseSpeed. Guarda TODOS os spans (inclusive
        // free) — o free serve de fronteira p/ o render saber onde o trecho lento
        // termina; só free não é pintado.
        final dsi = span['dynamicSpeedInfo'] as Map<String, dynamic>?;
        final base = (dsi?['baseSpeed'] as num?)?.toDouble();
        final traffic = (dsi?['trafficSpeed'] as num?)?.toDouble();
        if (base != null && base > 0 && traffic != null) {
          trafficSpans.add(TrafficSpan(offset, TrafficLevel.fromRatio(traffic / base)));
        }
      }
    }

    return RouteResult(
      polylinePoints:    allPoints,
      distanceMeters:    totalDistance,
      durationSeconds:   totalDuration,
      maneuvers:         allManeuvers,
      hasTimeRestriction: hasTimeRestriction,
      restrictionLabel:   restrictionLabel,
      restrictionPoints:  restrictionPoints,
      speedLimits:        speedLimits,
      trafficSpans:       trafficSpans,
    );
  }

  // Monta o texto do banner a partir do `details` do notice (o `title` da HERE
  // vem "Violated vehicle restriction." em inglês genérico — inútil). Dimensão
  // primeiro (concreto), horário como fallback. cm→m, kg→t. Null = texto genérico.
  static String? _restrictionLabel(List<Map<String, dynamic>> notices) {
    for (final n in notices) {
      final l = _labelForNotice(n);
      if (l != null) return l;
    }
    return null;
  }

  // Rótulo de UM notice (dimensão primeiro, horário/acesso como fallback).
  // Null quando não reconhece nada (chamador usa texto genérico).
  static String? _labelForNotice(Map<String, dynamic> n) {
    final details = (n['details'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    for (final d in details) {
      String m(num cm) => (cm / 100).toStringAsFixed(1).replaceAll('.', ',');
      final w = d['maxWeight'] as num?;
      if (w != null) {
        final t = w / 1000;
        final txt = t == t.roundToDouble()
            ? t.round().toString()
            : t.toStringAsFixed(1).replaceAll('.', ',');
        return 'Restrição: peso máx $txt t';
      }
      if (d['maxHeight'] != null) return 'Restrição: altura máx ${m(d['maxHeight'] as num)} m';
      if (d['maxLength'] != null) return 'Restrição: comprimento máx ${m(d['maxLength'] as num)} m';
      if (d['maxWidth']  != null) return 'Restrição: largura máx ${m(d['maxWidth'] as num)} m';
      if (d['type'] == 'violatedTransportMode') return 'Via proibida para caminhões';
      if (d['timeDependent'] == true) return 'Restrição por horário nesta via';
    }
    return null;
  }
}
