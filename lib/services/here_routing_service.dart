import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config.dart';
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
    List<LatLng> waypoints  = const [],
    List<String> avoidAreas = const [],
  }) async {
    final params = <String, dynamic>{
      'transportMode':   'truck',
      'origin':          '${origin.latitude},${origin.longitude}',
      'destination':     '${destination.latitude},${destination.longitude}',
      'return':          'polyline,summary,actions',
      'lang':            'pt-BR',
      'apikey':          hereApiKey,
      'avoid[features]': 'dirtRoad',
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
    final uri = Uri.parse('https://router.hereapi.com/v8/routes?${parts.join('&')}');
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('HERE API error ${response.statusCode}: ${response.body}');
    }

    final data   = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = data['routes'] as List<dynamic>;
    if (routes.isEmpty) throw Exception('Nenhuma rota encontrada');

    final sections = (routes[0] as Map<String, dynamic>)['sections'] as List<dynamic>;

    final allPoints   = <LatLng>[];
    final allManeuvers = <RouteManeuver>[];
    var totalDistance = 0;
    var totalDuration = 0;

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
    }

    return RouteResult(
      polylinePoints:  allPoints,
      distanceMeters:  totalDistance,
      durationSeconds: totalDuration,
      maneuvers:       allManeuvers,
    );
  }
}
