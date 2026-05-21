import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/route_result.dart';
import '../models/truck_profile.dart';
import '../services/firestore_restriction_service.dart';
import '../services/here_routing_service.dart';
import '../services/overpass_service.dart';
import '../services/tomtom_routing_service.dart';

enum RouteStatus { idle, loading, success, error }

class RouteProvider extends ChangeNotifier {
  RouteStatus _status = RouteStatus.idle;
  RouteResult? _result;
  String? _errorMessage;

  RouteStatus get status => _status;
  RouteResult? get result => _result;
  String? get errorMessage => _errorMessage;

  Future<void> calculate({
    required LatLng origin,
    required LatLng destination,
    required TruckProfile truck,
    DateTime? departureTime,
    List<LatLng> waypoints = const [],
    List<String> manualAvoidAreas = const [],
  }) async {
    _status = RouteStatus.loading;
    _result = null;
    _errorMessage = null;
    notifyListeners();

    try {
      final deptTime = departureTime?.toIso8601String().split('.').first;

      // TomTom roda em paralelo desde o início — não adiciona latência.
      final tomtomFuture = () async {
        try {
          return await TomTomRoutingService.calculateRoute(
            origin:        origin,
            destination:   destination,
            truck:         truck,
            departureTime: deptTime,
            waypoints:     waypoints,
          );
        } catch (_) {
          return null;
        }
      }();

      // 1. Rota inicial já evitando restrições marcadas manualmente.
      var result = await HereRoutingService.calculateRoute(
        origin:        origin,
        destination:   destination,
        truck:         truck,
        departureTime: deptTime,
        waypoints:     waypoints,
        avoidAreas:    manualAvoidAreas,
      );

      // 2. Overpass + Firestore em paralelo — restrições físicas no corredor.
      final overpassFuture =
          OverpassService.queryAlongRoute(result.polylinePoints);
      final firestoreFuture =
          FirestoreRestrictionService.fetchNearRoute(result.polylinePoints);
      final overpassRestrictions = await overpassFuture;
      final firestoreRestrictions = await firestoreFuture;

      final conflicts = [
        ...overpassRestrictions,
        ...firestoreRestrictions,
      ].where((r) => r.conflictsWith(truck)).toList();

      // 3. Recalcula evitando Overpass + restrições manuais.
      if (conflicts.isNotEmpty) {
        final avoidAreas = [
          ...manualAvoidAreas,
          ...conflicts.map((r) => r.toAvoidArea()),
        ];
        try {
          final rerouted = await HereRoutingService.calculateRoute(
            origin:        origin,
            destination:   destination,
            truck:         truck,
            departureTime: deptTime,
            waypoints:     waypoints,
            avoidAreas:    avoidAreas,
          );
          result = rerouted.copyWith(restrictionsAvoided: conflicts);
        } catch (_) {
          // HERE não encontrou rota alternativa — usa a original e avisa.
          result = result.copyWith(restrictionsBlocked: conflicts);
        }
      }

      // 4. TomTom como segunda fonte: usa se encontrou rota >10% mais longa,
      //    o que indica restrições físicas que a HERE não tem mapeadas.
      final tomtomResult = await tomtomFuture;
      if (tomtomResult != null &&
          tomtomResult.distanceMeters > result.distanceMeters * 1.10) {
        result = tomtomResult.copyWith(
          restrictionsAvoided: result.restrictionsAvoided,
          restrictionsBlocked: result.restrictionsBlocked,
        );
      }

      _result = result;
      _status = RouteStatus.success;
    } catch (e) {
      _errorMessage = e.toString();
      _status = RouteStatus.error;
    }

    notifyListeners();
  }

  void clear() {
    _status = RouteStatus.idle;
    _result = null;
    _errorMessage = null;
    notifyListeners();
  }
}
