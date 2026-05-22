import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/radar_point.dart';
import '../models/route_maneuver.dart';
import '../models/route_result.dart';
import '../models/truck_profile.dart';
import '../services/here_routing_service.dart';
import '../services/radar_service.dart';

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
    with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _posSub;
  late final FlutterTts _tts;

  late RouteResult _result;
  List<RadarPoint> _radares = [];

  LatLng? _currentPos;
  double _bearing = 0;
  double _speedKmh = 0;
  int _closestPolylineIdx = 0;
  int _maneuverIndex = 0;
  double _distToNextManeuver = double.infinity;
  bool _muted = false;
  bool _isRerouting = false;
  Timer? _refreshTimer;
  int _offRouteCount = 0;
  RadarPoint? _upcomingRadar;
  final Set<int> _announced = {};

  // Cache de ícones para radares
  final _iconCache = <String, BitmapDescriptor>{};
  BitmapDescriptor? _userArrowIcon;

  static const _offRouteThresholdM = 80.0;
  static const _offRouteCountLimit = 4;
  static const _radarAlertM = 400.0;

  @override
  void initState() {
    super.initState();
    _result  = widget.result;
    _radares = List.of(widget.initialRadares);
    WidgetsBinding.instance.addObserver(this);
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
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _recenter();
    if (_muted) return;
    final maneuvers = _result.maneuvers;
    if (_maneuverIndex >= maneuvers.length) return;
    final m = maneuvers[_maneuverIndex];
    if (m.action == 'depart' || m.action == 'arrive') return;
    final dist = _distToNextManeuver;
    final text = dist.isFinite && dist < 50000
        ? 'Em ${_fmtDist(dist)}, ${m.instruction}'
        : m.instruction;
    _speak(text);
  }

  // ── TTS ──────────────────────────────────────────────────────────────────────

  void _initTts() {
    _tts = FlutterTts();
    _tts.setLanguage('pt-BR');
    _tts.setSpeechRate(0.9);
    _tts.setVolume(1.0);
  }

  void _speak(String text) {
    if (_muted) return;
    _tts.stop();
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
    final latLng = LatLng(pos.latitude, pos.longitude);

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
      if (_offRouteCount >= _offRouteCountLimit) _reroute();
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

    setState(() {
      _currentPos           = latLng;
      _bearing              = pos.heading;
      _speedKmh             = (pos.speed * 3.6).clamp(0, 300);
      _closestPolylineIdx   = bestIdx;
      _maneuverIndex        = nextIdx;
      _distToNextManeuver   = distToNext;
      _upcomingRadar        = upcoming;
    });

    // 5. Câmera segue o usuário
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(
        target:  latLng,
        zoom:    17,
        tilt:    45,
        bearing: pos.heading,
      )),
    );
  }

  // ── TTS por threshold de distância ───────────────────────────────────────────

  void _checkTts(int idx, double distM, RouteManeuver m) {
    if (m.action == 'depart' || m.action == 'arrive') return;
    final k500 = idx * 10 + 0;
    final k200 = idx * 10 + 1;
    final k50  = idx * 10 + 2;

    if (distM <= 50 && !_announced.contains(k50)) {
      _announced.add(k50);
      _announced.add(k200);
      _announced.add(k500);
      _speak(m.instruction);
    } else if (distM <= 200 && !_announced.contains(k200)) {
      _announced.add(k200);
      _announced.add(k500);
      _speak('Em 200 metros, ${m.instruction}');
    } else if (distM <= 500 && !_announced.contains(k500)) {
      _announced.add(k500);
      _speak('Em 500 metros, ${m.instruction}');
    }
  }

  // ── Re-roteamento ─────────────────────────────────────────────────────────────

  Future<void> _periodicRefresh() async {
    if (_isRerouting || _currentPos == null) return;
    await _reroute();
  }

  Future<void> _reroute() async {
    if (_isRerouting || _currentPos == null) return;
    setState(() { _isRerouting = true; _offRouteCount = 0; });
    try {
      final newResult = await HereRoutingService.calculateRoute(
        origin:      _currentPos!,
        destination: widget.destination,
        truck:       widget.truck,
        waypoints:   widget.waypoints,
      );
      final allRadares = await RadarService.load();
      final nearby = RadarService.deduplicateNearby(
        RadarService.filterNearRoute(allRadares, newResult.polylinePoints),
      ).where((r) => !(r.type.toLowerCase().contains('lombada') && r.speedKmh == 0)).toList();
      if (!mounted) return;
      setState(() {
        _result             = newResult;
        _radares            = nearby;
        _closestPolylineIdx = 0;
        _maneuverIndex      = 0;
        _distToNextManeuver = double.infinity;
        _announced.clear();
        _iconCache.clear();
      });
      _speak('Rota recalculada');
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

  String _fmtTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}min';
    return '${m}min';
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

    const size = 20.0;
    final bgColor = isPedagio
        ? Colors.blue.shade700
        : isLombada
            ? Colors.orange.shade700
            : Colors.red.shade700;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2, Paint()..color = bgColor);
    canvas.drawCircle(
      const Offset(size / 2, size / 2), size / 2 - 1.5,
      Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5,
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
                fontSize: r.speedKmh >= 100 ? 6.0 : 7.5,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              )
            : TextStyle(
                fontSize: 10,
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
    if (_currentPos == null || _mapController == null) return;
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(
        target:  _currentPos!,
        zoom:    17,
        tilt:    45,
        bearing: _bearing,
      )),
    );
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
          position: _currentPos!,
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
              maneuver:   nextM,
              distance:   _distToNextManeuver,
              dirIcon:    nextM != null ? _dirIcon(nextM) : Icons.straight,
              muted:      _muted,
              rerouting:  _isRerouting,
              onMute:     () => setState(() => _muted = !_muted),
              onClose:    () => Navigator.of(context).pop(),
              fmtDist:    _fmtDist,
            ),

            // ── Mapa ────────────────────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  FutureBuilder<List<BitmapDescriptor>>(
                    future: Future.wait(_radares.map(_radarIcon)),
                    builder: (context, snap) {
                      if (snap.hasData) {
                        for (var i = 0; i < _radares.length; i++) {
                          markers.add(Marker(
                            markerId: MarkerId('r_${_radares[i].lat}_${_radares[i].lng}'),
                            position: LatLng(_radares[i].lat, _radares[i].lng),
                            icon: snap.data![i],
                            infoWindow: InfoWindow(
                              title: _radares[i].speedKmh > 0
                                  ? '${_radares[i].speedKmh} km/h'
                                  : _radares[i].type,
                              snippet: _radares[i].type,
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
                        polylines: polylines,
                        markers: markers,
                        trafficEnabled: true,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        compassEnabled: false,
                      );
                    },
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
              ),
            ),

            // ── Barra inferior ──────────────────────────────────────────────
            _BottomBar(
              speedKmh:      _speedKmh,
              remainingDist: _fmtDist(remaining),
              remainingTime: _fmtTime(remSec),
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
  final bool muted;
  final bool rerouting;
  final VoidCallback onMute;
  final VoidCallback onClose;
  final String Function(double) fmtDist;

  const _InstructionBar({
    required this.maneuver,
    required this.distance,
    required this.dirIcon,
    required this.muted,
    required this.rerouting,
    required this.onMute,
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
          // Mudo
          IconButton(
            icon: Icon(muted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
            onPressed: onMute,
            tooltip: muted ? 'Ativar voz' : 'Silenciar',
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
  final String remainingTime;
  final RadarPoint? radarAlert;

  const _BottomBar({
    required this.speedKmh,
    required this.remainingDist,
    required this.remainingTime,
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
                      _BarItem(top: remainingTime, bottom: 'chegada'),
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
