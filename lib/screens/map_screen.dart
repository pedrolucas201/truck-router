import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/pois.dart';
import '../models/bridge_restriction.dart';
import '../models/poi.dart';
import '../models/radar_point.dart';
import '../models/route_history.dart';
import '../models/route_result.dart';
import '../models/truck_profile.dart';
import '../services/history_service.dart';
import '../providers/route_provider.dart';
import '../providers/truck_profile_provider.dart';
import '../services/here_geocoding_service.dart';
import '../services/radar_service.dart';
import '../widgets/address_search_field.dart';
import '../widgets/add_restriction_sheet.dart';
import '../widgets/crosshair.dart';
import 'truck_profile_screen.dart';
import 'navigation_screen.dart';
import '../models/user_restriction.dart';
import '../services/auth_service.dart';
import '../services/restriction_service.dart';
import '../repositories/restriction_repository.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  LatLng? _origin;
  LatLng? _destination;
  String? _originLabel;
  String? _destinationLabel;
  DateTime? _departureTime;
  Key _originKey      = const ValueKey('origin');
  Key _destinationKey = const ValueKey('destination');
  bool _locatingGps = false;
  final _waypointPositions = <LatLng?>[];
  final _waypointLabels    = <String?>[];
  final _waypointKeys      = <Key>[];
  int   _waypointKeySeq    = 0;
  final _poiIconCache      = <String, BitmapDescriptor>{};
  List<RadarPoint>         _nearbyRadares = [];
  List<UserRestriction>    _userRestrictions = [];
  double                   _currentZoom = 11.0;
  bool                     _markingMode = false;
  bool                     _panelCollapsed = false;
  bool                     _showDirtAlternative = false;
  String?                  _selectedRoute; // 'paved' | 'dirt'
  Timer?                   _routeSelectionTimer;
  LatLng                   _cameraTarget = const LatLng(-23.5505, -46.6333);
  DateTime?                _routeCalculatedAt;

  static const _radarMinZoom = 14.0;

  static const _initialPosition = CameraPosition(
    target: LatLng(-23.5505, -46.6333),
    zoom: 11,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPoiIcons();
    _loadUserRestrictions();
  }

  @override
  void dispose() {
    _routeSelectionTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_routeCalculatedAt == null) return;
    if (_departureTime != null) return;
    if (_origin == null || _destination == null) return;
    if (DateTime.now().difference(_routeCalculatedAt!) < const Duration(minutes: 15)) return;
    _autoRecalculate();
  }

  Future<void> _autoRecalculate() async {
    await _calculate();
    if (!mounted) return;
    if (context.read<RouteProvider>().result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rota atualizada automaticamente'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _loadPoiIcons() async {
    for (final compatible in [true, false]) {
      for (final category in PoiCategory.values) {
        final color = compatible ? _poiCompatibleColor(category) : Colors.grey.shade500;
        _poiIconCache['${category.name}_$compatible'] =
            await _buildPoiIcon(color, _poiIconData(category));
      }
    }
    _poiIconCache['label_paved'] = await _buildRouteLabelIcon(
      'Pavimentada', const Color(0xFF1565C0), Icons.verified_outlined);
    _poiIconCache['label_dirt'] = await _buildRouteLabelIcon(
      'Estrada de terra', Colors.orange.shade700, Icons.warning_amber_rounded);
    if (mounted) setState(() {});
  }

  static Future<BitmapDescriptor> _buildPoiIcon(Color color, IconData iconData) async {
    const size = 26.0;
    const iconSize = 13.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2,
      Paint()..color = color,
    );
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2 - 2,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize: iconSize,
          fontFamily: iconData.fontFamily,
          package: iconData.fontPackage,
          color: Colors.white,
        ),
      )
      ..layout();
    tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));
    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  static Future<BitmapDescriptor> _buildRadarIcon(
      int speedKmh, {bool isLombada = false, bool isPedagio = false}) async {
    const size = 20.0;
    final bgColor = isPedagio
        ? Colors.blue.shade700
        : isLombada
            ? Colors.orange.shade700
            : Colors.red.shade700;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2,
      Paint()..color = bgColor,
    );
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2 - 1.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final IconData iconData;
    if (isPedagio) {
      iconData = Icons.toll;
    } else if (speedKmh == 0) {
      iconData = Icons.camera_alt;
    } else {
      iconData = Icons.circle; // não usado — exibe texto abaixo
    }

    if (!isPedagio && speedKmh > 0) {
      final tp = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
          text: speedKmh.toString(),
          style: TextStyle(
            fontSize: speedKmh >= 100 ? 6.0 : 7.5,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        )
        ..layout();
      tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));
    } else {
      final tp = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
          text: String.fromCharCode(iconData.codePoint),
          style: TextStyle(
            fontSize: 10,
            fontFamily: iconData.fontFamily,
            color: Colors.white,
          ),
        )
        ..layout();
      tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));
    }
    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  static Future<BitmapDescriptor> _buildRouteLabelIcon(
      String text, Color bgColor, IconData icon) async {
    const h = 34.0;
    const iconPx = 13.0;
    const fontPx = 11.5;
    const padH = 9.0;
    const gap = 4.0;

    final iconTp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: iconPx,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      )
      ..layout();

    final textTp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: fontPx,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      )
      ..layout();

    final w = padH + iconTp.width + gap + textTp.width + padH;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final rRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      const Radius.circular(h / 2),
    );
    canvas.drawRRect(rRect, Paint()..color = bgColor);
    canvas.drawRRect(
      rRect,
      Paint()
        ..color = Colors.white.withAlpha(180)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    iconTp.paint(canvas, Offset(padH, (h - iconTp.height) / 2));
    textTp.paint(canvas, Offset(padH + iconTp.width + gap, (h - textTp.height) / 2));

    final picture = recorder.endRecording();
    final img = await picture.toImage(w.ceil(), h.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  Future<void> _loadUserRestrictions() async {
    final restrictions = await RestrictionService.load();
    for (final r in restrictions) {
      final key = 'ur_${r.lat}_${r.lng}_${r.createdAt.millisecondsSinceEpoch}';
      if (!_poiIconCache.containsKey(key)) {
        _poiIconCache[key] = await _buildRestrictionIcon(r);
      }
    }
    if (mounted) setState(() => _userRestrictions = restrictions);
  }

  static Future<BitmapDescriptor> _buildRestrictionIcon(UserRestriction r) async {
    const iconH = 20.0;
    final bgColor = switch (r.type) {
      'maxheight' => Colors.red.shade700,
      'maxweight' => Colors.brown.shade600,
      _           => Colors.deepOrange.shade600,
    };
    final text = switch (r.type) {
      'maxheight' => '${r.value.toStringAsFixed(1)}m',
      'maxweight' => '${r.value.toStringAsFixed(0)}t',
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

  Future<void> _saveRestrictionAt(LatLng latLng) async {
    final repo = context.read<RestrictionRepository>();
    final r = await showModalBottomSheet<UserRestriction>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => AddRestrictionSheet(position: latLng),
    );
    if (r == null || !mounted) return;

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
    _poiIconCache[key] = icon;
    setState(() => _userRestrictions.add(r));
    if (_origin != null && _destination != null) {
      await _calculate();
    }
  }

  void _choosePaved() {
    _routeSelectionTimer?.cancel();
    _routeSelectionTimer = null;
    setState(() { _showDirtAlternative = false; _selectedRoute = null; });
  }

  void _chooseDirt() {
    _routeSelectionTimer?.cancel();
    _routeSelectionTimer = null;
    context.read<RouteProvider>().useDirtRoadRoute();
    setState(() { _showDirtAlternative = false; _selectedRoute = null; });
  }

  void _tapPavedRoute() {
    _routeSelectionTimer?.cancel();
    setState(() => _selectedRoute = 'paved');
    _routeSelectionTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) _choosePaved();
    });
  }

  void _tapDirtRoute() {
    _routeSelectionTimer?.cancel();
    setState(() => _selectedRoute = 'dirt');
    _routeSelectionTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) _chooseDirt();
    });
  }

  Future<void> _enterMarkingMode() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('marking_onboarding_seen') ?? false;
    if (!seen && mounted) {
      await showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => const _MarkingOnboardingSheet(),
      );
      await prefs.setBool('marking_onboarding_seen', true);
    }
    if (mounted) setState(() => _markingMode = true);
  }

  void _exitMarkingMode() => setState(() => _markingMode = false);

  Future<void> _confirmMarkingPosition() async {
    final latLng = _cameraTarget;
    setState(() => _markingMode = false);
    await _saveRestrictionAt(latLng);
  }

  Future<void> _showRestrictionDetails(UserRestriction r) async {
    final shouldDelete = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _RestrictionDetailSheet(restriction: r),
    );
    if (shouldDelete != true || !mounted) return;
    await RestrictionService.remove(r);
    setState(() => _userRestrictions.removeWhere(
      (x) => x.lat == r.lat && x.lng == r.lng && x.createdAt == r.createdAt,
    ));
    if (_origin != null && _destination != null) {
      await _calculate();
    }
  }

  void _addWaypoint() {
    setState(() {
      _waypointPositions.add(null);
      _waypointLabels.add(null);
      _waypointKeys.add(ValueKey('wp_${_waypointKeySeq++}'));
    });
  }

  void _removeWaypoint(int index) {
    setState(() {
      _waypointPositions.removeAt(index);
      _waypointLabels.removeAt(index);
      _waypointKeys.removeAt(index);
    });
    context.read<RouteProvider>().clear();
  }

  Future<void> _useCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ative o GPS do dispositivo')),
        );
      }
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissão de localização negada')),
        );
      }
      return;
    }

    setState(() => _locatingGps = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );
      final latLng = LatLng(pos.latitude, pos.longitude);
      final label  = await HereGeocodingService.reverseGeocode(latLng);
      if (!mounted) return;
      setState(() {
        _origin      = latLng;
        _originLabel = label;
        _originKey   = ValueKey(latLng.toString());
        _locatingGps = false;
      });
      context.read<RouteProvider>().clear();
    } catch (_) {
      if (mounted) {
        setState(() => _locatingGps = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível obter a localização')),
        );
      }
    }
  }

  Future<void> _pickDepartureTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _departureTime ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departureTime ?? now),
    );
    if (time == null || !mounted) return;
    setState(() {
      _departureTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
    context.read<RouteProvider>().clear();
  }

  String _formatDeparture(DateTime dt) {
    final day   = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final hour  = dt.hour.toString().padLeft(2, '0');
    final min   = dt.minute.toString().padLeft(2, '0');
    return '$day/$month ${hour}h$min';
  }

  String _buildShareText(RouteResult result, TruckProfile truck) {
    final buf = StringBuffer('Rota do Caminhão\n\n');
    buf.writeln('Origem: ${_originLabel ?? '—'}');
    for (var i = 0; i < _waypointLabels.length; i++) {
      if (_waypointLabels[i] != null) {
        buf.writeln('Parada ${i + 1}: ${_waypointLabels[i]}');
      }
    }
    buf.writeln('Destino: ${_destinationLabel ?? '—'}');
    buf.writeln();
    if (_departureTime != null) {
      buf.writeln('Saída: ${_formatDeparture(_departureTime!)}');
    }
    buf.writeln('Distância: ${result.distanceText}');
    buf.writeln('Duração: ${result.durationText}');
    buf.writeln();
    buf.write(
      'Caminhão: ${truck.heightCm}cm alt / ${truck.widthCm}cm larg / '
      '${truck.lengthCm}cm comp / '
      '${(truck.weightKg / 1000).toStringAsFixed(0)}t bruto / '
      '${truck.axleCount} eixos',
    );
    return buf.toString();
  }

  void _shareRoute(RouteResult result, TruckProfile truck) {
    Share.share(_buildShareText(result, truck), subject: 'Rota do Caminhão');
  }

  Future<void> _launchNavigation() async {
    if (_origin == null || _destination == null) return;
    final o = _origin!;
    final d = _destination!;
    final stops = _waypointPositions.whereType<LatLng>().toList();

    final waypointsParam = stops.isNotEmpty
        ? '&waypoints=${stops.map((w) => '${w.latitude},${w.longitude}').join('|')}'
        : '';
    final googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&origin=${o.latitude},${o.longitude}'
      '&destination=${d.latitude},${d.longitude}'
      '$waypointsParam'
      '&travelmode=driving',
    );
    final wazeUrl = Uri.parse(
      'waze://?ll=${d.latitude},${d.longitude}&navigate=yes'
      '&from=${o.latitude},${o.longitude}',
    );

    final hasGoogleMaps = await canLaunchUrl(googleMapsUrl);
    final hasWaze       = await canLaunchUrl(wazeUrl);

    if (!mounted) return;

    if (!hasGoogleMaps && !hasWaze) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum app de navegação encontrado')),
      );
      return;
    }

    // Se só um app disponível, abre direto
    if (hasGoogleMaps && !hasWaze) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      return;
    }
    if (hasWaze && !hasGoogleMaps) {
      await launchUrl(wazeUrl, mode: LaunchMode.externalApplication);
      return;
    }

    // Ambos disponíveis — mostra chooser
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Abrir navegação em',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.map, color: Colors.blue),
              title: const Text('Google Maps'),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.pop(context);
                launchUrl(googleMapsUrl,
                    mode: LaunchMode.externalApplication);
              },
            ),
            ListTile(
              leading: const Icon(Icons.navigation, color: Color(0xFF00CCFF)),
              title: const Text('Waze'),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.pop(context);
                launchUrl(wazeUrl, mode: LaunchMode.externalApplication);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _startNavigation() {
    final result = context.read<RouteProvider>().result;
    if (result == null || _destination == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NavigationScreen(
        result:           result,
        destination:      _destination!,
        truck:            context.read<TruckProfileProvider>().profile,
        destinationLabel: _destinationLabel ?? '',
        waypoints:        _waypointPositions.whereType<LatLng>().toList(),
        initialRadares:   _nearbyRadares,
      ),
    ));
  }

  void _copyRoute(RouteResult result, TruckProfile truck) {
    Clipboard.setData(ClipboardData(text: _buildShareText(result, truck)));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copiado!'), duration: Duration(seconds: 2)),
    );
  }

  void _clearAll() {
    setState(() {
      _origin           = null;
      _destination      = null;
      _originLabel      = null;
      _destinationLabel = null;
      _departureTime    = null;
      _originKey        = ValueKey('origin_${DateTime.now().millisecondsSinceEpoch}');
      _destinationKey   = ValueKey('dest_${DateTime.now().millisecondsSinceEpoch}');
      _waypointPositions.clear();
      _waypointLabels.clear();
      _waypointKeys.clear();
      _nearbyRadares    = [];
      _panelCollapsed   = false;
    });
    context.read<RouteProvider>().clear();
  }

  void _restoreHistory(RouteHistory h) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _origin           = h.originPosition;
      _originLabel      = h.originLabel;
      _originKey        = ValueKey('origin_$ts');
      _destination      = h.destinationPosition;
      _destinationLabel = h.destinationLabel;
      _destinationKey   = ValueKey('dest_$ts');
      _departureTime    = h.departureTime;
      _waypointPositions
        ..clear()
        ..addAll(h.waypoints.map((w) => w.position));
      _waypointLabels
        ..clear()
        ..addAll(h.waypoints.map((w) => w.label));
      _waypointKeys
        ..clear()
        ..addAll(List.generate(
          h.waypoints.length,
          (i) => ValueKey('wp_${_waypointKeySeq++}'),
        ));
    });
    context.read<RouteProvider>().clear();
  }

  Future<void> _showHistory() async {
    final history = await HistoryService.load();
    if (!mounted) return;
    if (history.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhuma rota salva ainda')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (_) => _HistorySheet(
        history: history,
        onSelect: (h) {
          Navigator.pop(context);
          _restoreHistory(h);
        },
        onDelete: (index) => HistoryService.remove(index),
      ),
    );
  }

  void _addPoiAsWaypoint(Poi poi) {
    setState(() {
      _waypointPositions.add(poi.position);
      _waypointLabels.add(poi.name);
      _waypointKeys.add(ValueKey('wp_${_waypointKeySeq++}'));
    });
    context.read<RouteProvider>().clear();
  }

  void _showPoiDetails(Poi poi) {
    final truck = context.read<TruckProfileProvider>().profile;
    final canAddWaypoint = _waypointPositions.length < 3;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _PoiSheet(
        poi: poi,
        truck: truck,
        canAddWaypoint: canAddWaypoint,
        onAddToRoute: () {
          Navigator.pop(context);
          _addPoiAsWaypoint(poi);
        },
      ),
    );
  }

  Future<void> _calculate() async {
    if (_origin == null || _destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe origem e destino')),
      );
      return;
    }
    final truck = context.read<TruckProfileProvider>().profile;
    final manualAvoidAreas = _userRestrictions
        .where((r) => r.toBridgeRestriction().conflictsWith(truck))
        .map((r) => r.toBridgeRestriction().toAvoidArea())
        .toList();
    await context.read<RouteProvider>().calculate(
          origin: _origin!,
          destination: _destination!,
          truck: truck,
          departureTime: _departureTime,
          waypoints: _waypointPositions.whereType<LatLng>().toList(),
          manualAvoidAreas: manualAvoidAreas,
        );

    if (!mounted) return;

    final result = context.read<RouteProvider>().result;
    if (result != null) _routeCalculatedAt = DateTime.now();
    if (result != null) {
      final allRadares = await RadarService.load();
      final filtered = RadarService.deduplicateNearby(
        RadarService.filterNearRoute(allRadares, result.polylinePoints),
      ).where((r) => !(r.type.toLowerCase().contains('lombada') && r.speedKmh == 0)).toList();
      // Gera ícones só para os speeds que aparecem nesta rota
      for (final r in filtered) {
        final isLombada = r.type.toLowerCase().contains('lombada');
        final isPedagio = r.type.toLowerCase().contains('pedagio');
        final key = isPedagio
            ? 'pedagio'
            : '${isLombada ? 'lombada' : 'radar'}_${r.speedKmh}';
        if (!_poiIconCache.containsKey(key)) {
          _poiIconCache[key] = await _buildRadarIcon(
            r.speedKmh,
            isLombada: isLombada,
            isPedagio: isPedagio,
          );
        }
      }
      if (mounted) {
        setState(() {
          _nearbyRadares  = filtered;
          _panelCollapsed = true;
        });
      }
    }

    if (result != null && _origin != null && _destination != null) {
      HistoryService.add(RouteHistory(
        originLabel:         _originLabel ?? '',
        originPosition:      _origin!,
        waypoints: [
          for (var i = 0; i < _waypointPositions.length; i++)
            if (_waypointPositions[i] != null)
              WaypointEntry(
                label:    _waypointLabels[i] ?? '',
                position: _waypointPositions[i]!,
              ),
        ],
        destinationLabel:    _destinationLabel ?? '',
        destinationPosition: _destination!,
        departureTime:       _departureTime,
        distanceText:        result.distanceText,
        durationText:        result.durationText,
        calculatedAt:        DateTime.now(),
      ));
    }

    // O AnimatedSize e o Platform View do mapa processam resize no mesmo frame
    // que recebem a polyline — o rebuild extra garante que a linha apareça.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    final routeResult = result;
    if (routeResult != null && routeResult.polylinePoints.isNotEmpty && _mapController != null) {
      try {
        final allPts = [
          ...routeResult.polylinePoints,
          if (routeResult.dirtRoadAlternative != null)
            ...routeResult.dirtRoadAlternative!.polylinePoints,
        ];
        final pts = allPts;
        double minLat = pts[0].latitude, maxLat = pts[0].latitude;
        double minLng = pts[0].longitude, maxLng = pts[0].longitude;
        for (final p in pts) {
          if (p.latitude < minLat) minLat = p.latitude;
          if (p.latitude > maxLat) maxLat = p.latitude;
          if (p.longitude < minLng) minLng = p.longitude;
          if (p.longitude > maxLng) maxLng = p.longitude;
        }
        final center = LatLng(
          (minLat + maxLat) / 2,
          (minLng + maxLng) / 2,
        );
        final latSpan = (maxLat - minLat).abs();
        final lngSpan = (maxLng - minLng).abs();
        final maxSpan = max(latSpan, lngSpan);
        // Approximate zoom so the full route fits with padding.
        final zoom = maxSpan > 0
            ? (log(360 / maxSpan) / log(2) - 1).clamp(1.0, 20.0)
            : 10.0;
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) {
          await _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: center, zoom: zoom),
            ),
          );
        }
      } catch (_) {}
    }

    // Sheet de escolha quando rota com terra é significativamente mais rápida.
    if (!mounted) return;
    final finalResult = context.read<RouteProvider>().result;
    if (finalResult?.dirtRoadAlternative != null) {
      setState(() => _showDirtAlternative = true);
    }
  }

  Widget _buildCollapsedPanel() {
    return InkWell(
      onTap: () => setState(() => _panelCollapsed = false),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle, color: Colors.red.shade400),
                  ),
                  Container(width: 2, height: 12, color: Colors.grey.shade300),
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle, color: Colors.teal.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _originLabel ?? '',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _destinationLabel ?? '',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.expand_more, color: Colors.teal.shade700, size: 22),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routeProvider  = context.watch<RouteProvider>();
    final truckProvider  = context.watch<TruckProfileProvider>();

    final polylines = <Polyline>{};
    final markers = <Marker>{};
    final result = routeProvider.result;
    final pts = result?.polylinePoints;
    if (_showDirtAlternative && result?.dirtRoadAlternative != null) {
      final dirtPts = result!.dirtRoadAlternative!.polylinePoints;
      final dirtDimmed = _selectedRoute == 'paved';
      polylines.add(Polyline(
        polylineId: const PolylineId('route_dirt'),
        points: dirtPts,
        color: Colors.orange.shade700.withAlpha(dirtDimmed ? 60 : 255),
        width: dirtDimmed ? 4 : 6,
        patterns: [PatternItem.dash(24), PatternItem.gap(12)],
        zIndex: 0,
        onTap: _tapDirtRoute,
        consumeTapEvents: true,
      ));
      if (dirtPts.isNotEmpty && _poiIconCache.containsKey('label_dirt') && !dirtDimmed) {
        final mid = dirtPts[dirtPts.length ~/ 2];
        markers.add(Marker(
          markerId: const MarkerId('label_dirt'),
          position: mid,
          icon: _poiIconCache['label_dirt']!,
          anchor: const Offset(0.5, 0.5),
        ));
      }
    }
    if (pts != null && pts.isNotEmpty) {
      final pavedDimmed = _selectedRoute == 'dirt';
      polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: pts,
        color: const Color(0xFF1565C0).withAlpha(pavedDimmed ? 60 : 255),
        width: pavedDimmed ? 4 : 6,
        zIndex: 1,
        onTap: _showDirtAlternative ? _tapPavedRoute : null,
        consumeTapEvents: _showDirtAlternative,
      ));
      if (_showDirtAlternative && _poiIconCache.containsKey('label_paved') && !pavedDimmed) {
        final mid = pts[pts.length ~/ 2];
        markers.add(Marker(
          markerId: const MarkerId('label_paved'),
          position: mid,
          icon: _poiIconCache['label_paved']!,
          anchor: const Offset(0.5, 0.5),
        ));
      }
    }
    if (_origin != null) {
      markers.add(Marker(
        markerId: const MarkerId('origin'),
        position: _origin!,
        infoWindow: InfoWindow(title: 'Origem', snippet: _originLabel),
      ));
    }
    if (_destination != null) {
      markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: _destination!,
        infoWindow: InfoWindow(title: 'Destino', snippet: _destinationLabel),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ));
    }
    for (var i = 0; i < _waypointPositions.length; i++) {
      final pos = _waypointPositions[i];
      if (pos == null) continue;
      markers.add(Marker(
        markerId: MarkerId('waypoint_$i'),
        position: pos,
        infoWindow: InfoWindow(title: 'Parada ${i + 1}', snippet: _waypointLabels[i]),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ));
    }

    if (_currentZoom >= _radarMinZoom) {
      for (final r in _nearbyRadares) {
        final isLombada = r.type.toLowerCase().contains('lombada');
        final isPedagio = r.type.toLowerCase().contains('pedagio');
        final key = isPedagio
            ? 'pedagio'
            : '${isLombada ? 'lombada' : 'radar'}_${r.speedKmh}';
        markers.add(Marker(
          markerId: MarkerId('radar_${r.lat}_${r.lng}'),
          position: LatLng(r.lat, r.lng),
          icon: _poiIconCache[key] ?? BitmapDescriptor.defaultMarker,
          infoWindow: InfoWindow(
            title: r.speedKmh > 0 ? '${r.speedKmh} km/h' : r.type,
            snippet: r.type,
          ),
        ));
      }
    }

    for (final poi in kHardcodedPois) {
      final compatible = poi.isCompatibleWith(truckProvider.profile);
      final cacheKey = '${poi.category.name}_$compatible';
      markers.add(Marker(
        markerId: MarkerId('poi_${poi.name}'),
        position: poi.position,
        icon: _poiIconCache[cacheKey] ?? BitmapDescriptor.defaultMarker,
        infoWindow: InfoWindow.noText,
        onTap: () => _showPoiDetails(poi),
      ));
    }

    for (final r in _userRestrictions) {
      final key = 'ur_${r.lat}_${r.lng}_${r.createdAt.millisecondsSinceEpoch}';
      final icon = _poiIconCache[key];
      if (icon == null) continue;
      markers.add(Marker(
        markerId: MarkerId(key),
        position: r.position,
        icon: icon,
        infoWindow: InfoWindow(title: r.fullLabel, snippet: 'Toque para gerenciar'),
        onTap: () => _showRestrictionDetails(r),
      ));
    }

    return Scaffold(
      body: Column(
        children: [
          // Mapa ocupa todo o espaço disponível — estrutura do Stack nunca muda
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: _initialPosition,
                  onMapCreated: (c) => _mapController = c,
                  onCameraMove: (pos) {
                    if ((pos.zoom - _currentZoom).abs() > 0.3) {
                      setState(() => _currentZoom = pos.zoom);
                    }
                    _cameraTarget = pos.target;
                  },
                  polylines: polylines,
                  markers: markers,
                  trafficEnabled: true,
                  myLocationButtonEnabled: false,
                ),
                if (!_markingMode) ...[
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Material(
                      color: Colors.white,
                      elevation: 4,
                      shadowColor: Colors.black26,
                      borderRadius: BorderRadius.circular(16),
                      child: _panelCollapsed
                          ? _buildCollapsedPanel()
                          : Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: AddressSearchField(
                                key: _originKey,
                                hint: 'Local de partida',
                                initialValue: _originLabel,
                                indicatorColor: Colors.red.shade400,
                                onSelected: (record) {
                                  setState(() {
                                    _originLabel = record.$1;
                                    _origin      = record.$2;
                                    _originKey   = const ValueKey('origin');
                                  });
                                  context.read<RouteProvider>().clear();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: _locatingGps
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.my_location),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.teal.shade50,
                                foregroundColor: Colors.teal.shade800,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              tooltip: 'Usar minha posição',
                              onPressed: _locatingGps ? null : _useCurrentLocation,
                            ),
                            const SizedBox(width: 4),
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert, color: Colors.teal.shade800),
                              style: ButtonStyle(
                                backgroundColor: WidgetStateProperty.all(Colors.teal.shade50),
                                shape: WidgetStateProperty.all(RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                )),
                              ),
                              onSelected: (value) {
                                if (value == 'history') { _showHistory(); }
                                if (value == 'truck') {
                                  final truckProv = context.read<TruckProfileProvider>();
                                  final routeProv = context.read<RouteProvider>();
                                  final prevId = truckProv.activeId;
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => const TruckProfileScreen(),
                                  )).then((_) {
                                    if (!mounted) return;
                                    if (truckProv.activeId != prevId) routeProv.clear();
                                  });
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'history',
                                  child: Row(children: [
                                    Icon(Icons.history, color: Colors.teal.shade700, size: 20),
                                    const SizedBox(width: 12),
                                    const Text('Histórico'),
                                  ]),
                                ),
                                PopupMenuItem(
                                  value: 'truck',
                                  child: Row(children: [
                                    Icon(Icons.local_shipping, color: Colors.teal.shade700, size: 20),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text('Caminhões'),
                                        Text(
                                          truckProvider.profile.name,
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                        ),
                                      ],
                                    ),
                                  ]),
                                ),
                              ],
                            ),
                            if (_origin != null ||
                                _destination != null ||
                                _waypointPositions.isNotEmpty ||
                                _departureTime != null) ...[
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.clear_all),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.red.shade50,
                                  foregroundColor: Colors.red.shade700,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                tooltip: 'Limpar tudo',
                                onPressed: _clearAll,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        AddressSearchField(
                          key: _destinationKey,
                          hint: 'Local de destino',
                          initialValue: _destinationLabel,
                          indicatorColor: Colors.teal.shade600,
                          biasLocation: _origin,
                          onSelected: (record) {
                            setState(() {
                              _destinationLabel = record.$1;
                              _destination = record.$2;
                            });
                            context.read<RouteProvider>().clear();
                          },
                        ),
                        ..._waypointPositions.asMap().entries.map((entry) {
                          final i = entry.key;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: AddressSearchField(
                                      key: _waypointKeys[i],
                                      hint: 'Parada ${i + 1}',
                                      initialValue: _waypointLabels[i],
                                      indicatorColor: Colors.orange.shade600,
                                      biasLocation: _origin,
                                      onSelected: (record) {
                                        setState(() {
                                          _waypointLabels[i]    = record.$1;
                                          _waypointPositions[i] = record.$2;
                                        });
                                        context.read<RouteProvider>().clear();
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.grey.shade100,
                                      foregroundColor: Colors.grey.shade700,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: () => _removeWaypoint(i),
                                  ),
                                ],
                              ),
                            ],
                          );
                        }),
                        if (_waypointPositions.length < 3)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _addWaypoint,
                              icon: Icon(Icons.add, size: 16, color: Colors.teal.shade700),
                              label: Text(
                                'Adicionar parada',
                                style: TextStyle(color: Colors.teal.shade700, fontSize: 13),
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.schedule, size: 16, color: Colors.grey.shade500),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: _pickDepartureTime,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _departureTime == null ? 'Agora' : _formatDeparture(_departureTime!),
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                ),
                              ),
                            ),
                            if (_departureTime != null)
                              IconButton(
                                icon: Icon(Icons.close, size: 16, color: Colors.grey.shade500),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  setState(() => _departureTime = null);
                                  context.read<RouteProvider>().clear();
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: routeProvider.status == RouteStatus.loading
                                ? null
                                : _calculate,
                            icon: routeProvider.status == RouteStatus.loading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.route),
                            label: const Text('Calcular rota'),
                          ),
                        ),
                        if (routeProvider.status == RouteStatus.error)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              routeProvider.errorMessage ?? 'Erro ao calcular rota',
                              style: const TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                      ),
                    ),
                  ),
                ),
                if (routeProvider.result != null && _panelCollapsed)
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: FloatingActionButton.small(
                      heroTag: 'mark_restriction',
                      onPressed: _enterMarkingMode,
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.teal.shade700,
                      elevation: 3,
                      tooltip: 'Marcar restrição',
                      child: const Icon(Icons.add_location_alt),
                    ),
                  ),
                ],
                if (_showDirtAlternative && result?.dirtRoadAlternative != null)
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Material(
                      elevation: 8,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      color: Colors.white,
                      child: _DirtRoadChoiceSheet(
                        safeRoute: result!,
                        dirtyRoute: result.dirtRoadAlternative!,
                        selectedRoute: _selectedRoute,
                        onChooseSafe: _choosePaved,
                        onChooseDirty: _chooseDirt,
                      ),
                    ),
                  ),
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
          // Card de resultado FORA do Stack — nunca interfere no platform view do mapa
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: routeProvider.result == null
                ? const SizedBox.shrink()
                : _ResultCard(
                    result: routeProvider.result!,
                    onStartNavigation: _startNavigation,
                    onOpenExternal: _launchNavigation,
                    onShare: () => _shareRoute(
                      routeProvider.result!,
                      context.read<TruckProfileProvider>().profile,
                    ),
                    onCopy: () => _copyRoute(
                      routeProvider.result!,
                      context.read<TruckProfileProvider>().profile,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final RouteResult result;
  final VoidCallback onStartNavigation;
  final VoidCallback onOpenExternal;
  final VoidCallback onShare;
  final VoidCallback onCopy;

  const _ResultCard({
    required this.result,
    required this.onStartNavigation,
    required this.onOpenExternal,
    required this.onShare,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        if (result.usedTomTomData)
          const _TomTomBanner(),
        if (result.restrictionsAvoided.isNotEmpty ||
            result.restrictionsBlocked.isNotEmpty)
          _RestrictionsBanner(
            avoided: result.restrictionsAvoided,
            blocked: result.restrictionsBlocked,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _InfoItem(icon: Icons.straighten, label: 'Distância', value: result.distanceText, color: primary),
              _InfoItem(icon: Icons.schedule, label: 'Tempo', value: result.durationText, color: primary),
              Consumer<TruckProfileProvider>(
                builder: (context, p, child) => _InfoItem(
                  icon: Icons.local_shipping,
                  label: 'Caminhão',
                  value: '${p.profile.heightCm}cm · ${(p.profile.weightKg / 1000).toStringAsFixed(0)}t',
                  color: primary,
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy, size: 20, color: primary),
                onPressed: onCopy,
                tooltip: 'Copiar texto',
              ),
              IconButton(
                icon: Icon(Icons.share, size: 20, color: primary),
                onPressed: onShare,
                tooltip: 'Compartilhar',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onStartNavigation,
              icon: const Icon(Icons.navigation),
              label: const Text('Iniciar viagem'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onOpenExternal,
              icon: Icon(Icons.open_in_new, size: 16, color: Colors.grey.shade600),
              label: Text(
                'Abrir em Waze / Google Maps',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _InfoItem({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        const SizedBox(height: 1),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }
}

class _HistorySheet extends StatefulWidget {
  final List<RouteHistory> history;
  final ValueChanged<RouteHistory> onSelect;
  final ValueChanged<int> onDelete;

  const _HistorySheet({
    required this.history,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  late final List<RouteHistory> _items = List.of(widget.history);

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}h'
      '${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Histórico', style: Theme.of(context).textTheme.titleMedium),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _items.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final h = _items[i];
              return ListTile(
                leading: const Icon(Icons.route, size: 20),
                title: Text(
                  '${h.originLabel} → ${h.destinationLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  '${h.distanceText}  •  ${h.durationText}  •  ${_formatDate(h.calculatedAt)}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () {
                    widget.onDelete(i);
                    setState(() => _items.removeAt(i));
                  },
                ),
                onTap: () => widget.onSelect(h),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Helpers de POI (nível de arquivo) ────────────────────────────────────────

IconData _poiIconData(PoiCategory category) => switch (category) {
      PoiCategory.fuel     => Icons.local_gas_station,
      PoiCategory.scale    => Icons.monitor_weight,
      PoiCategory.restArea => Icons.local_hotel,
    };

Color _poiCompatibleColor(PoiCategory category) => switch (category) {
      PoiCategory.fuel     => Colors.amber.shade700,
      PoiCategory.scale    => Colors.purple.shade600,
      PoiCategory.restArea => Colors.teal.shade600,
    };

// ── _PoiSheet ─────────────────────────────────────────────────────────────────

class _PoiSheet extends StatelessWidget {
  final Poi poi;
  final TruckProfile truck;
  final bool canAddWaypoint;
  final VoidCallback onAddToRoute;

  const _PoiSheet({
    required this.poi,
    required this.truck,
    required this.canAddWaypoint,
    required this.onAddToRoute,
  });

  @override
  Widget build(BuildContext context) {
    final compatible = poi.isCompatibleWith(truck);
    final reason     = poi.incompatibilityReason(truck);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_poiIconData(poi.category),
                  color: _poiCompatibleColor(poi.category), size: 20),
              const SizedBox(width: 8),
              Text(poi.categoryLabel,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Text(poi.name,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (poi.description != null) ...[
            const SizedBox(height: 4),
            Text(poi.description!,
                style:
                    TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ],
          const Divider(height: 24),
          Text('Restrições',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _InfoRow(Icons.height, 'Altura máx',
              poi.maxHeightCm != null
                  ? '${(poi.maxHeightCm! / 100).toStringAsFixed(2)}m'
                  : '—'),
          _InfoRow(Icons.straighten, 'Comprimento máx',
              poi.maxLengthCm != null
                  ? '${(poi.maxLengthCm! / 100).toStringAsFixed(2)}m'
                  : '—'),
          _InfoRow(Icons.scale, 'Peso máx',
              poi.maxWeightKg != null
                  ? '${(poi.maxWeightKg! / 1000).toStringAsFixed(0)}t'
                  : '—'),
          if (poi.category == PoiCategory.fuel)
            _InfoRow(Icons.local_gas_station, 'Diesel',
                poi.hasDiesel ? 'Sim' : 'Não'),
          const SizedBox(height: 16),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: compatible
                  ? Colors.green.shade50
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  compatible ? Icons.check_circle : Icons.cancel,
                  color: compatible
                      ? Colors.green.shade600
                      : Colors.grey.shade500,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    compatible
                        ? 'Compatível com seu caminhão'
                        : reason ?? 'Incompatível com seu caminhão',
                    style: TextStyle(
                      fontSize: 13,
                      color: compatible
                          ? Colors.green.shade700
                          : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canAddWaypoint ? onAddToRoute : null,
              icon: const Icon(Icons.add_location_alt),
              label: Text(canAddWaypoint
                  ? 'Adicionar como parada'
                  : 'Máximo de paradas atingido (3)'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TomTomBanner extends StatelessWidget {
  const _TomTomBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.teal.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.teal.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.verified_outlined, color: Colors.teal.shade700, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Rota otimizada com TomTom — restrições adicionais detectadas',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.teal.shade800,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestrictionsBanner extends StatelessWidget {
  final List<BridgeRestriction> avoided;
  final List<BridgeRestriction> blocked;

  const _RestrictionsBanner({required this.avoided, required this.blocked});

  @override
  Widget build(BuildContext context) {
    final hasBlocked = blocked.isNotEmpty;
    final color  = hasBlocked ? Colors.amber.shade700  : Colors.green.shade600;
    final bgColor = hasBlocked ? Colors.amber.shade50  : Colors.green.shade50;
    final border  = hasBlocked ? Colors.amber.shade300 : Colors.green.shade200;
    final icon    = hasBlocked ? Icons.warning_amber_rounded : Icons.check_circle_outline;

    final String message;
    if (hasBlocked) {
      final labels = blocked.map((r) => r.label).join(', ');
      message = blocked.length == 1
          ? 'Restrição não contornável: $labels'
          : '${blocked.length} restrições não contornáveis: $labels';
    } else {
      final total      = avoided.length;
      final unverified = avoided.where((r) => !r.isVerified).length;
      if (unverified == 0) {
        message = total == 1
            ? '1 restrição contornada automaticamente'
            : '$total restrições contornadas automaticamente';
      } else if (unverified == total) {
        message = total == 1
            ? '1 restrição contornada (aguardando confirmação de outros motoristas)'
            : '$total restrições contornadas (não verificadas — aguardando mais relatos)';
      } else {
        final verified = total - unverified;
        message = '$total restrições contornadas ($verified verificadas, $unverified aguardando confirmação)';
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Text(label,
              style:
                  TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ── _MarkingOnboardingSheet ───────────────────────────────────────────────────

class _MarkingOnboardingSheet extends StatelessWidget {
  const _MarkingOnboardingSheet();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.add_location_alt, color: primary, size: 22),
              const SizedBox(width: 10),
              Text('Marcar restrição de via',
                  style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Use quando encontrar:',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 10),
          _OnboardingItem(Icons.height,         'Viaduto com altura limitada'),
          _OnboardingItem(Icons.monitor_weight, 'Via com restrição de peso'),
          _OnboardingItem(Icons.swap_horiz,     'Passagem com largura baixa'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primary.withAlpha(15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: primary.withAlpha(40)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Arraste o mapa até o local exato, confirme e informe o valor. '
                    'Os dados coletados melhoram as rotas para todos os motoristas.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _OnboardingItem(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

// ── _RestrictionDetailSheet ───────────────────────────────────────────────────

class _RestrictionDetailSheet extends StatelessWidget {
  final UserRestriction restriction;
  const _RestrictionDetailSheet({required this.restriction});

  String _formatDate(DateTime dt) {
    final d   = dt.day.toString().padLeft(2, '0');
    final m   = dt.month.toString().padLeft(2, '0');
    final h   = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/${dt.year} ${h}h$min';
  }

  @override
  Widget build(BuildContext context) {
    final r = restriction;
    final iconData = switch (r.type) {
      'maxheight' => Icons.height,
      'maxweight' => Icons.monitor_weight,
      _           => Icons.swap_horiz,
    };
    final color = switch (r.type) {
      'maxheight' => Colors.red.shade700,
      'maxweight' => Colors.brown.shade600,
      _           => Colors.deepOrange.shade600,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iconData, color: color, size: 20),
              const SizedBox(width: 8),
              Text('Restrição marcada manualmente',
                  style: TextStyle(
                      color: Colors.grey.shade600, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Text(r.fullLabel,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Adicionada em ${_formatDate(r.createdAt)}',
              style:
                  TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          const Divider(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text('Remover restrição',
                  style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sheet de escolha: rota segura vs rota com estrada de terra ─────────────────

class _DirtRoadChoiceSheet extends StatelessWidget {
  final RouteResult safeRoute;
  final RouteResult dirtyRoute;
  final String? selectedRoute;
  final VoidCallback onChooseSafe;
  final VoidCallback onChooseDirty;

  const _DirtRoadChoiceSheet({
    required this.safeRoute,
    required this.dirtyRoute,
    required this.selectedRoute,
    required this.onChooseSafe,
    required this.onChooseDirty,
  });

  @override
  Widget build(BuildContext context) {
    final savingMin = (safeRoute.durationSeconds - dirtyRoute.durationSeconds) ~/ 60;
    final pavedSelected = selectedRoute == 'paved';
    final dirtSelected  = selectedRoute == 'dirt';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fork_right, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Duas rotas disponíveis',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              if (selectedRoute == null)
                Text('Toque na rota no mapa',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 16),
          _RouteOption(
            icon: Icons.verified_outlined,
            iconColor: Colors.green.shade700,
            title: 'Rota pavimentada',
            subtitle: '${safeRoute.durationText}  •  ${safeRoute.distanceText}',
            note: null,
            highlighted: pavedSelected,
            highlightColor: const Color(0xFF1565C0),
          ),
          const SizedBox(height: 10),
          _RouteOption(
            icon: Icons.warning_amber_rounded,
            iconColor: Colors.orange.shade700,
            title: 'Rota com estrada de terra',
            subtitle: '${dirtyRoute.durationText}  •  ${dirtyRoute.distanceText}',
            note: '$savingMin min mais rápida — pode ser intransitável para carretas',
            highlighted: dirtSelected,
            highlightColor: Colors.orange.shade700,
          ),
          const SizedBox(height: 20),
          if (selectedRoute != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: pavedSelected ? const Color(0xFF1565C0) : Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    pavedSelected ? 'Confirmando rota pavimentada…' : 'Confirmando rota com terra…',
                    style: TextStyle(
                      fontSize: 12,
                      color: pavedSelected ? const Color(0xFF1565C0) : Colors.orange.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onChooseSafe,
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Rota segura'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                  ),
                  onPressed: onChooseDirty,
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('Eu decido'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RouteOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? note;
  final bool highlighted;
  final Color highlightColor;

  const _RouteOption({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.note,
    this.highlighted = false,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlighted ? highlightColor.withAlpha(18) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlighted ? highlightColor : Colors.grey.shade300,
          width: highlighted ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade700)),
                if (note != null) ...[
                  const SizedBox(height: 4),
                  Text(note!,
                      style: TextStyle(
                          fontSize: 12, color: Colors.orange.shade800)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
