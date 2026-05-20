import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/bridge_restriction.dart';
import '../models/user_restriction.dart';

abstract class RestrictionRepository {
  Future<List<BridgeRestriction>> fetchNearRoute(List<LatLng> points);
  Future<String> add(UserRestriction r, String uid);
  Future<void> confirm(String id);
  Future<void> report(String id);
}
