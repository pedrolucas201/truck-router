import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/bridge_restriction.dart';
import '../models/route_result.dart';
import '../models/truck_profile.dart';
import '../models/weather_alert.dart';
import '../repositories/restriction_repository.dart';
import '../services/field_log.dart';
import '../services/here_routing_service.dart';
import '../services/physical_restriction_service.dart';
import '../services/radar_service.dart';
import '../services/tomtom_routing_service.dart';
import '../services/weather_service.dart';

enum RouteStatus { idle, loading, success, error }

class RouteProvider extends ChangeNotifier {
  final RestrictionRepository _repo;
  RouteProvider(this._repo);

  RouteStatus _status = RouteStatus.idle;
  RouteResult? _result;
  String? _errorMessage;
  List<WeatherAlert> _weatherAlerts = const [];

  RouteStatus get status => _status;
  RouteResult? get result => _result;
  String? get errorMessage => _errorMessage;
  // Células de clima severo na rota. Chegam DEPOIS da rota (busca async), então a
  // UI pode renderizar a rota primeiro e os avisos aparecem quando prontos.
  List<WeatherAlert> get weatherAlerts => _weatherAlerts;

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
    _weatherAlerts = const [];
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

      // 2. Asset offline (base) + backend (o que o asset não tem) em paralelo.
      final assetFuture =
          PhysicalRestrictionService.queryAlongRoute(result.polylinePoints);
      final firestoreFuture =
          _repo.fetchNearRoute(result.polylinePoints);
      final assetRestrictions = await assetFuture;
      final firestoreRestrictions = await firestoreFuture;

      final conflicts = [
        ...assetRestrictions,
        ...firestoreRestrictions,
      ].where((r) => r.conflictsWith(truck)).toList();

      // 3. Recalcula evitando as restrições encontradas + as marcadas na mão.
      if (conflicts.isNotEmpty) {
        // O cap vale só pro que cabe na URL da HERE. `conflicts` segue INTEIRO
        // daqui pra baixo: o que não coube no avoid continua na rota e tem que
        // cair em stillBlocked — senão um limite de API vira alerta suprimido.
        final paraEvitar = capAvoidAreas(conflicts, result.polylinePoints,
            reservado: manualAvoidAreas.length);
        final avoidAreas = [
          ...manualAvoidAreas,
          ...paraEvitar.map((r) => r.toAvoidArea()),
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

      // 5. Rota com terra: oferece escolha se economizar ≥5min E ≥20% do tempo.
      final dirtResult = await dirtRoadFuture;
      if (dirtResult != null &&
          offersDirtAlternative(
              result.durationSeconds, dirtResult.durationSeconds)) {
        // Cego total até aqui: nunca soubemos se este gate abriu em campo.
        // 1x por cálculo de rota, fora do hot path.
        FieldLog.event('dirt_offered', {
          'savingS': result.durationSeconds - dirtResult.durationSeconds,
          'durS': result.durationSeconds,
        });
        result = result.copyWith(dirtRoadAlternative: dirtResult);
      }

      _result = result;
      _status = RouteStatus.success;
      // Clima na rota: fire-and-forget. Não bloqueia o success — a rota já vai
      // pra tela; os avisos entram quando o backend responde (ou nunca, em falha).
      _fetchWeather(result, departureTime ?? DateTime.now());
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
    _weatherAlerts = const [];
    notifyListeners();
  }

  // Busca o clima da rota e publica os avisos. Guarda de corrida: se a rota mudou
  // enquanto buscava (novo cálculo/clear), descarta — senão avisos de uma rota
  // antiga apareceriam sobre a nova.
  Future<void> _fetchWeather(RouteResult forRoute, DateTime departure) async {
    final alerts = await WeatherService.forecastAlongRoute(
      polyline: forRoute.polylinePoints,
      departure: departure,
      durationSeconds: forRoute.durationSeconds,
    );
    if (alerts.isEmpty || !identical(_result, forRoute)) return;
    _weatherAlerts = alerts;
    notifyListeners();
  }

  /// Gate da alternativa por terra: economia ≥5min E ≥20% da rota pavimentada.
  /// O piso era 15min e tornava viagem curta matematicamente impossível: abaixo
  /// de 75min os 15min já são >20%, então uma viagem de 30min exigia economizar
  /// 50%. Com 5min, os 20% mandam a partir de 25min de viagem; acima de 75min
  /// nada muda (3h continua exigindo 36min).
  @visibleForTesting
  static bool offersDirtAlternative(int pavedSeconds, int dirtSeconds) {
    final saving = pavedSeconds - dirtSeconds;
    return saving >= 5 * 60 && saving >= pavedSeconds * 0.20;
  }

  /// Teto de áreas no `avoid[areas]` da HERE. Medido em 2026-07-22 contra o
  /// backend real: 150 áreas passam (URL de 7.590 chars), 155 devolvem 431 no
  /// nosso Cloud Run e 160+ devolvem 414 na HERE. O limite é o TAMANHO da URL
  /// (~7,7 KB), não a contagem — por isso 100, com folga, e não colado no teto.
  static const _maxAvoidAreas = 100;

  /// Corta o excesso mantendo as restrições que o caminhão encontra PRIMEIRO.
  /// As cortadas não somem para sempre: cada reroute refaz esta janela, então
  /// entram conforme ele se aproxima.
  @visibleForTesting
  static List<BridgeRestriction> capAvoidAreas(
    List<BridgeRestriction> conflicts,
    List<LatLng> polyline, {
    int reservado = 0,
  }) {
    final teto = _maxAvoidAreas - reservado;
    if (teto <= 0) return const [];
    if (conflicts.length <= teto) return conflicts;
    if (polyline.isEmpty) return conflicts.take(teto).toList();

    final start = polyline.first;
    double dist(BridgeRestriction r) => RadarService.haversine(
        start.latitude, start.longitude, r.lat, r.lng);
    // Cópia: quem chama continua com a lista original e na ordem original — ela
    // ainda é usada pra classificar avoided/blocked depois do reroute.
    final porProximidade = [...conflicts];
    // ponytail: ordena pela distância em linha reta até o início da rota, não pela
    // posição ao longo dela — numa rota que faz volta a ordem sai imprecisa. Só
    // pesa acima de 100 conflitos, e o reroute refaz a janela durante a viagem.
    // Se um dia isso importar, o índice do segmento mais próximo é a versão exata.
    porProximidade.sort((a, b) => dist(a).compareTo(dist(b)));
    FieldLog.event('avoid_cap', {'total': conflicts.length, 'usados': teto});
    return porProximidade.take(teto).toList();
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
