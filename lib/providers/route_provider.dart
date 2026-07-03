import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/bridge_restriction.dart';
import '../models/route_result.dart';
import '../models/truck_profile.dart';
import '../repositories/restriction_repository.dart';
import '../services/field_log.dart';
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
        } catch (e, st) {
          FieldLog.error('route_tomtom', e, st);
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
        } catch (e, st) {
          FieldLog.error('route_dirt', e, st);
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
          // Valida se o desvio funcionou: HERE pode ignorar o avoid[areas]
          // se não houver rota alternativa, retornando a rota original sem erro.
          final reallyAvoided = <BridgeRestriction>[];
          final stillBlocked  = <BridgeRestriction>[];
          for (final r in conflicts) {
            (_isOnRoute(r, rerouted.polylinePoints) ? stillBlocked : reallyAvoided).add(r);
          }
          result = rerouted.copyWith(
            restrictionsAvoided: reallyAvoided,
            restrictionsBlocked: stillBlocked,
          );
        } catch (e, st) {
          // HERE não encontrou rota alternativa — usa a original e avisa.
          // Loga: "desvio falhou" é diferente de "não havia conflito".
          FieldLog.error('route_reroute_avoid', e, st);
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
          // speedLimits/trafficSpans NÃO herdados: são offsets da polyline HERE,
          // que não batem com a geometria (outra) da TomTom.
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
    } catch (e, st) {
      // Captura-mãe do cálculo. É a queixa mais provável ("não calculou a rota");
      // sem isto o motorista vê o erro na tela e nós não temos nada. Coords no
      // 'where' pra repro.
      FieldLog.error(
          'route_calc from=${origin.latitude},${origin.longitude}'
          ' to=${destination.latitude},${destination.longitude}',
          e, st);
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

  // Retorna true se a restrição cai dentro de ~50m de qualquer ponto da polyline.
  // Usa aproximação plana — válida para distâncias pequenas na latitude do Brasil.
  static bool _isOnRoute(BridgeRestriction r, List<LatLng> points) {
    const thresholdSq = 50.0 * 50.0;
    final cosLat = cos(r.lat * pi / 180);
    for (final p in points) {
      final dy = (r.lat - p.latitude)  * 111320;
      final dx = (r.lng - p.longitude) * 111320 * cosLat;
      if (dx * dx + dy * dy <= thresholdSq) return true;
    }
    return false;
  }
}
