import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/route_result.dart';
import '../models/truck_profile.dart';
import '../repositories/restriction_repository.dart';
import '../services/here_routing_service.dart';
import '../services/overpass_service.dart';
import '../services/tomtom_routing_service.dart';

enum RouteStatus { idle, loading, success, error }

class RouteProvider extends ChangeNotifier {
  final RestrictionRepository _repo;
  RouteProvider(this._repo);

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

      // TomTom e rota sem filtro de terra rodam em paralelo desde o início.
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

      // Rota B (sem evitar terra) para comparação de threshold.
      final dirtRoadFuture = () async {
        try {
          return await HereRoutingService.calculateRoute(
            origin:        origin,
            destination:   destination,
            truck:         truck,
            departureTime: deptTime,
            waypoints:     waypoints,
            avoidAreas:    manualAvoidAreas,
            avoidDirtRoad: false,
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
          _repo.fetchNearRoute(result.polylinePoints);
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
          // restrictionsBlocked zerado: enrichment rodou sobre a polyline HERE,
          // não sobre a TomTom — herdar geraria alertas de proximidade errados.
        );
      }

      // 5. Rota com terra: oferece escolha se economizar ≥15min E ≥20% do tempo.
      final dirtResult = await dirtRoadFuture;
      if (dirtResult != null) {
        final saving = result.durationSeconds - dirtResult.durationSeconds;
        if (saving >= 15 * 60 && saving >= result.durationSeconds * 0.20) {
          result = result.copyWith(dirtRoadAlternative: dirtResult);
        }
      }

      _result = result;
      _status = RouteStatus.success;
    } catch (e) {
      _errorMessage = e.toString();
      _status = RouteStatus.error;
    }

    notifyListeners();
  }

  void useDirtRoadRoute() {
    if (_result?.dirtRoadAlternative == null) return;
    _result = _result!.dirtRoadAlternative!.copyWith(
      restrictionsAvoided: _result!.restrictionsAvoided,
      // restrictionsBlocked zerado: rota de terra tem polyline diferente da pavimentada.
    );
    notifyListeners();
  }

  void clear() {
    _status = RouteStatus.idle;
    _result = null;
    _errorMessage = null;
    notifyListeners();
  }
}
