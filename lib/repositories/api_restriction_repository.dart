import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/bridge_restriction.dart';
import '../models/user_restriction.dart';
import 'restriction_repository.dart';

class ApiRestrictionRepository implements RestrictionRepository {
  final String baseUrl;
  ApiRestrictionRepository(this.baseUrl);

  @override
  Future<List<BridgeRestriction>> fetchNearRoute(List<LatLng> points) async {
    if (points.isEmpty) return [];
    var minLat = points[0].latitude, maxLat = points[0].latitude;
    var minLng = points[0].longitude, maxLng = points[0].longitude;
    for (final p in points) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    try {
      final uri = Uri.parse('$baseUrl/restrictions').replace(queryParameters: {
        'minLat': minLat.toString(),
        'maxLat': maxLat.toString(),
        'minLng': minLng.toString(),
        'maxLng': maxLng.toString(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final list = jsonDecode(resp.body) as List<dynamic>;
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return BridgeRestriction(
          id:          m['id'] as String?,
          lat:         (m['lat']   as num).toDouble(),
          lng:         (m['lng']   as num).toDouble(),
          type:        m['type']   as String,
          value:       (m['value'] as num).toDouble(),
          roadName:    m['roadName'] as String?,
          confirmedBy: (m['confirmedBy'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<String> add(UserRestriction r, String uid) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl/restrictions'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({...r.toJson(), 'uid': uid}),
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 201) {
      throw Exception('API ${resp.statusCode}: ${resp.body}');
    }
    return (jsonDecode(resp.body) as Map<String, dynamic>)['id'] as String;
  }

  @override
  Future<void> confirm(String id) async {
    await http
        .post(Uri.parse('$baseUrl/restrictions/$id/confirm'))
        .timeout(const Duration(seconds: 10));
  }

  @override
  Future<void> report(String id) async {
    await http
        .post(Uri.parse('$baseUrl/restrictions/$id/report'))
        .timeout(const Duration(seconds: 10));
  }
}
