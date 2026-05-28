import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config.dart';
import '../models/route_maneuver.dart';
import '../models/route_result.dart';
import '../models/truck_profile.dart';

class TomTomRoutingService {
  static Future<RouteResult> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    required TruckProfile truck,
    String? departureTime,
    List<LatLng> waypoints = const [],
  }) async {
    final locs = [
      '${origin.latitude},${origin.longitude}',
      ...waypoints.map((w) => '${w.latitude},${w.longitude}'),
      '${destination.latitude},${destination.longitude}',
    ].join(':');

    final params = <String, String>{
      'travelMode':    'truck',
      'vehicleHeight': (truck.heightCm / 100).toStringAsFixed(2),
      'vehicleWeight': truck.weightKg.toString(),
      'vehicleLength': (truck.lengthCm / 100).toStringAsFixed(2),
      'vehicleWidth':  (truck.widthCm  / 100).toStringAsFixed(2),
      'instructionsType': 'text',
      'language':         'pt-BR',
    };
    if (departureTime != null) params['departAt'] = departureTime;

    final uri = Uri.parse('$backendUrl/route/tomtom/$locs')
        .replace(queryParameters: params);
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('TomTom ${response.statusCode}: ${response.body}');
    }

    final data   = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = data['routes'] as List<dynamic>;
    if (routes.isEmpty) throw Exception('TomTom: nenhuma rota encontrada');

    final route   = routes[0] as Map<String, dynamic>;
    final summary = route['summary'] as Map<String, dynamic>;
    final legs    = route['legs'] as List<dynamic>;

    final points = <LatLng>[];
    for (final leg in legs) {
      for (final p in (leg as Map<String, dynamic>)['points'] as List<dynamic>) {
        final pt = p as Map<String, dynamic>;
        points.add(LatLng(
          (pt['latitude']  as num).toDouble(),
          (pt['longitude'] as num).toDouble(),
        ));
      }
    }

    final maneuvers = <RouteManeuver>[];
    for (final leg in legs) {
      final instructions =
          (leg as Map<String, dynamic>)['instructions'] as List<dynamic>? ?? [];
      for (final inst in instructions) {
        final i       = inst as Map<String, dynamic>;
        final maneuver = i['maneuver'] as String? ?? '';
        final pt      = i['point'] as Map<String, dynamic>;
        final pos     = LatLng(
          (pt['latitude']  as num).toDouble(),
          (pt['longitude'] as num).toDouble(),
        );
        maneuvers.add(RouteManeuver(
          instruction:     i['message'] as String? ?? '',
          action:          _mapAction(maneuver),
          direction:       _mapDirection(maneuver),
          distanceMeters:  (i['routeOffsetInMeters'] as num?)?.toInt() ?? 0,
          durationSeconds: (i['travelTimeInSeconds'] as num?)?.toInt() ?? 0,
          polylineOffset:  _closestIndex(pos, points),
          position:        pos,
        ));
      }
    }

    return RouteResult(
      polylinePoints:  points,
      distanceMeters:  (summary['lengthInMeters']      as num).toInt(),
      durationSeconds: (summary['travelTimeInSeconds'] as num).toInt(),
      maneuvers:       maneuvers,
      usedTomTomData:  true,
    );
  }

  static int _closestIndex(LatLng pos, List<LatLng> pts) {
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final dlat = pts[i].latitude  - pos.latitude;
      final dlng = pts[i].longitude - pos.longitude;
      final d = dlat * dlat + dlng * dlng;
      if (d < bestDist) { bestDist = d; best = i; }
    }
    return best;
  }

  static String _mapAction(String m) {
    if (m.startsWith('ROUNDABOUT')) return 'roundaboutExit';
    return switch (m) {
      'ARRIVE' || 'LOCATION_ARRIVAL'                             => 'arrive',
      'DEPART' || 'LOCATION_DEPARTURE'                           => 'depart',
      'TURN_LEFT'  || 'SHARP_LEFT'  || 'MAKE_UTURN'             => 'turn',
      'TURN_RIGHT' || 'SHARP_RIGHT'                              => 'turn',
      'KEEP_LEFT'  || 'BEAR_LEFT'                                => 'keep',
      'KEEP_RIGHT' || 'BEAR_RIGHT'                               => 'keep',
      'ENTER_MOTORWAY' || 'ENTER_FREEWAY' || 'ENTER_HIGHWAY'     => 'ramp',
      'TAKE_EXIT' || 'MOTOR_WAY_EXIT_LEFT' || 'MOTOR_WAY_EXIT_RIGHT' => 'exit',
      _ => 'continue',
    };
  }

  static String? _mapDirection(String m) => switch (m) {
    'TURN_LEFT'  || 'SHARP_LEFT'  || 'BEAR_LEFT'  || 'KEEP_LEFT'  => 'left',
    'TURN_RIGHT' || 'SHARP_RIGHT' || 'BEAR_RIGHT' || 'KEEP_RIGHT' => 'right',
    'MAKE_UTURN' => 'uTurnLeft',
    _ => null,
  };
}
