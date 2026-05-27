import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/bridge_restriction.dart';
import '../models/user_restriction.dart';
import '../services/firestore_restriction_service.dart';
import 'restriction_repository.dart';

class FirestoreRestrictionRepository implements RestrictionRepository {
  @override
  Future<List<BridgeRestriction>> fetchNearRoute(List<LatLng> points) =>
      FirestoreRestrictionService.fetchNearRoute(points);

  @override
  Future<String> add(UserRestriction r, String uid) =>
      FirestoreRestrictionService.add(r, uid);

  @override
  Future<void> confirm(String id) => FirestoreRestrictionService.confirm(id);

  @override
  Future<void> report(String id) => FirestoreRestrictionService.report(id);
}
