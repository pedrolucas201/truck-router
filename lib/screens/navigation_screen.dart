import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show listEquals, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/bridge_restriction.dart';
import '../models/police_alert.dart';
import '../models/radar_point.dart';
import '../models/route_maneuver.dart';
import '../models/route_result.dart';
import '../models/truck_profile.dart';
import '../models/user_restriction.dart';
import '../repositories/restriction_repository.dart';
import '../services/auth_service.dart';
import '../services/field_log.dart';
import '../services/here_routing_service.dart';
import '../services/police_alert_service.dart';
import '../services/radar_service.dart';
import '../utils/radar_tts.dart';
import '../services/restriction_service.dart';
import '../data/map_styles.dart';
import '../data/pois.dart';
import '../models/poi.dart';
import '../models/route_event.dart';
import '../providers/theme_controller.dart';
import '../widgets/add_restriction_sheet.dart';
import '../widgets/crosshair.dart';
import '../widgets/next_event_strip.dart';
import '../widgets/upcoming_dots.dart';

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
  late ThemeController _themeController;
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
  DateTime? _lastRerouteAt;
  int _offRouteCount = 0;
  DateTime? _offRouteSince; // instrumentação: quando o caminhão saiu do corredor
  RadarPoint? _upcomingRadar;
  final Set<int> _announced = {};

  // Cache de ícones para radares
  final _iconCache = <String, BitmapDescriptor>{};
  Future<List<BitmapDescriptor>>? _radarIconsFuture;

  final List<UserRestriction> _userRestrictions = [];
  final _restrictionIconCache = <String, BitmapDescriptor>{};

  bool _markingMode = false;
  bool _paused = false;
  bool _arrived = false;
  // Estado "chegando": contador ancorado antes de finalizar (não mata o GPS —
  // o motorista ainda manobra / dá a volta no quarteirão).
  bool _arriving = false;
  LatLng? _arrivalAnchor;
  Timer? _arrivalTimer;
  double _arrivalProgress = 0.0; // 0→1 ao longo da contagem
  bool _ttsActive = false;
  bool _speedAlertActive = false;
  DateTime? _lastSpeedAlertAt;
  final Set<String> _actionedRestrictions = {};
  LatLng? _snappedPos;
  PoliceAlert? _nearestPoliceAlert;
  bool _hasFirstFix = false;
  LatLng _cameraTarget = const LatLng(-15.788, -47.879);
  BitmapDescriptor? _userArrowIcon;

  // Animação suave do marcador (N3)
  // Dead-reckoning: a seta é extrapolada por velocidade constante AO LONGO da
  // rota a 60fps, a partir do último fix GPS (anchor). Elimina o lag de ~1
  // intervalo que a animação por tween introduzia (seta sempre atrás do carro).
  // Guardas: não prevê parado (anti-freada) e congela após _maxPredictMs sem
  // fix novo (anti-viaduto/perda de sinal), evitando a seta deslizar sozinha.
  late AnimationController _predTicker; // driver de 60fps (.repeat)
  LatLng _animPos = const LatLng(-15.788, -47.879);
  double _animBearing = 0;
  LatLng? _anchorPos;          // posição snapped do último fix
  int _anchorIdx = 0;          // índice na polyline do último fix
  double _anchorSpeedMps = 0;  // velocidade do último fix (m/s)
  DateTime? _lastPosUpdateAt;  // hora do último fix (= anchor time)
  static const double _stopKmh = 3.0;
  static const int _maxPredictMs = 2500;

  // Cache dos overlays do mapa (polylines/circles). A animação do marcador
  // dispara setState a 60fps; sem cache, o build() realocava as sublists da
  // rota toda a cada frame e o google_maps_flutter re-enviava a geometria
  // pelo platform channel. Recomputamos só quando o índice/raio muda.
  Set<Polyline> _polylines = {};
  Set<Circle> _radarCircles = {};
  int? _overlaysSplitIdx;
  RadarPoint? _overlaysRadar;

  List<RouteEvent>  _upcomingEvents = [];
  List<Poi>         _routePois      = [];
  List<PoliceAlert> _policeAhead    = [];
  Timer?            _policeTimelineTimer;

  BridgeRestriction? _nearbyBlockedRestriction;
  String? _lastRestrictionAlertKey;
  String? _lastRadarAlertKey;
  DateTime? _resumedAt;
  bool _hasTimeRestrictionAlert  = false;
  bool _timeRestrictionAlertSpoken = false;

  // Corredor de desvio: 40m (era 120m). 120m deixava o caminhão errar um
  // quarteirão inteiro numa rua paralela antes de a contagem sequer começar —
  // causa raiz do reroute de 63s no teste de campo. 40m ≈ comportamento Waze.
  // O debounce de 3 fixes (_offRouteCountLimit) segura ruído de GPS.
  static const _offRouteThresholdM  = 40.0;
  static const _offRouteCountLimit  = 3;
  // Throttle do reroute: 10s pro refresh periódico/background; piso curto de 4s
  // pra desvio real (urgent), que já é naturalmente limitado pelo re-arm do
  // _offRouteCount (precisa de 3 fixes novos) + guarda _isRerouting.
  static const _rerouteThrottleSec     = 10;
  static const _rerouteUrgentFloorSec  = 4;
  // Chegada: contador de 15s antes de finalizar; se o caminhão se afastar mais
  // que 40m da âncora durante a contagem, cancela e reroteia (deu a volta).
  static const _arrivalCountdownMs = 15000;
  static const _arrivalMoveM       = 40.0;
  static const _radarAlertM         = 400.0;
  static const _restrictionAlertM   = 300.0;
  static const _radarLookAheadM     = 1500.0;
  // Distância perpendicular máxima do radar ao segmento da rota para contar
  // como "na via" (~largura de pista + erro de GPS). Antes era raio a pontos
  // soltos (60m), que vazava pra ruas paralelas. Tunável em campo.
  static const _radarCorridorM      = 22.0;
  static const _prefAudioLevel = 'nav_audio_level';
  static const _prefZoomLevel  = 'nav_zoom_level';

  @override
  void initState() {
    super.initState();
    _result  = widget.result;
    _radares        = List.of(widget.initialRadares);
    _visibleRadares = List.of(widget.initialRadares);
    _radarIconsFuture = Future.wait(_radares.map(_radarIcon));
    _hasTimeRestrictionAlert = widget.result.hasTimeRestriction;
    WidgetsBinding.instance.addObserver(this);
    _loadAudioLevel();
    _loadZoomLevel();
    _loadUserRestrictions();
    _startForegroundService();
    _initTts();
    _themeController = context.read<ThemeController>();
    _themeController.addListener(_onThemeChanged);
    _startGps();
    _predTicker = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..addListener(_predictTick)
      ..repeat();
    _refreshTimer = Timer.periodic(const Duration(minutes: 10), (_) => _periodicRefresh());
    WakelockPlus.enable();
    _buildUserArrow().then((icon) {
      if (mounted) setState(() => _userArrowIcon = icon);
    });
    _loadRoutePois();
    _policeTimelineTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _refreshPoliceTimeline(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _policeTimelineTimer?.cancel();
    _arrivalTimer?.cancel();
    _posSub?.cancel();
    _tts.stop();
    _ttsActive = false;
    _themeController.removeListener(_onThemeChanged);
    FlutterForegroundTask.stopService();
    WakelockPlus.disable();
    _predTicker.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _resumedAt = DateTime.now();
    // Re-anchora o marcador na posição atual — evita que a predição continue
    // de uma posição desatualizada ao retomar o app.
    if (_snappedPos != null) {
      _animPos     = _snappedPos!;
      _animBearing = _bearing;
      _anchorPos   = _snappedPos;
      _anchorSpeedMps = 0;
    }
    _lastPosUpdateAt = null;
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
        ? 'Em ${_fmtDist(dist)}. ${m.instruction}'
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
    // Debounce de 300ms: evita que completionHandler prematuro (chunk interno do engine)
    // abra a janela para um novo _speak interromper a utterance em andamento.
    _tts.setCompletionHandler(() =>
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _ttsActive = false;
        }));
    _tts.setCancelHandler(() => _ttsActive = false);
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

  void _onThemeChanged() {
    if (mounted) setState(() {});
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
      _ttsActive = false;
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
    if (_ttsActive) return;
    _ttsActive = true;
    _tts.speak(text);
  }

  // Entra no estado "chegando": ancora a posição, fala uma vez e arma a contagem.
  // NÃO cancela o GPS — _onPositionUpdate continua pra detectar se o caminhão
  // se afasta (manobra / volta no quarteirão) e cancelar a finalização.
  void _beginArrival(LatLng anchor) {
    if (_arrived || _arriving) return;
    _arriving = true;
    _arrivalAnchor = anchor;
    _arrivalProgress = 0.0;
    if (_audioLevel != AudioLevel.silencioso) {
      _tts.speak('Você chegou ao destino');
    }
    setState(() {});
    final start = DateTime.now();
    _arrivalTimer?.cancel();
    // Timer, NÃO AnimationController: o SingleTickerProviderStateMixin já é
    // consumido pelo _predTicker.
    _arrivalTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) { t.cancel(); return; }
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      setState(() => _arrivalProgress = (elapsed / _arrivalCountdownMs).clamp(0.0, 1.0));
      if (elapsed >= _arrivalCountdownMs) {
        t.cancel();
        _finalizeArrival();
      }
    });
  }

  // Caminhão se afastou da âncora durante a contagem: cancela e reroteia pra
  // guiá-lo de volta (típico de dar a volta no quarteirão pra entrar no pátio).
  void _cancelArrival() {
    if (!_arriving) return;
    _arrivalTimer?.cancel();
    _arrivalTimer = null;
    _arriving = false;
    _arrivalAnchor = null;
    _arrivalProgress = 0.0;
    _tts.stop();
    _ttsActive = false;
    _lastRerouteAt = null; // fura o throttle: precisa reorientar já
    if (mounted) setState(() {});
    if (_currentPos != null) _reroute(fromPos: _currentPos, urgent: true);
  }

  void _finalizeArrival() {
    if (_arrived) return;
    _arrived = true;
    _arrivalTimer?.cancel();
    _arrivalTimer = null;
    _arriving = false;
    _posSub?.cancel();
    _tts.stop();
    _ttsActive = false;
    // Sem speak aqui: "Você chegou ao destino" já foi dito em _beginArrival.
    if (mounted) setState(() {});
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Widget _buildArrivalBanner() {
    final secs = ((_arrivalCountdownMs * (1 - _arrivalProgress)) / 1000).ceil();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B5E20),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.flag, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Você chegou ao destino',
                      style: TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Finalizando em ${secs}s',
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: 1 - _arrivalProgress,
              minHeight: 6,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _finalizeArrival,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1B5E20),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text(
              'Finalizar agora',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _checkSpeedAlert(double kmh) {
    if (kmh >= 90) {
      final now = DateTime.now();
      if (!_speedAlertActive) {
        _speedAlertActive = true;
        _lastSpeedAlertAt = now;
        _speak('Velocidade acima do limite para caminhão');
      } else if (_lastSpeedAlertAt != null &&
          now.difference(_lastSpeedAlertAt!).inSeconds >= 30) {
        _lastSpeedAlertAt = now;
        _speak('Velocidade acima do limite para caminhão');
      }
    } else if (kmh < 85) {
      _speedAlertActive = false;
    }
  }

  // ── GPS ──────────────────────────────────────────────────────────────────────

  void _startGps() {
    // No Android, intervalDuration explícito força a frequência de updates do
    // fused provider (a LocationSettings base não controla isso). 1Hz é o teto
    // prático do GPS da maioria dos aparelhos — pedir menos garante esse mínimo.
    final LocationSettings settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            intervalDuration: const Duration(milliseconds: 1000),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
          );
    _posSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPositionUpdate);
  }

  void _checkPoliceAlerts(LatLng position) {
    const radiusMeters = 500.0;
    const deltaLat = 0.0045; // ~500m em graus lat
    const deltaLng = 0.0050; // ~500m em graus lng na latitude do Brasil
    PoliceAlertService.streamInBounds(
      position.latitude - deltaLat, position.latitude + deltaLat,
      position.longitude - deltaLng, position.longitude + deltaLng,
    ).first.then((alerts) {
      if (!mounted) return;
      PoliceAlert? nearest;
      double bestDist = radiusMeters;
      for (final a in alerts) {
        final d = RadarService.haversine(
          position.latitude, position.longitude, a.lat, a.lng);
        if (d < bestDist) { bestDist = d; nearest = a; }
      }
      if (nearest?.id != _nearestPoliceAlert?.id) {
        setState(() => _nearestPoliceAlert = nearest);
      }
    });
  }

  void _onPositionUpdate(Position pos) {
    if (!mounted) return;
    final firstFix = !_hasFirstFix;
    _hasFirstFix = true;
    if (firstFix && _hasTimeRestrictionAlert && !_timeRestrictionAlertSpoken) {
      _timeRestrictionAlertSpoken = true;
      _speak('Atenção! Restrição para caminhões nesta via');
    }
    if (firstFix) _refreshPoliceTimeline();
    final latLng = LatLng(pos.latitude, pos.longitude);

    if (_paused) {
      final pts2 = _result.polylinePoints;
      final s2 = (_closestPolylineIdx - 5).clamp(0, pts2.length - 1);
      var bd2  = double.infinity;
      var snap2 = pts2.isNotEmpty ? pts2[_closestPolylineIdx] : latLng;
      final end2 = min(s2 + 200, pts2.length);
      for (var i = s2; i < end2 - 1; i++) {
        final s = _projectToSegment(latLng, pts2[i], pts2[i + 1]);
        final d = RadarService.haversine(latLng.latitude, latLng.longitude, s.latitude, s.longitude);
        if (d < bd2) { bd2 = d; snap2 = s; }
      }
      if (end2 == pts2.length && pts2.isNotEmpty) {
        final d = RadarService.haversine(latLng.latitude, latLng.longitude, pts2[end2 - 1].latitude, pts2[end2 - 1].longitude);
        if (d < bd2) { snap2 = pts2[end2 - 1]; }
      }
      final pausedSnap    = pts2.isNotEmpty ? snap2 : latLng;
      final pausedBearing = pts2.length >= 2
          ? _segmentBearing(pts2, _closestPolylineIdx.clamp(0, pts2.length - 1))
          : pos.heading;
      setState(() {
        _currentPos = latLng;
        _snappedPos = pausedSnap;
        _bearing    = pausedBearing;
        _speedKmh   = pos.speed * 3.6 < 2.5 ? 0.0 : (pos.speed * 3.6).clamp(0.0, 300.0);
      });
      // Pausado: ancora sem velocidade — marcador fica parado no snap, sem prever.
      _setAnchor(pausedSnap, _closestPolylineIdx, pausedBearing, 0);
      return;
    }

    // Estado "chegando": contador ancorado. Não roda nav normal; só vigia se o
    // caminhão se afasta da âncora (cancela + reroteia) — senão deixa contar.
    if (_arriving) {
      final anchor = _arrivalAnchor ?? latLng;
      final fromAnchorM = RadarService.haversine(
        latLng.latitude, latLng.longitude, anchor.latitude, anchor.longitude,
      );
      if (fromAnchorM > _arrivalMoveM) {
        _cancelArrival();
        return;
      }
      setState(() { _currentPos = latLng; _snappedPos = latLng; });
      _setAnchor(latLng, _closestPolylineIdx, _bearing, 0);
      return;
    }

    // Recálculo em andamento: a polyline atual é a antiga (vai ser trocada em
    // _reroute). Rodar detecção de desvio/radar/manobra contra ela é trabalho
    // jogado fora — e pior, re-incrementa _offRouteCount e fica re-disparando o
    // reroute (storm) num caminhão que já está fora do corredor. Só atualiza a
    // posição e deixa o recálculo terminar. O marcador já está ancorado parado
    // por _reroute, então o ticker continua renderizando sem travar a thread.
    if (_isRerouting) {
      _currentPos = latLng;
      return;
    }

    // 1. Segmento mais próximo na polyline (projeção, não só vértice)
    final pts  = _result.polylinePoints;
    final start = (_closestPolylineIdx - 5).clamp(0, pts.length - 1);
    var bestIdx  = _closestPolylineIdx;
    var bestDist = double.infinity;
    var bestSnap = pts.isNotEmpty ? pts[_closestPolylineIdx] : latLng;
    final end = min(start + 200, pts.length);
    for (var i = start; i < end - 1; i++) {
      final snap = _projectToSegment(latLng, pts[i], pts[i + 1]);
      final d = RadarService.haversine(
        latLng.latitude, latLng.longitude,
        snap.latitude, snap.longitude,
      );
      if (d < bestDist) { bestDist = d; bestIdx = i; bestSnap = snap; }
    }
    if (end == pts.length && pts.isNotEmpty) {
      final d = RadarService.haversine(
          latLng.latitude, latLng.longitude, pts[end - 1].latitude, pts[end - 1].longitude);
      if (d < bestDist) { bestDist = d; bestIdx = end - 1; bestSnap = pts[end - 1]; }
    }

    // 2. Arrival detection: velocidade < 10 km/h E (linha reta ao destino < 80m OU
    // distância restante na polilinha < 50m). A checagem em linha reta cobre o caso
    // em que a HERE roteia o pino para dentro da propriedade — o caminhão já está na
    // "porta" mas o fim da polilinha fica lá dentro. O fallback de polilinha cobre
    // casos onde o snap do GPS diverge do pino de destino.
    if (!_arrived && !_arriving && pos.speed * 3.6 < 10) {
      final straightToDestM = RadarService.haversine(
        latLng.latitude, latLng.longitude,
        widget.destination.latitude, widget.destination.longitude,
      );
      if (straightToDestM < 80) {
        _beginArrival(latLng);
        return;
      }
      var remaining = 0.0;
      for (var i = bestIdx; i < pts.length - 1; i++) {
        remaining += RadarService.haversine(
          pts[i].latitude, pts[i].longitude,
          pts[i + 1].latitude, pts[i + 1].longitude,
        );
        if (remaining > 120) break;
      }
      if (remaining < 50) {
        _beginArrival(latLng);
        return;
      }
    }

    // 3. Desvio de rota
    if (bestDist > _offRouteThresholdM) {
      if (_offRouteCount == 0) {
        _offRouteSince = DateTime.now();
        FieldLog.event('off_route', {'distM': bestDist.round()});
      }
      _offRouteCount++;
      if (_offRouteCount >= _offRouteCountLimit) _reroute(fromPos: latLng, urgent: true);
    } else {
      _offRouteCount = 0;
      _offRouteSince = null;
    }

    // 4. Manobra atual — busca monotônica: mIdx só avança, nunca retrocede.
    // GPS noise pode oscilar bestIdx ao redor do polylineOffset de uma manobra,
    // fazendo nextIdx alternar entre N e N+1 e re-disparar os thresholds de TTS.
    final maneuvers = _result.maneuvers;
    final searchStart = _maneuverIndex > 0 ? _maneuverIndex - 1 : 0;
    var mIdx = searchStart;
    for (var i = searchStart; i < maneuvers.length; i++) {
      if (maneuvers[i].polylineOffset <= bestIdx) mIdx = i;
    }
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

    // 5. Radares visíveis: até 1500m à frente na polyline, restritos ao corredor
    // da rota medido pela distância PERPENDICULAR ao segmento (não raio a pontos
    // soltos) — elimina falso positivo em via paralela.
    final aheadPts = <LatLng>[];
    for (var i = bestIdx; i < pts.length; i++) {
      if (RadarService.haversine(latLng.latitude, latLng.longitude,
              pts[i].latitude, pts[i].longitude) > _radarLookAheadM) { break; }
      aheadPts.add(pts[i]);
    }
    final visibleRadares = _radares.where((r) =>
        RadarService.distanceToPath(r.lat, r.lng, aheadPts) <= _radarCorridorM
    ).toList();

    // 6. Radar à frente — restrito ao corredor da rota (sem falso positivo em paralelas)
    RadarPoint? upcoming;
    for (final r in visibleRadares) {
      final d = RadarService.haversine(latLng.latitude, latLng.longitude, r.lat, r.lng);
      if (d < _radarAlertM) {
        if (upcoming == null ||
            d < RadarService.haversine(latLng.latitude, latLng.longitude, upcoming.lat, upcoming.lng)) {
          upcoming = r;
        }
      }
    }

    // 7. Restrição bloqueada à frente
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

    final radarListChanged = !listEquals(visibleRadares, _visibleRadares);
    setState(() {
      _currentPos                 = latLng;
      _snappedPos                 = pts.isNotEmpty ? bestSnap : latLng;
      _bearing                    = pos.heading;
      _speedKmh                   = pos.speed * 3.6 < 2.5 ? 0.0 : (pos.speed * 3.6).clamp(0.0, 300.0);
      _closestPolylineIdx         = bestIdx;
      _maneuverIndex              = nextIdx;
      _distToNextManeuver         = distToNext;
      _upcomingRadar              = upcoming;
      _nearbyBlockedRestriction   = nearestBlocked;
      _visibleRadares             = visibleRadares;
      if (radarListChanged) {
        _radarIconsFuture = Future.wait(visibleRadares.map(_radarIcon));
      }
    });
    // Bearing único para seta e câmera: o segmento da rota (estável), não o
    // heading bruto do GPS. Evita a "pescadinha" — a seta balançando em cima
    // de um mapa que já gira suave. Fallback para heading só sem rota.
    final routeBearing = pts.length >= 2 ? _segmentBearing(pts, bestIdx) : pos.heading;
    _setAnchor(pts.isNotEmpty ? bestSnap : latLng, bestIdx, routeBearing, pos.speed);
    _updateRestrictionAlert(nearestBlocked, nearestBlockedDist);
    _updateRadarAlert(upcoming);
    _checkSpeedAlert(_speedKmh);
    _checkPoliceAlerts(latLng);
    _buildUpcomingEvents();

    // 8. Câmera segue o usuário (pausada no modo crosshair)
    // Usa pts[bestIdx] (snapped) em vez do GPS bruto — evita que a seta
    // apareça fora da via no zoom aproximado por drift de GPS.
    if (!_markingMode) {
      final camTarget  = pts.isNotEmpty ? bestSnap : latLng;
      final camBearing = routeBearing;
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(
          target:  camTarget,
          zoom:    _zoom,
          tilt:    45,
          bearing: camBearing,
        )),
      );
    }
  }

  // Registra um novo fix GPS como âncora da predição. O _predTicker passa a
  // extrapolar a partir daqui. Velocidade <= 0 (ou parado) → marcador não anda.
  void _setAnchor(LatLng pos, int idx, double bearing, double speedMps) {
    final pts = _result.polylinePoints;
    final firstFix = _lastPosUpdateAt == null;
    _anchorPos       = pos;
    _anchorIdx       = pts.isEmpty ? 0 : idx.clamp(0, pts.length - 1);
    _anchorSpeedMps  = (speedMps.isFinite && speedMps > 0) ? speedMps : 0.0;
    _lastPosUpdateAt = DateTime.now();
    // Primeiro fix: posiciona direto (sai do default de Brasília sem deslizar).
    if (firstFix && mounted) {
      setState(() { _animPos = pos; _animBearing = bearing; });
    }
  }

  // Extrapola a posição da seta a 60fps a partir da âncora, andando ao longo
  // da rota. Guarda anti-freada (não prevê parado) e anti-viaduto (congela
  // após _maxPredictMs sem fix). Não faz setState quando a posição não muda
  // (parado/pausado) — evita rebuild de 60fps à toa.
  void _predictTick() {
    if (!mounted) return;
    final anchor = _anchorPos;
    final anchorTime = _lastPosUpdateAt;
    if (anchor == null || anchorTime == null) return;
    final pts = _result.polylinePoints;
    if (pts.length < 2) return;

    final elapsedMs = DateTime.now()
        .difference(anchorTime)
        .inMilliseconds
        .clamp(0, _maxPredictMs);
    final advanceM = (_anchorSpeedMps * 3.6 >= _stopKmh)
        ? _anchorSpeedMps * (elapsedMs / 1000.0)
        : 0.0;

    final (predPos, predIdx) = _advanceAlongRoute(pts, _anchorIdx, anchor, advanceM);
    final predBearing = _segmentBearing(pts, predIdx);

    if (_sameLatLng(predPos, _animPos) && (predBearing - _animBearing).abs() < 0.1) {
      return;
    }
    setState(() {
      _animPos     = predPos;
      _animBearing = predBearing;
    });
  }

  // Caminha `distM` à frente pela polyline a partir de (startIdx, startPos).
  // Retorna a posição interpolada e o índice do segmento onde caiu. Cap no fim.
  (LatLng, int) _advanceAlongRoute(
      List<LatLng> pts, int startIdx, LatLng startPos, double distM) {
    var idx = startIdx.clamp(0, pts.length - 2);
    if (distM <= 0) return (startPos, idx);
    var remaining = distM;
    var cur = startPos;
    while (idx < pts.length - 1) {
      final next = pts[idx + 1];
      final segLeft = RadarService.haversine(
          cur.latitude, cur.longitude, next.latitude, next.longitude);
      if (remaining <= segLeft) {
        final t = segLeft > 0 ? remaining / segLeft : 0.0;
        return (
          LatLng(
            cur.latitude  + (next.latitude  - cur.latitude)  * t,
            cur.longitude + (next.longitude - cur.longitude) * t,
          ),
          idx,
        );
      }
      remaining -= segLeft;
      idx++;
      cur = pts[idx];
    }
    return (pts.last, pts.length - 2);
  }

  bool _sameLatLng(LatLng a, LatLng b) =>
      (a.latitude - b.latitude).abs() < 1e-7 &&
      (a.longitude - b.longitude).abs() < 1e-7;

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
        _speak('Em 500 metros. ${m.instruction}');
      } else if (distM <= 200 && !_announced.contains(k200)) {
        _announced.add(k200);
        _announced.add(k500);
        _speak('Em 200 metros. ${m.instruction}');
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
        _speak('Em 200 metros. ${m.instruction}');
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

  void _updateRestrictionAlert(BridgeRestriction? restriction, double dist) {
    if (restriction == null) { return; }
    final key = '${restriction.lat}_${restriction.lng}';
    if (key == _lastRestrictionAlertKey) return;
    _lastRestrictionAlertKey = key;
    _speak('Atenção! ${restriction.label} a ${dist.round()} metros à frente');
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
    if (radar == null) return;
    final key = '${radar.lat}_${radar.lng}';
    if (key == _lastRadarAlertKey) return;
    _lastRadarAlertKey = key;
    final isLombada = radar.type.toLowerCase().contains('lombada');
    final isPedagio = radar.type.toLowerCase().contains('pedagio');
    if (isLombada) {
      _speak('Lombada à frente');
    } else if (isPedagio) {
      _speak('Pedágio à frente');
    } else {
      // Silencia o TTS quando dentro do limite. speedKmh == 0 = dado ausente → alerta por cautela.
      if (radar.speedKmh > 0 && _speedKmh <= radar.speedKmh) return;
      _speak(radarAlertPhrase(radar.speedKmh));
    }
  }

  // ── Re-roteamento ─────────────────────────────────────────────────────────────

  Future<void> _periodicRefresh() async {
    if (_isRerouting || _paused || _currentPos == null) return;
    await _reroute();
  }

  Future<void> _reroute({LatLng? fromPos, bool urgent = false}) async {
    final origin = fromPos ?? _currentPos;
    if (_isRerouting || origin == null) return;
    final now = DateTime.now();
    // Desvio real (urgent) usa piso curto; refresh de background usa throttle cheio.
    final floorSec = urgent ? _rerouteUrgentFloorSec : _rerouteThrottleSec;
    if (_lastRerouteAt != null && now.difference(_lastRerouteAt!).inSeconds < floorSec) {
      // Throttle barrou: se isto aparecer em rajada nos breadcrumbs, é storm.
      FieldLog.event('reroute_skip', {'urgent': urgent, 'floorSec': floorSec});
      return;
    }
    _lastRerouteAt = now;
    // Instrumentação P0: tempo de detecção (saiu do corredor → disparou o reroute).
    final detectMs = _offRouteSince != null ? now.difference(_offRouteSince!).inMilliseconds : -1;
    FieldLog.event('reroute_start', {'urgent': urgent, 'detectMs': detectMs});
    final recalcSw = Stopwatch()..start();

    // Snapa marcador para posição atual e re-anchora — geometria vai mudar.
    final snapTarget = _snappedPos ?? _currentPos;
    if (snapTarget != null) {
      setState(() { _animPos = snapTarget; _animBearing = _bearing; });
      _anchorPos = snapTarget;
      _anchorSpeedMps = 0;
    }
    _lastPosUpdateAt = null;

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
        _overlaysSplitIdx        = null; // invalida cache de overlays: geometria mudou
        _maneuverIndex           = 0;
        _distToNextManeuver      = double.infinity;
        _hasTimeRestrictionAlert = newResult.hasTimeRestriction;
        _announced.clear();
        _lastRadarAlertKey       = null;
        _lastRestrictionAlertKey = null;
        _iconCache.clear();
        _radarIconsFuture        = null;
      });
      // Instrumentação P0 (logcat / `flutter logs`): separa os 63s em
      // detecção (corredor) vs recálculo (HERE + Firestore enrichment).
      debugPrint('[REROUTE] urgent=$urgent detecção=${detectMs}ms '
          'recálculo=${recalcSw.elapsedMilliseconds}ms');
      FieldLog.event('reroute_done', {
        'urgent':   urgent,
        'detectMs': detectMs,
        'recalcMs': recalcSw.elapsedMilliseconds,
        'points':   newResult.polylinePoints.length,
        'distM':    newResult.distanceMeters.round(),
      });
      if (newResult.hasTimeRestriction && !_timeRestrictionAlertSpoken) {
        _timeRestrictionAlertSpoken = true;
        _speak('Atenção! Restrição para caminhões nesta via');
      } else if (!newResult.hasTimeRestriction) {
        _timeRestrictionAlertSpoken = false;
      }
      _loadRoutePois();
      _refreshPoliceTimeline();
      // Só anuncia se nível completo e rota mudou significativamente (>500m)
      if (_audioLevel == AudioLevel.completo &&
          (newResult.distanceMeters - prevDistM).abs() > 500) {
        _speak('Rota recalculada');
      }
    } catch (e, st) {
      // Não vaza pro usuário (princípio do Márcio), mas não some: sobe como
      // non-fatal pro Crashlytics + breadcrumb. Antes era catch(_) {} mudo.
      FieldLog.error('reroute', e, st);
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
    final isRadarWithSpeed = !isPedagio && !isLombada && r.speedKmh > 0;
    final key = isPedagio ? 'p' : '${isLombada ? 'l' : 'r'}_${r.speedKmh}';
    if (_iconCache.containsKey(key)) return _iconCache[key]!;

    final bgColor = isPedagio
        ? Colors.blue.shade700
        : isLombada
            ? Colors.orange.shade700
            : Colors.red.shade700;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    if (isRadarWithSpeed) {
      // Retângulo arredondado: câmera acima + velocidade abaixo — distinto de placa de limite
      const w = 44.0;
      const h = 50.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, w, h), const Radius.circular(8)),
        Paint()..color = bgColor,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, w, h), const Radius.circular(8)),
        Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3.0,
      );
      const camIcon = Icons.camera_alt;
      final camTp = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
          text: String.fromCharCode(camIcon.codePoint),
          style: TextStyle(fontSize: 20, fontFamily: camIcon.fontFamily, color: Colors.white),
        )
        ..layout();
      camTp.paint(canvas, Offset((w - camTp.width) / 2, 4));
      final speedTp = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
          text: r.speedKmh.toString(),
          style: TextStyle(
            fontSize: r.speedKmh >= 100 ? 11.0 : 13.0,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        )
        ..layout();
      speedTp.paint(canvas, Offset((w - speedTp.width) / 2, h - speedTp.height - 4));
      final img   = await recorder.endRecording().toImage(w.toInt(), h.toInt());
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      final icon  = BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
      _iconCache[key] = icon;
      return icon;
    }

    // Círculo para lombada, pedágio e radar sem velocidade cadastrada
    const size = 40.0;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2, Paint()..color = bgColor);
    canvas.drawCircle(
      const Offset(size / 2, size / 2), size / 2 - 3.0,
      Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3.0,
    );
    final IconData displayIcon = isPedagio ? Icons.toll : Icons.camera_alt;
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(displayIcon.codePoint),
        style: TextStyle(fontSize: 22, fontFamily: displayIcon.fontFamily, color: Colors.white),
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

  // ── Projeção no segmento mais próximo ────────────────────────────────────────

  static LatLng _projectToSegment(LatLng p, LatLng a, LatLng b) {
    final dx = b.latitude - a.latitude;
    final dy = b.longitude - a.longitude;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return a;
    final t = ((p.latitude - a.latitude) * dx + (p.longitude - a.longitude) * dy) / lenSq;
    final tc = t.clamp(0.0, 1.0);
    return LatLng(a.latitude + tc * dx, a.longitude + tc * dy);
  }

  // Bearing do segmento pts[idx] → pts[idx+1] em graus (0°=Norte, 90°=Leste).
  // Rastro percorrido em cinza (estilo Google) + rota à frente em azul.
  // O cinza ajuda a se orientar em trevos: mostra de onde veio vs. pra onde ir.
  Set<Polyline> _buildPolylines(List<LatLng> pts, int splitIdx) {
    return {
      if (splitIdx >= 1)
        Polyline(
          polylineId: const PolylineId('nav_traveled'),
          points: pts.sublist(0, splitIdx + 1),
          color: Colors.blueGrey.shade300,
          width: 7,
        ),
      if (splitIdx < pts.length - 1)
        Polyline(
          polylineId: const PolylineId('nav_remaining_halo'),
          points: pts.sublist(splitIdx),
          color: const Color(0xFF1565C0).withAlpha(90),
          width: 18,
        ),
      if (splitIdx < pts.length - 1)
        Polyline(
          polylineId: const PolylineId('nav_remaining'),
          points: pts.sublist(splitIdx),
          color: const Color(0xFF1565C0),
          width: 10,
        ),
    };
  }

  Set<Circle> _buildRadarCircles() {
    final r = _upcomingRadar;
    if (r == null) return {};
    final isLombada = r.type.toLowerCase().contains('lombada');
    return {
      Circle(
        circleId: const CircleId('radar_alert'),
        center: LatLng(r.lat, r.lng),
        radius: 80.0,
        fillColor: (isLombada ? Colors.orange : Colors.red).withAlpha(35),
        strokeColor: isLombada ? Colors.orange.shade400 : Colors.red.shade400,
        strokeWidth: 2,
      ),
    };
  }

  // Usa fórmula de haversine bearing — estável independente do heading do GPS.
  static double _segmentBearing(List<LatLng> pts, int idx) {
    if (pts.length < 2) return 0;
    final i = idx.clamp(0, pts.length - 2);
    final a = pts[i];
    final b = pts[i + 1];
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;
    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    return (atan2(y, x) * 180 / pi + 360) % 360;
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
    const double size   = 56;
    const double center = size / 2;
    const double radius = 24;

    final text = switch (r.type) {
      'maxheight' => '${r.value.toStringAsFixed(1)}m',
      'maxweight' => '${r.value.toStringAsFixed(0)}t',
      'dirtroad'  => 'Terra',
      _           => '${r.value.toStringAsFixed(1)}m',
    };

    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));

    // Sombra
    canvas.drawCircle(
      const Offset(center, center + 2),
      radius,
      Paint()
        ..color      = Colors.black38
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Fundo âmbar
    canvas.drawCircle(
      const Offset(center, center),
      radius,
      Paint()..color = const Color(0xFFFFA726),
    );

    // Borda branca
    canvas.drawCircle(
      const Offset(center, center),
      radius,
      Paint()
        ..color       = Colors.white
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Texto centralizado
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
      )
      ..layout(maxWidth: radius * 2);
    tp.paint(canvas, Offset(center - tp.width / 2, center - tp.height / 2));

    final picture = recorder.endRecording();
    final img     = await picture.toImage(size.toInt(), size.toInt());
    final bytes   = await img.toByteData(format: ui.ImageByteFormat.png);
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

  Future<void> _loadRoutePois() async {
    final pts = _result.polylinePoints;
    if (pts.isEmpty) return;

    var minLat = pts[0].latitude, maxLat = pts[0].latitude;
    var minLng = pts[0].longitude, maxLng = pts[0].longitude;
    for (final p in pts) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    const buf = 0.003;

    final sampled = <LatLng>[];
    for (var i = 0; i < pts.length; i += 5) { sampled.add(pts[i]); }
    if (sampled.last != pts.last) { sampled.add(pts.last); }

    final filtered = kHardcodedPois.where((poi) {
      if (poi.category != PoiCategory.scale &&
          poi.category != PoiCategory.restArea) { return false; }
      final lat = poi.position.latitude;
      final lng = poi.position.longitude;
      if (lat < minLat - buf || lat > maxLat + buf ||
          lng < minLng - buf || lng > maxLng + buf) { return false; }
      return sampled.any((p) =>
          RadarService.haversine(lat, lng, p.latitude, p.longitude) <= 500);
    }).toList();

    if (mounted) setState(() => _routePois = filtered);
  }

  Future<void> _refreshPoliceTimeline() async {
    if (_currentPos == null) return;
    final pts = _result.polylinePoints;
    if (pts.isEmpty) return;

    final startIdx = _closestPolylineIdx.clamp(0, pts.length - 1);
    final endIdx   = (startIdx + 200).clamp(0, pts.length - 1);
    final ahead    = pts.sublist(startIdx, endIdx + 1);
    if (ahead.isEmpty) return;

    var minLat = ahead[0].latitude, maxLat = ahead[0].latitude;
    var minLng = ahead[0].longitude, maxLng = ahead[0].longitude;
    for (final p in ahead) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    const buf = 0.005;

    try {
      final alerts = await PoliceAlertService.streamInBounds(
        minLat - buf, maxLat + buf, minLng - buf, maxLng + buf,
      ).first;
      if (mounted) setState(() => _policeAhead = alerts);
    } catch (_) {}
  }

  void _buildUpcomingEvents() {
    if (_currentPos == null) return;
    final pts = _result.polylinePoints;
    if (pts.isEmpty) return;

    final startIdx = _closestPolylineIdx.clamp(0, pts.length - 1);
    final aheadPts = pts.sublist(startIdx);
    if (aheadPts.isEmpty) {
      if (mounted) setState(() => _upcomingEvents = []);
      return;
    }

    var minLat = aheadPts[0].latitude, maxLat = aheadPts[0].latitude;
    var minLng = aheadPts[0].longitude, maxLng = aheadPts[0].longitude;
    for (final p in aheadPts) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    const buf = 0.002;

    bool isAhead(double lat, double lng, double corridorM) {
      if (lat < minLat - buf || lat > maxLat + buf ||
          lng < minLng - buf || lng > maxLng + buf) { return false; }
      for (var i = 0; i < aheadPts.length; i += 5) {
        if (RadarService.haversine(lat, lng,
                aheadPts[i].latitude, aheadPts[i].longitude) <= corridorM) {
          return true;
        }
      }
      return false;
    }

    double distFrom(double lat, double lng) => RadarService.haversine(
        _currentPos!.latitude, _currentPos!.longitude, lat, lng);

    final candidates = <RouteEvent>[];

    double bestRadarDist = double.infinity;
    for (final r in _radares) {
      if (!isAhead(r.lat, r.lng, 100)) continue; // prefiltro barato
      // Mesmo corredor perpendicular do alerta — sem falso radar de via paralela.
      if (RadarService.distanceToPath(r.lat, r.lng, aheadPts) > _radarCorridorM) {
        continue;
      }
      final d = distFrom(r.lat, r.lng);
      if (d < bestRadarDist) bestRadarDist = d;
    }
    if (bestRadarDist != double.infinity) {
      candidates.add(RouteEvent(type: RouteEventType.radar, distanceM: bestRadarDist));
    }

    double bestRestrDist = double.infinity;
    for (final b in _result.restrictionsBlocked) {
      if (!isAhead(b.lat, b.lng, 150)) continue;
      final d = distFrom(b.lat, b.lng);
      if (d < bestRestrDist) bestRestrDist = d;
    }
    if (bestRestrDist != double.infinity) {
      candidates.add(RouteEvent(type: RouteEventType.restriction, distanceM: bestRestrDist));
    }

    double bestPoliceDist = double.infinity;
    for (final a in _policeAhead) {
      if (!isAhead(a.lat, a.lng, 200)) continue;
      final d = distFrom(a.lat, a.lng);
      if (d < bestPoliceDist) bestPoliceDist = d;
    }
    if (bestPoliceDist != double.infinity) {
      candidates.add(RouteEvent(type: RouteEventType.police, distanceM: bestPoliceDist));
    }

    for (final poi in _routePois) {
      final lat = poi.position.latitude;
      final lng = poi.position.longitude;
      if (!isAhead(lat, lng, 300)) continue;
      final d = distFrom(lat, lng);
      if (d > 20000) continue;
      final type = poi.category == PoiCategory.scale
          ? RouteEventType.scale
          : RouteEventType.restArea;
      candidates.add(RouteEvent(type: type, distanceM: d));
    }

    candidates.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    final events = candidates.take(4).toList();
    if (mounted) setState(() => _upcomingEvents = events);
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
    if (_currentPos != null) await _reroute(fromPos: _currentPos, urgent: true);
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
    // Memoização: recomputa overlays só quando o trecho/raio realmente muda
    // (≈1Hz do GPS), não a cada frame da animação do marcador (60fps).
    // Mantendo a mesma instância de Set entre frames, o google_maps_flutter
    // não re-difunde a geometria pelo channel.
    if (_overlaysSplitIdx != splitIdx || !identical(_overlaysRadar, _upcomingRadar)) {
      _overlaysSplitIdx = splitIdx;
      _overlaysRadar    = _upcomingRadar;
      _polylines        = _buildPolylines(pts, splitIdx);
      _radarCircles     = _buildRadarCircles();
    }
    final polylines    = _polylines;
    final radarCircles = _radarCircles;

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('destination'),
        position: widget.destination,
        infoWindow: InfoWindow(title: 'Destino', snippet: widget.destinationLabel),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      if (_currentPos != null && _lastPosUpdateAt != null)
        Marker(
          markerId: const MarkerId('user'),
          position: _animPos,
          icon: _userArrowIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          flat: true,
          rotation: _animBearing,
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
              isNight:      _themeController.isNight,
              onAudioCycle: _cycleAudioLevel,
              onClose:      () => Navigator.of(context).pop(),
              fmtDist:      _fmtDist,
            ),

            // ── Faixa do próximo evento (degraus FAR/MID/NEAR) ──────────────
            if (_upcomingEvents.isNotEmpty && !_markingMode)
              NextEventStrip(event: _upcomingEvents.first),

            // ── Mapa ────────────────────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  FutureBuilder<List<BitmapDescriptor>>(
                    future: _radarIconsFuture ?? Future.value([]),
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
                            anchor: const Offset(0.5, 0.5),
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
                        onMapCreated: (c) {
                          _mapController = c;
                        },
                        style: _themeController.isNight ? kNightMapStyle : null,
                        onCameraMove: (pos) => _cameraTarget = pos.target,
                        polylines: polylines,
                        markers: markers,
                        circles: radarCircles,
                        trafficEnabled: false,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        compassEnabled: false,
                      );
                    },
                  ),
                  // ── Alerta restrição bloqueada / horário ────────────────
                  if ((_nearbyBlockedRestriction != null || _hasTimeRestrictionAlert) && !_markingMode)
                    Positioned(
                      bottom: 8,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
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
                                  color: const Color(0xFF4FC3F7),
                                  size: 26,
                                ),
                                const SizedBox(width: 12),
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
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () => _confirmRestriction(
                                          _nearbyBlockedRestriction!.id!),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF4FC3F7),
                                        foregroundColor: Colors.black,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(vertical: 13),
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12)),
                                        textStyle: const TextStyle(
                                            fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                      child: const Text('Confirmar'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () => _reportRestriction(
                                          _nearbyBlockedRestriction!.id!),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF424242),
                                        foregroundColor: const Color(0xFF4FC3F7),
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(vertical: 13),
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12)),
                                        textStyle: const TextStyle(
                                            fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                      child: const Text('Não existe'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (_nearestPoliceAlert != null && !_markingMode)
                    Positioned(
                      top: 0, left: 0, right: 0,
                      child: Material(
                        color: switch (_nearestPoliceAlert!.type) {
                          PoliceAlertType.radar  => Colors.orange.shade700,
                          PoliceAlertType.police => Colors.blue.shade700,
                          PoliceAlertType.blitz  => Colors.red.shade700,
                        },
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.local_police, color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    switch (_nearestPoliceAlert!.type) {
                                      PoliceAlertType.radar  => 'Radar à frente',
                                      PoliceAlertType.police => 'Polícia à frente',
                                      PoliceAlertType.blitz  => 'Blitz à frente',
                                    },
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  _nearestPoliceAlert!.timeRemainingText,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_upcomingEvents.length > 1 && !_markingMode)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: UpcomingDots(events: _upcomingEvents.skip(1).toList()),
                    ),
                  if (_arriving)
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: SafeArea(child: _buildArrivalBanner()),
                    ),
                  if (!_markingMode && !_arriving) ...[
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
  final bool isNight;
  final VoidCallback onAudioCycle;
  final VoidCallback onClose;
  final String Function(double) fmtDist;

  const _InstructionBar({
    required this.maneuver,
    required this.distance,
    required this.dirIcon,
    required this.audioLevel,
    required this.rerouting,
    required this.isNight,
    required this.onAudioCycle,
    required this.onClose,
    required this.fmtDist,
  });

  @override
  Widget build(BuildContext context) {
    const bg           = Colors.black;
    final instrColor   = isNight ? const Color(0xFF4FC3F7) : Colors.white;
    final distColor    = Colors.white;

    return Container(
      color: bg,
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
                        style: TextStyle(
                            color: instrColor, fontSize: 16, fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (distance.isFinite && distance < 50000)
                        Text(
                          'Em ${fmtDist(distance)}',
                          style: TextStyle(
                              color: distColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
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

class _BottomBar extends StatefulWidget {
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
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(_BottomBar old) {
    super.didUpdateWidget(old);
    if (widget.speedKmh >= 90 && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    } else if (widget.speedKmh < 88 && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Color get _borderColor {
    if (widget.speedKmh >= 90) return Colors.red.shade600;
    if (widget.speedKmh >= 80) return Colors.amber.shade600;
    return Colors.white24;
  }

  @override
  Widget build(BuildContext context) {
    final isOver = widget.speedKmh >= 90;
    final isWarn = widget.speedKmh >= 80;
    final isLombada = widget.radarAlert != null &&
        widget.radarAlert!.type.toLowerCase().contains('lombada');

    return Container(
      color: const Color(0xFF212121),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, _) {
              final t = isOver ? _pulseAnim.value : 0.0;
              final borderColor = isOver
                  ? Color.lerp(Colors.red.shade600, Colors.red.shade300, t)!
                  : _borderColor;
              final borderW = isOver ? 2.0 + t * 2.5 : (isWarn ? 2.5 : 2.0);
              final bgColor = isOver
                  ? Color.lerp(
                      const Color(0xFF2C2C2C), Colors.red.shade900, t * 0.35)!
                  : const Color(0xFF2C2C2C);

              return Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bgColor,
                  border: Border.all(color: borderColor, width: borderW),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${widget.speedKmh.round()}',
                      style: TextStyle(
                        color: isOver
                            ? Color.lerp(
                                Colors.white, Colors.red.shade200, t)
                            : Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                    ),
                    Text(
                      'km/h',
                      style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 10,
                          height: 1.2),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: widget.radarAlert != null
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isLombada
                          ? Colors.orange.shade700
                          : Colors.red.shade700,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.speed, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          widget.radarAlert!.speedKmh > 0
                              ? '${widget.radarAlert!.speedKmh} km/h'
                              : isLombada
                                  ? 'Lombada'
                                  : 'Radar',
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
                      _BarItem(
                          top: widget.remainingDist, bottom: 'restante'),
                      _BarItem(top: widget.eta, bottom: 'chegada'),
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
