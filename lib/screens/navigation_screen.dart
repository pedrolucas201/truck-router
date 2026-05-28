import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/bridge_restriction.dart';
import '../models/radar_point.dart';
import '../models/route_maneuver.dart';
import '../models/route_result.dart';
import '../models/truck_profile.dart';
import '../models/user_restriction.dart';
import '../repositories/restriction_repository.dart';
import '../services/auth_service.dart';
import '../services/here_routing_service.dart';
import '../services/radar_service.dart';
import '../services/restriction_service.dart';
import '../widgets/add_restriction_sheet.dart';
import '../widgets/crosshair.dart';

@pragma('vm:entry-point')
void _navForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_NavTaskHandler());
}

class _NavTaskHandler extends TaskHandler {
  @override Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override void onRepeatEvent(DateTime timestamp) {}
  @override Future<void> onDestroy(DateTime timestamp) async {}
}

enum AudioLevel { completo, essencial, silencioso }

enum ZoomLevel { recuado, medio, aproximado }

class NavigationScreen extends StatefulWidget {
  final RouteResult result;
  final LatLng destination;
  final TruckProfile truck;
  final String destinationLabel;
  final List<LatLng> waypoints;
  final List<RadarPoint> initialRadares;

  const NavigationScreen({
    super.key,
    required this.result,
    required this.destination,
    required this.truck,
    required this.destinationLabel,
    this.waypoints = const [],
    this.initialRadares = const [],
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _posSub;
  late final FlutterTts _tts;

  late RouteResult _result;
  List<RadarPoint> _radares = [];
  List<RadarPoint> _visibleRadares = [];

  LatLng? _currentPos;
  double _bearing = 0;
  double _speedKmh = 0;
  int _closestPolylineIdx = 0;
  int _maneuverIndex = 0;
  double _distToNextManeuver = double.infinity;
  AudioLevel _audioLevel = AudioLevel.completo;
  ZoomLevel _zoomLevel = ZoomLevel.medio;
  bool _isRerouting = false;
  Timer? _refreshTimer;
  int _offRouteCount = 0;
  RadarPoint? _upcomingRadar;
  final Set<int> _announced = {};

  // Cache de ícones para radares
  final _iconCache = <String, BitmapDescriptor>{};

  final List<UserRestriction> _userRestrictions = [];
  final _restrictionIconCache = <String, BitmapDescriptor>{};

  bool _markingMode = false;
  bool _paused = false;
  final Set<String> _actionedRestrictions = {};
  LatLng? _snappedPos;
  bool _hasFirstFix = false;
  LatLng _cameraTarget = const LatLng(-15.788, -47.879);
  BitmapDescriptor? _userArrowIcon;

  BridgeRestriction? _nearbyBlockedRestriction;
  String? _lastRestrictionAlertKey;
  String? _lastRadarAlertKey;
  DateTime? _resumedAt;
  bool _hasTimeRestrictionAlert  = false;
  bool _timeRestrictionAlertSpoken = false;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  static const _offRouteThresholdM  = 80.0;
  static const _offRouteCountLimit  = 4;
  static const _radarAlertM         = 400.0;
  static const _restrictionAlertM   = 300.0;
  static const _radarLookAheadM     = 1500.0;
  static const _radarCorridorM      = 100.0;
  static const _prefAudioLevel = 'nav_audio_level';
  static const _prefZoomLevel  = 'nav_zoom_level';

  @override
  void initState() {
    super.initState();
    _result  = widget.result;
    _radares        = List.of(widget.initialRadares);
    _visibleRadares = List.of(widget.initialRadares);
    _hasTimeRestrictionAlert = widget.result.hasTimeRestriction;
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseAnimation = Tween<double>(begin: 0.12, end: 0.48)
        .animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _loadAudioLevel();
    _loadZoomLevel();
    _loadUserRestrictions();
    _startForegroundService();
    _initTts();
    _startGps();
    _refreshTimer = Timer.periodic(const Duration(minutes: 10), (_) => _periodicRefresh());
    WakelockPlus.enable();
    _buildUserArrow().then((icon) {
      if (mounted) setState(() => _userArrowIcon = icon);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _posSub?.cancel();
    _tts.stop();
    _pulseController.dispose();
    FlutterForegroundTask.stopService();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _resumedAt = DateTime.now();
    // moveCamera (instantâneo) evita giros: animateCamera competia com
    // os primeiros updates de GPS no resume e causava rotações bruscas.
    if (!_markingMode && _mapController != null) {
      final pos = _snappedPos ?? _currentPos;
      if (pos != null) {
        _mapController!.moveCamera(
          CameraUpdate.newCameraPosition(CameraPosition(
            target:  pos,
            zoom:    _zoom,
            tilt:    45,
            bearing: _bearing,
          )),
        );
      }
    }
    // Trava as chaves de alerta para o próximo GPS update não reanunciar
    // o radar/restrição que já estava ativo antes de sair do app.
    if (_upcomingRadar != null) {
      _lastRadarAlertKey = '${_upcomingRadar!.lat}_${_upcomingRadar!.lng}';
    }
    if (_nearbyBlockedRestriction != null) {
      _lastRestrictionAlertKey =
          '${_nearbyBlockedRestriction!.lat}_${_nearbyBlockedRestriction!.lng}';
    }
    if (!_hasFirstFix) return;
    if (_audioLevel == AudioLevel.silencioso) return;
    final maneuvers = _result.maneuvers;
    if (_maneuverIndex >= maneuvers.length) return;
    final m = maneuvers[_maneuverIndex];
    if (m.action == 'depart' || m.action == 'arrive') return;
    final dist = _distToNextManeuver;
    final text = dist.isFinite && dist < 50000
        ? 'Em ${_fmtDist(dist)}, ${m.instruction}'
        : m.instruction;
    _speak(text);
    // Marca os thresholds já anunciados para _checkTts não repetir no próximo GPS update.
    final idx = _maneuverIndex;
    _announced.add(idx * 10 + 0);
    if (dist.isFinite && dist <= 200) _announced.add(idx * 10 + 1);
    if (dist.isFinite && dist <= 50)  _announced.add(idx * 10 + 2);
  }

  // ── TTS ──────────────────────────────────────────────────────────────────────

  void _initTts() {
    _tts = FlutterTts();
    _tts.setLanguage('pt-BR');
    _tts.setSpeechRate(0.9);
    _tts.setVolume(1.0);
  }

  Future<void> _startForegroundService() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'nav_service',
        channelName: 'Navegação ativa',
        channelDescription: 'GPS ativo em segundo plano',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWifiLock: false,
      ),
    );
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'Navegando',
      notificationText: widget.destinationLabel.isNotEmpty
          ? 'Destino: ${widget.destinationLabel}'
          : 'GPS ativo',
      callback: _navForegroundCallback,
    );
  }

  Future<void> _loadAudioLevel() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_prefAudioLevel) ?? 0;
    if (mounted) setState(() => _audioLevel = AudioLevel.values[idx.clamp(0, 2)]);
  }

  Future<void> _saveAudioLevel(AudioLevel level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefAudioLevel, level.index);
  }

  void _cycleAudioLevel() {
    final next = AudioLevel.values[(_audioLevel.index + 1) % AudioLevel.values.length];
    setState(() => _audioLevel = next);
    _saveAudioLevel(next);
  }

  Future<void> _loadZoomLevel() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_prefZoomLevel) ?? 1;
    if (mounted) setState(() => _zoomLevel = ZoomLevel.values[idx.clamp(0, 2)]);
  }

  Future<void> _saveZoomLevel(ZoomLevel level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefZoomLevel, level.index);
  }

  void _cycleZoomLevel() {
    final next = ZoomLevel.values[(_zoomLevel.index + 1) % ZoomLevel.values.length];
    setState(() => _zoomLevel = next);
    _saveZoomLevel(next);
    _recenter();
  }

  double get _zoom => switch (_zoomLevel) {
    ZoomLevel.recuado    => 15.0,
    ZoomLevel.medio      => 17.0,
    ZoomLevel.aproximado => 19.0,
  };

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_paused) {
      _tts.stop();
    } else {
      _resumedAt = DateTime.now();
      _recenter();
    }
  }

  void _speak(String text) {
    if (_paused) return;
    if (_audioLevel == AudioLevel.silencioso) return;
    if (_resumedAt != null &&
        DateTime.now().difference(_resumedAt!).inMilliseconds < 4000) { return; }
    _tts.speak(text);
  }

  // ── GPS ──────────────────────────────────────────────────────────────────────

  void _startGps() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );
    _posSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPositionUpdate);
  }

  void _onPositionUpdate(Position pos) {
    if (!mounted) return;
    final firstFix = !_hasFirstFix;
    _hasFirstFix = true;
    if (firstFix && _hasTimeRestrictionAlert && !_timeRestrictionAlertSpoken) {
      _timeRestrictionAlertSpoken = true;
      _speak('Atenção! Restrição para caminhões nesta via');
      _updatePulse();
    }
    final latLng = LatLng(pos.latitude, pos.longitude);

    if (_paused) {
      final pts2 = _result.polylinePoints;
      final s2 = (_closestPolylineIdx - 5).clamp(0, pts2.length - 1);
      var bi2 = _closestPolylineIdx;
      var bd2 = double.infinity;
      for (var i = s2; i < min(s2 + 200, pts2.length); i++) {
        final d = RadarService.haversine(
            latLng.latitude, latLng.longitude, pts2[i].latitude, pts2[i].longitude);
        if (d < bd2) { bd2 = d; bi2 = i; }
      }
      setState(() {
        _currentPos = latLng;
        _snappedPos = pts2.isNotEmpty ? pts2[bi2] : latLng;
        _bearing    = pos.heading;
        _speedKmh   = (pos.speed * 3.6).clamp(0, 300);
      });
      return;
    }

    // 1. Ponto mais próximo na polyline (busca a partir do índice atual)
    final pts  = _result.polylinePoints;
    final start = (_closestPolylineIdx - 5).clamp(0, pts.length - 1);
    var bestIdx  = _closestPolylineIdx;
    var bestDist = double.infinity;
    final end = min(start + 200, pts.length);
    for (var i = start; i < end; i++) {
      final d = RadarService.haversine(
        latLng.latitude, latLng.longitude,
        pts[i].latitude, pts[i].longitude,
      );
      if (d < bestDist) { bestDist = d; bestIdx = i; }
    }

    // 2. Desvio de rota
    if (bestDist > _offRouteThresholdM) {
      _offRouteCount++;
      if (_offRouteCount >= _offRouteCountLimit) _reroute(latLng);
    } else {
      _offRouteCount = 0;
    }

    // 3. Manobra atual
    final maneuvers = _result.maneuvers;
    var mIdx = 0;
    for (var i = 0; i < maneuvers.length; i++) {
      if (maneuvers[i].polylineOffset <= bestIdx) mIdx = i;
    }
    // Avança se já passou desta manobra
    final nextIdx = (mIdx + 1 < maneuvers.length) ? mIdx + 1 : mIdx;
    final nextManeuver = maneuvers.isNotEmpty ? maneuvers[nextIdx] : null;

    double distToNext = double.infinity;
    if (nextManeuver != null) {
      distToNext = RadarService.haversine(
        latLng.latitude, latLng.longitude,
        nextManeuver.position.latitude, nextManeuver.position.longitude,
      );
      _checkTts(nextIdx, distToNext, nextManeuver);
    }

    // 4. Radar à frente
    RadarPoint? upcoming;
    for (final r in _radares) {
      final d = RadarService.haversine(latLng.latitude, latLng.longitude, r.lat, r.lng);
      if (d < _radarAlertM) {
        if (upcoming == null ||
            d < RadarService.haversine(latLng.latitude, latLng.longitude, upcoming.lat, upcoming.lng)) {
          upcoming = r;
        }
      }
    }

    // 5. Restrição bloqueada à frente
    final userBlocked = _userRestrictions
        .map((r) => r.toBridgeRestriction())
        .where((b) => b.conflictsWith(widget.truck));
    BridgeRestriction? nearestBlocked;
    double nearestBlockedDist = double.infinity;
    for (final b in [..._result.restrictionsBlocked, ...userBlocked]) {
      final d = RadarService.haversine(latLng.latitude, latLng.longitude, b.lat, b.lng);
      if (d < _restrictionAlertM && d < nearestBlockedDist) {
        nearestBlockedDist = d;
        nearestBlocked = b;
      }
    }

    // 6. Radares visíveis: próximos 1500m da polyline com corredor de 100m
    final aheadPts = <LatLng>[];
    for (var i = bestIdx; i < pts.length; i++) {
      if (RadarService.haversine(latLng.latitude, latLng.longitude,
              pts[i].latitude, pts[i].longitude) > _radarLookAheadM) { break; }
      aheadPts.add(pts[i]);
    }
    final visibleRadares = _radares.where((r) => aheadPts.any((p) =>
        RadarService.haversine(r.lat, r.lng, p.latitude, p.longitude) <=
            _radarCorridorM)).toList();

    setState(() {
      _currentPos                 = latLng;
      _snappedPos                 = pts.isNotEmpty ? pts[bestIdx] : latLng;
      _bearing                    = pos.heading;
      _speedKmh                   = (pos.speed * 3.6).clamp(0, 300);
      _closestPolylineIdx         = bestIdx;
      _maneuverIndex              = nextIdx;
      _distToNextManeuver         = distToNext;
      _upcomingRadar              = upcoming;
      _nearbyBlockedRestriction   = nearestBlocked;
      _visibleRadares             = visibleRadares;
    });
    _updateRestrictionAlert(nearestBlocked, nearestBlockedDist);
    _updateRadarAlert(upcoming);

    // 7. Câmera segue o usuário (pausada no modo crosshair)
    // Usa pts[bestIdx] (snapped) em vez do GPS bruto — evita que a seta
    // apareça fora da via no zoom aproximado por drift de GPS.
    if (!_markingMode) {
      final camTarget = pts.isNotEmpty ? pts[bestIdx] : latLng;
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(
          target:  camTarget,
          zoom:    _zoom,
          tilt:    45,
          bearing: pos.heading,
        )),
      );
    }
  }

  // ── TTS por threshold de distância ───────────────────────────────────────────

  void _checkTts(int idx, double distM, RouteManeuver m) {
    if (m.action == 'depart' || m.action == 'arrive') return;
    final k500 = idx * 10 + 0;
    final k200 = idx * 10 + 1;
    final k50  = idx * 10 + 2;

    // Classificação por relevância de voz:
    // isTurn    — curva / rotatória → aviso completo
    // isExit    — saída de rodovia / rampa → aviso intermediário
    // else      — continue/keep/straight → sem voz (só visual)
    final isTurn = m.action == 'turn' || m.action == 'roundaboutExit';
    final isExit = m.action == 'exit'  || m.action == 'ramp' ||
                   m.action == 'keepLeft' || m.action == 'keepRight';

    if (isTurn) {
      // 500m só no nível completo
      if (_audioLevel == AudioLevel.completo && distM <= 500 && !_announced.contains(k500)) {
        _announced.add(k500);
        _speak('Em 500 metros, ${m.instruction}');
      } else if (distM <= 200 && !_announced.contains(k200)) {
        _announced.add(k200);
        _announced.add(k500);
        _speak('Em 200 metros, ${m.instruction}');
      } else if (distM <= 50 && !_announced.contains(k50)) {
        _announced.add(k50);
        _announced.add(k200);
        _announced.add(k500);
        _speak(m.instruction);
      }
    } else if (isExit) {
      // Saídas: 200m no completo, 50m em ambos
      if (_audioLevel == AudioLevel.completo && distM <= 200 && !_announced.contains(k200)) {
        _announced.add(k200);
        _announced.add(k500);
        _speak('Em 200 metros, ${m.instruction}');
      } else if (distM <= 50 && !_announced.contains(k50)) {
        _announced.add(k50);
        _announced.add(k200);
        _announced.add(k500);
        _speak(m.instruction);
      }
    }
    // continue/keep/straight: silêncio total — só aparece na _InstructionBar
  }

  // ── Alerta de restrição bloqueada ────────────────────────────────────────────

  void _updatePulse() {
    final active = _nearbyBlockedRestriction != null || _hasTimeRestrictionAlert;
    if (active) {
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  void _updateRestrictionAlert(BridgeRestriction? restriction, double dist) {
    final key = restriction != null ? '${restriction.lat}_${restriction.lng}' : null;
    if (key == _lastRestrictionAlertKey) return;
    _lastRestrictionAlertKey = key;
    if (restriction != null) {
      _speak('Atenção! ${restriction.label} a ${dist.round()} metros à frente');
    }
    _updatePulse();
  }

  Future<void> _confirmRestriction(String id) async {
    setState(() => _actionedRestrictions.add(id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Restrição confirmada. Obrigado!'),
      duration: Duration(seconds: 2),
    ));
    try { await context.read<RestrictionRepository>().confirm(id); } catch (_) {}
  }

  Future<void> _reportRestriction(String id) async {
    setState(() => _actionedRestrictions.add(id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Restrição reportada como incorreta.'),
      duration: Duration(seconds: 2),
    ));
    try { await context.read<RestrictionRepository>().report(id); } catch (_) {}
  }

  void _updateRadarAlert(RadarPoint? radar) {
    final key = radar != null ? '${radar.lat}_${radar.lng}' : null;
    if (key == _lastRadarAlertKey) return;
    _lastRadarAlertKey = key;
    if (radar == null) return;
    final isLombada = radar.type.toLowerCase().contains('lombada');
    final isPedagio = radar.type.toLowerCase().contains('pedagio');
    if (isLombada) {
      _speak('Lombada à frente');
    } else if (isPedagio) {
      _speak('Pedágio à frente');
    } else {
      final speed = radar.speedKmh > 0 ? ', ${radar.speedKmh} quilômetros por hora' : '';
      _speak('Radar à frente$speed');
    }
  }

  // ── Re-roteamento ─────────────────────────────────────────────────────────────

  Future<void> _periodicRefresh() async {
    if (_isRerouting || _paused || _currentPos == null) return;
    await _reroute();
  }

  Future<void> _reroute([LatLng? fromPos]) async {
    final origin = fromPos ?? _currentPos;
    if (_isRerouting || origin == null) return;
    setState(() { _isRerouting = true; _offRouteCount = 0; });
    try {
      final prevDistM = _result.distanceMeters;
      final repo = context.read<RestrictionRepository>();

      final manualAvoidAreas = [
        ..._userRestrictions
            .where((r) => r.toBridgeRestriction().conflictsWith(widget.truck))
            .map((r) => r.toBridgeRestriction().toAvoidArea()),
        ..._result.restrictionsAvoided.map((r) => r.toAvoidArea()),
      ];

      var newResult = await HereRoutingService.calculateRoute(
        origin:      origin,
        destination: widget.destination,
        truck:       widget.truck,
        waypoints:   widget.waypoints,
        avoidAreas:  manualAvoidAreas,
      );

      // Enrichment Firestore — mantém alertas crowd-sourced vivos após recálculo.
      final firestoreRestrictions = await repo.fetchNearRoute(newResult.polylinePoints);
      final conflicts = firestoreRestrictions
          .where((r) => r.conflictsWith(widget.truck))
          .toList();
      if (conflicts.isNotEmpty) {
        newResult = newResult.copyWith(restrictionsBlocked: conflicts);
      }

      final allRadares = await RadarService.load();
      final nearby = RadarService.deduplicateNearby(
        RadarService.filterNearRoute(allRadares, newResult.polylinePoints),
      ).where((r) => !(r.type.toLowerCase().contains('lombada') && r.speedKmh == 0)).toList();
      if (!mounted) return;
      setState(() {
        _result                  = newResult;
        _radares                 = nearby;
        _closestPolylineIdx      = 0;
        _maneuverIndex           = 0;
        _distToNextManeuver      = double.infinity;
        _hasTimeRestrictionAlert = newResult.hasTimeRestriction;
        _announced.clear();
        _iconCache.clear();
      });
      if (newResult.hasTimeRestriction && !_timeRestrictionAlertSpoken) {
        _timeRestrictionAlertSpoken = true;
        _speak('Atenção! Restrição para caminhões nesta via');
      } else if (!newResult.hasTimeRestriction) {
        _timeRestrictionAlertSpoken = false;
      }
      _updatePulse();
      // Só anuncia se nível completo e rota mudou significativamente (>500m)
      if (_audioLevel == AudioLevel.completo &&
          (newResult.distanceMeters - prevDistM).abs() > 500) {
        _speak('Rota recalculada');
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isRerouting = false);
    }
  }

  // ── Distância restante ────────────────────────────────────────────────────────

  double _remainingDistanceM() {
    final pts = _result.polylinePoints;
    if (pts.length < 2) return 0;
    double total = 0;
    for (var i = _closestPolylineIdx; i < pts.length - 1; i++) {
      total += RadarService.haversine(
        pts[i].latitude, pts[i].longitude,
        pts[i + 1].latitude, pts[i + 1].longitude,
      );
    }
    return total;
  }

  // ── Formatação ────────────────────────────────────────────────────────────────

  String _fmtDist(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
    return '${m.round()} m';
  }

  String _fmtEta(int seconds) {
    final eta = DateTime.now().add(Duration(seconds: seconds));
    return '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';
  }

  // ── Ícone de direção ─────────────────────────────────────────────────────────

  IconData _dirIcon(RouteManeuver m) {
    return switch (m.action) {
      'depart'         => Icons.navigation,
      'arrive'         => Icons.flag,
      'roundaboutExit' => Icons.roundabout_right,
      'turn' when m.direction == 'left'          => Icons.turn_left,
      'turn' when m.direction == 'right'         => Icons.turn_right,
      'turn' when m.direction == 'slightlyLeft'  => Icons.turn_slight_left,
      'turn' when m.direction == 'slightlyRight' => Icons.turn_slight_right,
      'turn' when m.direction == 'uTurnLeft'     => Icons.u_turn_left,
      'turn' when m.direction == 'uTurnRight'    => Icons.u_turn_right,
      _                => Icons.straight,
    };
  }

  // ── Ícone de radar (bitmap) ───────────────────────────────────────────────────

  Future<BitmapDescriptor> _radarIcon(RadarPoint r) async {
    final isLombada = r.type.toLowerCase().contains('lombada');
    final isPedagio = r.type.toLowerCase().contains('pedagio');
    final key = isPedagio ? 'p' : '${isLombada ? 'l' : 'r'}_${r.speedKmh}';
    if (_iconCache.containsKey(key)) return _iconCache[key]!;

    const size = 40.0;
    final bgColor = isPedagio
        ? Colors.blue.shade700
        : isLombada
            ? Colors.orange.shade700
            : Colors.red.shade700;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2, Paint()..color = bgColor);
    canvas.drawCircle(
      const Offset(size / 2, size / 2), size / 2 - 3.0,
      Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3.0,
    );
    final IconData displayIcon = isPedagio
        ? Icons.toll
        : (r.speedKmh == 0 ? Icons.camera_alt : Icons.circle);
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: (!isPedagio && r.speedKmh > 0)
            ? r.speedKmh.toString()
            : String.fromCharCode(displayIcon.codePoint),
        style: (!isPedagio && r.speedKmh > 0)
            ? TextStyle(
                fontSize: r.speedKmh >= 100 ? 13.0 : 16.0,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              )
            : TextStyle(
                fontSize: 22,
                fontFamily: displayIcon.fontFamily,
                color: Colors.white,
              ),
      )
      ..layout();
    tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));
    final img   = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final icon  = BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
    _iconCache[key] = icon;
    return icon;
  }

  // ── Seta do usuário (Waze-style) ─────────────────────────────────────────────

  static Future<BitmapDescriptor> _buildUserArrow() async {
    const size = 48.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final path = Path()
      ..moveTo(size / 2, 2)           // ponta superior (frente)
      ..lineTo(size - 4, size - 6)    // canto direito
      ..lineTo(size / 2, size * 0.60) // entalhe central
      ..lineTo(4, size - 6)           // canto esquerdo
      ..close();

    // Outline branco
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.round,
    );
    // Preenchimento azul
    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFF1565C0),
    );

    final img   = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  // ── Centralizar câmera ────────────────────────────────────────────────────────

  void _recenter() {
    final pos = _snappedPos ?? _currentPos;
    if (pos == null || _mapController == null) return;
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(
        target:  pos,
        zoom:    _zoom,
        tilt:    45,
        bearing: _bearing,
      )),
    );
  }

  // ── Ícone de restrição (badge colorido) ──────────────────────────────────────

  static Future<BitmapDescriptor> _buildRestrictionIcon(UserRestriction r) async {
    const iconH = 20.0;
    final bgColor = switch (r.type) {
      'maxheight' => Colors.red.shade700,
      'maxweight' => Colors.brown.shade600,
      'dirtroad'  => Colors.green.shade700,
      _           => Colors.deepOrange.shade600,
    };
    final text = switch (r.type) {
      'maxheight' => '${r.value.toStringAsFixed(1)}m',
      'maxweight' => '${r.value.toStringAsFixed(0)}t',
      'dirtroad'  => 'Terra',
      _           => '${r.value.toStringAsFixed(1)}m',
    };
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: text,
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
      )
      ..layout();
    final iconW = (tp.width + 14).ceilToDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, iconW, iconH), const Radius.circular(4)),
      Paint()..color = bgColor,
    );
    tp.paint(canvas, Offset(7, (iconH - tp.height) / 2));
    final picture = recorder.endRecording();
    final img = await picture.toImage(iconW.toInt(), iconH.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  // ── Marcar restrição — fluxo crosshair ───────────────────────────────────────

  void _enterMarkingMode() {
    final pos = _currentPos ?? widget.destination;
    _cameraTarget = pos;
    setState(() => _markingMode = true);
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(
        target: pos,
        zoom: 17,
        tilt: 0,
      )),
    );
  }

  void _exitMarkingMode() {
    setState(() => _markingMode = false);
    _recenter();
  }

  Future<void> _loadUserRestrictions() async {
    final restrictions = await RestrictionService.load();
    for (final r in restrictions) {
      final key = 'ur_${r.lat}_${r.lng}_${r.createdAt.millisecondsSinceEpoch}';
      if (!_restrictionIconCache.containsKey(key)) {
        _restrictionIconCache[key] = await _buildRestrictionIcon(r);
      }
    }
    if (mounted) setState(() => _userRestrictions.addAll(restrictions));
  }

  Future<void> _confirmMarkingPosition() async {
    final pos = _cameraTarget;
    setState(() => _markingMode = false);
    final repo = context.read<RestrictionRepository>();
    final r = await showModalBottomSheet<UserRestriction>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => AddRestrictionSheet(position: pos),
    );
    if (r == null || !mounted) { _recenter(); return; }
    await RestrictionService.add(r);
    () async {
      try {
        final uid = await AuthService.getUid();
        await repo.add(r, uid);
      } catch (_) {}
    }();
    final key = 'ur_${r.lat}_${r.lng}_${r.createdAt.millisecondsSinceEpoch}';
    final icon = await _buildRestrictionIcon(r);
    if (!mounted) return;
    _restrictionIconCache[key] = icon;
    setState(() => _userRestrictions.add(r));
    _recenter();
    if (_currentPos != null) await _reroute(_currentPos);
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final maneuvers = _result.maneuvers;
    final hasNext   = maneuvers.isNotEmpty && _maneuverIndex < maneuvers.length;
    final nextM     = hasNext ? maneuvers[_maneuverIndex] : null;

    final remaining = _remainingDistanceM();
    // Tempo restante proporcional à distância percorrida
    final totalM    = _result.distanceMeters;
    final fraction  = totalM > 0 ? (remaining / totalM).clamp(0.0, 1.0) : 0.0;
    final remSec    = (_result.durationSeconds * fraction).round();

    final pts = _result.polylinePoints;
    final splitIdx = _closestPolylineIdx.clamp(0, pts.length - 1);
    final polylines = <Polyline>{
      if (splitIdx >= 1)
        Polyline(
          polylineId: const PolylineId('nav_traveled'),
          points: pts.sublist(0, splitIdx + 1),
          color: Colors.blueGrey.shade300,
          width: 5,
        ),
      if (splitIdx < pts.length - 1)
        Polyline(
          polylineId: const PolylineId('nav_remaining'),
          points: pts.sublist(splitIdx),
          color: const Color(0xFF1565C0),
          width: 7,
        ),
    };

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('destination'),
        position: widget.destination,
        infoWindow: InfoWindow(title: 'Destino', snippet: widget.destinationLabel),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      if (_currentPos != null)
        Marker(
          markerId: const MarkerId('user'),
          position: _snappedPos ?? _currentPos!,
          icon: _userArrowIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          flat: true,
          rotation: _bearing,
          anchor: const Offset(0.5, 0.65),
        ),
    };

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Barra de instrução ──────────────────────────────────────────
            _InstructionBar(
              maneuver:     nextM,
              distance:     _distToNextManeuver,
              dirIcon:      nextM != null ? _dirIcon(nextM) : Icons.straight,
              audioLevel:   _audioLevel,
              rerouting:    _isRerouting,
              onAudioCycle: _cycleAudioLevel,
              onClose:      () => Navigator.of(context).pop(),
              fmtDist:      _fmtDist,
            ),

            // ── Mapa ────────────────────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  FutureBuilder<List<BitmapDescriptor>>(
                    future: Future.wait(_visibleRadares.map(_radarIcon)),
                    builder: (context, snap) {
                      if (snap.hasData) {
                        for (var i = 0; i < _visibleRadares.length; i++) {
                          markers.add(Marker(
                            markerId: MarkerId('r_${_visibleRadares[i].lat}_${_visibleRadares[i].lng}'),
                            position: LatLng(_visibleRadares[i].lat, _visibleRadares[i].lng),
                            icon: snap.data![i],
                            infoWindow: InfoWindow(
                              title: _visibleRadares[i].speedKmh > 0
                                  ? '${_visibleRadares[i].speedKmh} km/h'
                                  : _visibleRadares[i].type,
                              snippet: _visibleRadares[i].type,
                            ),
                          ));
                        }
                      }
                      for (final r in _userRestrictions) {
                        final key = 'ur_${r.lat}_${r.lng}_${r.createdAt.millisecondsSinceEpoch}';
                        final icon = _restrictionIconCache[key];
                        if (icon != null) {
                          markers.add(Marker(
                            markerId: MarkerId(key),
                            position: LatLng(r.lat, r.lng),
                            icon: icon,
                            infoWindow: InfoWindow(
                              title: switch (r.type) {
                                'maxheight' => 'Altura máx. ${r.value.toStringAsFixed(1)}m',
                                'maxweight' => 'Peso máx. ${r.value.toStringAsFixed(0)}t',
                                'dirtroad'  => 'Estrada de terra',
                                _           => 'Largura máx. ${r.value.toStringAsFixed(1)}m',
                              },
                            ),
                          ));
                        }
                      }
                      return GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _currentPos ?? widget.destination,
                          zoom: 17,
                          tilt: 45,
                        ),
                        onMapCreated: (c) => _mapController = c,
                        onCameraMove: (pos) => _cameraTarget = pos.target,
                        polylines: polylines,
                        markers: markers,
                        trafficEnabled: true,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        compassEnabled: false,
                      );
                    },
                  ),
                  // ── Alerta restrição bloqueada / horário ────────────────
                  if ((_nearbyBlockedRestriction != null || _hasTimeRestrictionAlert) && !_markingMode) ...[
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) => ColoredBox(
                            color: Colors.red.withValues(alpha: _pulseAnimation.value),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade800,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(color: Colors.black54, blurRadius: 8)
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _nearbyBlockedRestriction != null
                                      ? Icons.warning_amber_rounded
                                      : Icons.schedule,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _nearbyBlockedRestriction != null
                                        ? _nearbyBlockedRestriction!.label
                                        : 'Restrição para caminhões nesta via',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_nearbyBlockedRestriction?.id != null &&
                                !_actionedRestrictions.contains(
                                    _nearbyBlockedRestriction!.id)) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _confirmRestriction(
                                          _nearbyBlockedRestriction!.id!),
                                      icon: const Icon(Icons.check, size: 16),
                                      label: const Text('Confirmar'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: const BorderSide(
                                            color: Colors.white54),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 6),
                                        visualDensity: VisualDensity.compact,
                                        textStyle:
                                            const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _reportRestriction(
                                          _nearbyBlockedRestriction!.id!),
                                      icon: const Icon(Icons.close, size: 16),
                                      label: const Text('Não existe'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white70,
                                        side: const BorderSide(
                                            color: Colors.white30),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 6),
                                        visualDensity: VisualDensity.compact,
                                        textStyle:
                                            const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (!_markingMode) ...[
                    // Botão pausar/retomar
                    Positioned(
                      bottom: 168,
                      right: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'nav_pause',
                        backgroundColor: _paused ? Colors.amber.shade700 : Colors.white,
                        foregroundColor: _paused ? Colors.white : Colors.grey.shade800,
                        elevation: 4,
                        tooltip: _paused ? 'Retomar navegação' : 'Pausar navegação',
                        onPressed: _togglePause,
                        child: Icon(_paused ? Icons.play_arrow : Icons.pause),
                      ),
                    ),
                    // Botão zoom
                    Positioned(
                      bottom: 116,
                      right: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'nav_zoom',
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.grey.shade800,
                        elevation: 4,
                        tooltip: switch (_zoomLevel) {
                          ZoomLevel.recuado    => 'Zoom: Recuado',
                          ZoomLevel.medio      => 'Zoom: Médio',
                          ZoomLevel.aproximado => 'Zoom: Aproximado',
                        },
                        onPressed: _cycleZoomLevel,
                        child: Icon(switch (_zoomLevel) {
                          ZoomLevel.recuado    => Icons.zoom_out_map,
                          ZoomLevel.medio      => Icons.map_outlined,
                          ZoomLevel.aproximado => Icons.zoom_in_map,
                        }),
                      ),
                    ),
                    // Botão marcar restrição
                    Positioned(
                      bottom: 64,
                      right: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'nav_mark_restriction',
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.teal.shade700,
                        elevation: 4,
                        tooltip: 'Marcar restrição',
                        onPressed: _enterMarkingMode,
                        child: const Icon(Icons.add_location_alt),
                      ),
                    ),
                    // Botão centralizar
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'nav_recenter',
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1565C0),
                        elevation: 4,
                        onPressed: _recenter,
                        child: const Icon(Icons.my_location),
                      ),
                    ),
                  ],
                  if (_markingMode) ...[
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(color: Colors.black.withAlpha(25)),
                      ),
                    ),
                    Positioned(
                      top: 0, left: 0, right: 0,
                      child: SafeArea(
                        child: Center(
                          child: Container(
                            margin: const EdgeInsets.only(top: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Arraste o mapa até a restrição',
                              style: TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Center(
                      child: IgnorePointer(child: MapCrosshair()),
                    ),
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _exitMarkingMode,
                                  icon: const Icon(Icons.close),
                                  label: const Text('Cancelar'),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.grey.shade700,
                                    side: BorderSide(color: Colors.grey.shade300),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: FilledButton.icon(
                                  onPressed: _confirmMarkingPosition,
                                  icon: const Icon(Icons.check),
                                  label: const Text('Confirmar local'),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Barra inferior ──────────────────────────────────────────────
            _BottomBar(
              speedKmh:      _speedKmh,
              remainingDist: _fmtDist(remaining),
              eta:           _fmtEta(remSec),
              radarAlert:    _upcomingRadar,
            ),
          ],
        ),
      ),
    );
  }
}

// ── _InstructionBar ────────────────────────────────────────────────────────────

class _InstructionBar extends StatelessWidget {
  final RouteManeuver? maneuver;
  final double distance;
  final IconData dirIcon;
  final AudioLevel audioLevel;
  final bool rerouting;
  final VoidCallback onAudioCycle;
  final VoidCallback onClose;
  final String Function(double) fmtDist;

  const _InstructionBar({
    required this.maneuver,
    required this.distance,
    required this.dirIcon,
    required this.audioLevel,
    required this.rerouting,
    required this.onAudioCycle,
    required this.onClose,
    required this.fmtDist,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A237E),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Fechar
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: onClose,
            tooltip: 'Encerrar navegação',
          ),
          const SizedBox(width: 4),
          // Seta de direção
          Icon(dirIcon, color: Colors.white, size: 40),
          const SizedBox(width: 12),
          // Instrução + distância
          Expanded(
            child: rerouting
                ? const Row(
                    children: [
                      SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('Recalculando rota…',
                          style: TextStyle(color: Colors.white, fontSize: 15)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        maneuver?.instruction ?? '—',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (distance.isFinite && distance < 50000)
                        Text(
                          'Em ${fmtDist(distance)}',
                          style: TextStyle(color: Colors.blue.shade100, fontSize: 13),
                        ),
                    ],
                  ),
          ),
          // Nível de áudio
          IconButton(
            icon: Icon(
              switch (audioLevel) {
                AudioLevel.completo   => Icons.volume_up,
                AudioLevel.essencial  => Icons.volume_down,
                AudioLevel.silencioso => Icons.volume_off,
              },
              color: Colors.white,
            ),
            onPressed: onAudioCycle,
            tooltip: switch (audioLevel) {
              AudioLevel.completo   => 'Áudio: Completo',
              AudioLevel.essencial  => 'Áudio: Essencial',
              AudioLevel.silencioso => 'Áudio: Silencioso',
            },
          ),
        ],
      ),
    );
  }
}

// ── _BottomBar ─────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final double speedKmh;
  final String remainingDist;
  final String eta;
  final RadarPoint? radarAlert;

  const _BottomBar({
    required this.speedKmh,
    required this.remainingDist,
    required this.eta,
    required this.radarAlert,
  });

  @override
  Widget build(BuildContext context) {
    final isLombada = radarAlert != null &&
        radarAlert!.type.toLowerCase().contains('lombada');

    return Container(
      color: const Color(0xFF212121),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Velocímetro circular
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF2C2C2C),
              border: Border.all(color: Colors.white24, width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${speedKmh.round()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
                Text(
                  'km/h',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Alerta de radar (se houver) ou distância + tempo
          Expanded(
            child: radarAlert != null
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isLombada ? Colors.orange.shade700 : Colors.red.shade700,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.speed, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          radarAlert!.speedKmh > 0
                              ? '${radarAlert!.speedKmh} km/h'
                              : isLombada ? 'Lombada' : 'Radar',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _BarItem(top: remainingDist, bottom: 'restante'),
                      _BarItem(top: eta, bottom: 'chegada'),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  final String top;
  final String bottom;

  const _BarItem({required this.top, required this.bottom});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(top,
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        Text(bottom,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
      ],
    );
  }
}
