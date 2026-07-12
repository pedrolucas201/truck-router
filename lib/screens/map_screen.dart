import 'dart:async';
import 'dart:math';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/geo_uri_parser.dart';
import '../utils/geo_bounds.dart';
import '../data/pois.dart';
import '../models/bridge_restriction.dart';
import '../models/poi.dart';
import '../models/radar_point.dart';
import '../models/route_history.dart';
import '../models/route_result.dart';
import '../models/truck_profile.dart';
import '../services/history_service.dart';
import '../services/places_service.dart';
import '../services/favorites_service.dart';
import '../providers/route_provider.dart';
import '../providers/truck_profile_provider.dart';
import '../services/here_geocoding_service.dart';
import '../services/field_log.dart';
import '../services/radar_service.dart';
import '../services/firestore_radar_service.dart';
import '../widgets/address_search_field.dart';
import '../widgets/add_restriction_sheet.dart';
import '../widgets/crosshair.dart';
import '../widgets/map/blocked_sheet.dart';
import '../widgets/map/dirt_road_choice_sheet.dart';
import '../widgets/map/history_sheet.dart';
import '../widgets/map/marker_icons.dart';
import '../widgets/map/marking_onboarding_sheet.dart';
import '../widgets/map/poi_sheet.dart';
import '../widgets/map/police_sheets.dart';
import '../widgets/map/restriction_detail_sheet.dart';
import '../widgets/map/result_card.dart';
import '../widgets/speed_plate.dart';
import 'truck_profile_screen.dart';
import 'navigation_screen.dart';
import '../models/police_alert.dart';
import '../models/user_restriction.dart';
import '../services/auth_service.dart';
import '../services/police_alert_service.dart';
import '../services/restriction_service.dart';
import '../repositories/restriction_repository.dart';
import '../data/map_styles.dart';
import '../providers/theme_controller.dart';
import '../utils/truck_glyph.dart';
import '../widgets/route_loading_indicator.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  late ThemeController _themeController;
  String?   _lastHandledUri;
  DateTime? _lastHandledAt;
  bool      _openedViaDeepLink = false;
  String?   _loadingTruckAsset;
  LatLng? _origin;
  LatLng? _destination;
  String? _originLabel;
  String? _destinationLabel;
  DateTime? _departureTime;
  Key _originKey      = const ValueKey('origin');
  Key _destinationKey = const ValueKey('destination');
  StreamSubscription<Uri>? _deepLinkSub;
  bool _locatingGps = false;
  final _waypointPositions = <LatLng?>[];
  final _waypointLabels    = <String?>[];
  final _waypointKeys      = <Key>[];
  int   _waypointKeySeq    = 0;
  final _poiIconCache      = <String, BitmapDescriptor>{};
  List<RadarPoint>         _nearbyRadares = [];
  List<UserRestriction>    _userRestrictions = [];
  List<PoliceAlert>        _policeAlerts = [];
  StreamSubscription<List<PoliceAlert>>? _policeAlertSub;
  double                   _currentZoom = 11.0;
  bool                     _markingMode = false;
  bool                     _panelCollapsed = false;
  bool                     _showDirtAlternative = false;
  bool                     _showTruckTip = false;
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
    _loadTruckTip();
    _seedPlaces();
    _initDeepLinks();
    _themeController = context.read<ThemeController>();
    _themeController.addListener(_onThemeChanged);
  }

  // Semeia a memória de lugares a partir do histórico de rotas (uma vez), pra
  // os recentes/sugestões já funcionarem com o que o usuário usou no passado.
  Future<void> _seedPlaces() async {
    final h = await HistoryService.load(); // recente primeiro
    final pairs = <(String, LatLng)>[];
    for (final e in h) {
      pairs.add((e.destinationLabel, e.destinationPosition));
      pairs.add((e.originLabel, e.originPosition));
    }
    await PlacesService.seedIfEmpty(pairs);
  }

  Future<void> _loadTruckTip() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool('truck_tip_shown') ?? false;
    if (!shown && mounted) {
      setState(() => _showTruckTip = true);
      Future.delayed(const Duration(seconds: 5), _dismissTruckTip);
    }
  }

  Future<void> _dismissTruckTip() async {
    if (!mounted) return;
    setState(() => _showTruckTip = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('truck_tip_shown', true);
  }

  Future<void> _initDeepLinks() async {
    final appLinks = AppLinks();
    final initial = await appLinks.getInitialLink();
    if (initial != null) {
      // App process só existe porque o sistema abriu via deep link (cold start) —
      // distingue do caso "app já aberto recebe novo link" via uriLinkStream abaixo.
      _openedViaDeepLink = true;
      if (mounted) _handleIncomingUri(initial);
    }
    _deepLinkSub = appLinks.uriLinkStream.listen(
      (uri) { if (mounted) _handleIncomingUri(uri); },
      // Sem onError, um link malformado no stream mata o recebimento de links
      // pro resto da sessão — silenciosamente.
      onError: (Object e, StackTrace st) => FieldLog.error('deeplink_stream', e, st),
    );
  }

  void _handleIncomingUri(Uri uri) {
    final uriStr = uri.toString();
    final now    = DateTime.now();
    if (uriStr == _lastHandledUri &&
        _lastHandledAt != null &&
        now.difference(_lastHandledAt!) < const Duration(seconds: 5)) {
      return;
    }
    _lastHandledUri = uriStr;
    _lastHandledAt  = now;

    final type = classifyMapsUri(uri);
    if (type == DeepLinkType.route) {
      final route = parseMapsUri(uri);
      if (route != null) {
        _setDeepLinkRoute(route);
        return;
      }
    } else if (type == DeepLinkType.destination) {
      // Pin de localização do WhatsApp (maps.google.com?q=lat,lng) — vira destino.
      final dest = parseMapsDestination(uri);
      if (dest != null) {
        _handleGeoUri(dest);
        return;
      }
    } else {
      final geo = parseGeoUri(uri);
      if (geo != null) {
        _handleGeoUri(geo);
        return;
      }
    }

    // Nenhum parser reconheceu o link. Loga o URI cru no field_logs — sem isso
    // dependíamos do motorista printar a tela pra saber o formato que falhou.
    FieldLog.event('deeplink_unrecognized', {'uri': uriStr});
    // Mostra o URI cru pra capturar formatos inesperados em campo (ex: shortlink
    // maps.app.goo.gl).
    // TODO(N4): após confirmar o formato real do WhatsApp em device, trocar por
    // mensagem genérica ("Não consegui ler esta localização compartilhada").
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Link não reconhecido: $uriStr'),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  void _setDeepLinkRoute(MapsRoute route) {
    setState(() {
      _destination      = route.destination;
      _destinationLabel = 'Destino compartilhado';
      _destinationKey   = ValueKey('dest_shared_${DateTime.now().millisecondsSinceEpoch}');
      if (route.origin != null) {
        _origin      = route.origin;
        _originLabel = 'Origem compartilhada';
        _originKey   = ValueKey('origin_shared_${DateTime.now().millisecondsSinceEpoch}');
      }
    });
    context.read<RouteProvider>().clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(route.origin != null
            ? 'Rota recebida — toque em Calcular para rotear'
            : 'Destino recebido — toque em Calcular para rotear'),
        duration: const Duration(seconds: 4),
      ),
    );
    if (_origin != null && _destination != null) _calculate();
  }

  void _handleGeoUri(GeoLocation geo) {
    if (_destination != null) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Usar como destino?'),
          content: const Text('Isso vai substituir o destino atual.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _setDeepLinkDestination(geo);
              },
              child: const Text('Usar'),
            ),
          ],
        ),
      );
    } else {
      _setDeepLinkDestination(geo);
    }
  }

  void _setDeepLinkDestination(GeoLocation geo) {
    setState(() {
      _destination      = geo.coords;
      _destinationLabel = geo.label ?? 'Localização compartilhada';
      _destinationKey   = ValueKey('dest_deep_${DateTime.now().millisecondsSinceEpoch}');
    });
    context.read<RouteProvider>().clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Destino recebido — toque em Calcular para rotear'),
        duration: Duration(seconds: 4),
      ),
    );
    if (_origin != null) _calculate();
  }

  @override
  void dispose() {
    _routeSelectionTimer?.cancel();
    _deepLinkSub?.cancel();
    _policeAlertSub?.cancel();
    _themeController.removeListener(_onThemeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
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
        final color = compatible ? poiCompatibleColor(category) : Colors.grey.shade500;
        _poiIconCache['${category.name}_$compatible'] =
            await buildPoiIcon(color, poiIconData(category));
      }
    }
    _poiIconCache['label_paved'] = await buildRouteLabelIcon(
      'Pavimentada', const Color(0xFF1565C0), Icons.verified_outlined);
    _poiIconCache['label_dirt'] = await buildRouteLabelIcon(
      'Estrada de terra', Colors.orange.shade700, Icons.warning_amber_rounded);
    if (mounted) setState(() {});
  }

  Future<void> _loadUserRestrictions() async {
    final local = await RestrictionService.load();
    var restrictions = local;

    if (local.isNotEmpty && mounted) {
      try {
        final (:minLat, :maxLat, :minLng, :maxLng) =
            boundsOf(local.map((r) => LatLng(r.lat, r.lng)).toList());
        const pad = 0.01;
        final remote = await context.read<RestrictionRepository>().fetchByBounds(
          minLat - pad, maxLat + pad, minLng - pad, maxLng + pad,
        );
        if (remote.isNotEmpty) {
          restrictions = local.map((r) {
            BridgeRestriction? match;
            for (final b in remote) {
              if ((b.lat - r.lat).abs() < 0.0001 && (b.lng - r.lng).abs() < 0.0001) {
                match = b;
                break;
              }
            }
            if (match == null || match.confirmedBy == r.confirmedBy) return r;
            return UserRestriction(
              id: r.id ?? match.id, lat: r.lat, lng: r.lng, type: r.type,
              value: r.value, createdAt: r.createdAt, confirmedBy: match.confirmedBy,
            );
          }).toList();
        }
      } catch (_) {}
    }

    for (final r in restrictions) {
      final key = 'ur_${r.lat}_${r.lng}_${r.createdAt.millisecondsSinceEpoch}_${r.isVerified}';
      if (!_poiIconCache.containsKey(key)) {
        _poiIconCache[key] = await buildRestrictionIcon(r);
      }
    }
    if (mounted) setState(() => _userRestrictions = restrictions);
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
        final id = await repo.add(r, uid);
        final rWithId = UserRestriction(
          id: id, lat: r.lat, lng: r.lng, type: r.type,
          value: r.value, createdAt: r.createdAt, confirmedBy: r.confirmedBy,
        );
        await RestrictionService.remove(r);
        await RestrictionService.add(rWithId);
        if (mounted) {
          setState(() {
            final idx = _userRestrictions.indexWhere(
              (x) => x.lat == r.lat && x.lng == r.lng && x.createdAt == r.createdAt,
            );
            if (idx != -1) _userRestrictions[idx] = rWithId;
          });
        }
      } catch (_) {}
    }();

    final key = 'ur_${r.lat}_${r.lng}_${r.createdAt.millisecondsSinceEpoch}_${r.isVerified}';
    final icon = await buildRestrictionIcon(r);
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
        builder: (_) => const MarkingOnboardingSheet(),
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
      builder: (_) => RestrictionDetailSheet(restriction: r),
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
    if (result.maxTruckSpeedKmh != null) {
      buf.writeln('Vel. máx. caminhão na rota: ${result.maxTruckSpeedKmh} km/h');
    }
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
    final text = StringBuffer(_buildShareText(result, truck));
    if (_origin != null && _destination != null) {
      final url = 'https://maps.google.com/maps'
          '?saddr=${_origin!.latitude},${_origin!.longitude}'
          '&daddr=${_destination!.latitude},${_destination!.longitude}';
      text.writeln('\n\nAbrir no Truck Router:');
      text.write(url);
    }
    Share.share(text.toString(), subject: 'Rota do Caminhão');
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
      await _launchNav(googleMapsUrl);
      return;
    }
    if (hasWaze && !hasGoogleMaps) {
      await _launchNav(wazeUrl);
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
                _launchNav(googleMapsUrl);
              },
            ),
            ListTile(
              leading: const Icon(Icons.navigation, color: Color(0xFF00CCFF)),
              title: const Text('Waze'),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onTap: () {
                Navigator.pop(context);
                _launchNav(wazeUrl);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Abre o app de navegação externo. Guard único dos 4 call-sites: launchUrl
  /// pode retornar false ou lançar (nenhum handler p/ o esquema) — antes o toque
  /// não fazia nada, sem sinal pro motorista nem pra nós.
  Future<void> _launchNav(Uri url) async {
    bool ok = false;
    try {
      ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e, st) {
      FieldLog.error('nav_launch', e, st);
    }
    if (!ok) {
      FieldLog.event('nav_launch_fail', {'scheme': url.scheme});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não consegui abrir o app de navegação')),
        );
      }
    }
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
        // Radar removido dentro da nav sai também do cache do mapa — senão
        // reaparecia ao reabrir a navegação (a dispensa já foi pro Firestore).
        onRadarRemoved:   (r) {
          if (!mounted) return;
          setState(() => _nearbyRadares = _nearbyRadares
              .where((x) => !(x.lat == r.lat && x.lng == r.lng && x.type == r.type))
              .toList());
        },
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _calculate();
    });
  }

  Future<void> _showHistory() async {
    final history   = await HistoryService.load();
    final favorites = await FavoritesService.load();
    if (!mounted) return;
    if (history.isEmpty && favorites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhuma rota salva ainda')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (_) => HistorySheet(
        history: history,
        favorites: favorites,
        onSelect: (h) {
          Navigator.pop(context);
          _restoreHistory(h);
        },
        onDelete: (index) => HistoryService.remove(index),
        onFavorite: (h) => FavoritesService.add(h),
        onUnfavorite: (h) => FavoritesService.remove(h),
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
      builder: (_) => PoiSheet(
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

  // Toque num radar no mapa: curadoria do Gilberto (palavra = fato). Não existe →
  // some; existe → mantém; existe @ X → troca a velocidade. Override local-first +
  // Firestore. Editável passando de novo. Mesma folha da navegação.
  Future<void> _onRadarTap(RadarPoint r) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: Text(r.speedKmh > 0
                ? 'Radar ${r.speedKmh} km/h'
                : (r.type.isEmpty ? 'Radar' : r.type)),
            subtitle: const Text('Existe aqui? Qual a velocidade real?'),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final s in [60, 70, 80, 90])
                  SpeedPlate(
                      kmh: s, onTap: () => Navigator.pop(context, 'speed:$s')),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: const Text('Existe (manter velocidade)'),
            onTap: () => Navigator.pop(context, 'confirm'),
          ),
          ListTile(
            leading: const Icon(Icons.cancel, color: Colors.red),
            title: const Text('Não existe aqui'),
            onTap: () => Navigator.pop(context, 'remove'),
          ),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    final uid = await AuthService.getUid();
    bool sameAs(RadarPoint x) => x.lat == r.lat && x.lng == r.lng && x.type == r.type;

    if (action == 'remove') {
      await FirestoreRadarService.setOverride(
          lat: r.lat, lng: r.lng, exists: false, uid: uid);
      if (!mounted) return;
      setState(() => _nearbyRadares =
          _nearbyRadares.where((x) => !sameAs(x)).toList());
      return;
    }
    final speed = action.startsWith('speed:') ? int.parse(action.substring(6)) : 0;
    await FirestoreRadarService.setOverride(
        lat: r.lat, lng: r.lng, exists: true, speedKmh: speed, uid: uid);
    if (!mounted || speed <= 0) return;
    setState(() => _nearbyRadares = _nearbyRadares
        .map((x) => sameAs(x) ? x.copyWith(speedKmh: speed) : x)
        .toList());
  }

  Future<void> _calculate() async {
    _loadingTruckAsset = null;
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
      final csvFiltered = RadarService.deduplicateNearby(
        RadarService.filterNearRoute(allRadares, result.polylinePoints),
      ).where((r) => !(r.type.toLowerCase().contains('lombada') && r.speedKmh == 0)).toList();
      // Merge crowd: + radares adicionados, − os dispensados por voto.
      final filtered = await FirestoreRadarService.mergeCrowd(csvFiltered, result.polylinePoints);
      // Gera ícones só para os speeds que aparecem nesta rota
      for (final r in filtered) {
        final isLombada = r.type.toLowerCase().contains('lombada');
        final isPedagio = r.type.toLowerCase().contains('pedagio');
        final key = isPedagio
            ? 'pedagio'
            : '${isLombada ? 'lombada' : 'radar'}_${r.speedKmh}';
        if (!_poiIconCache.containsKey(key)) {
          _poiIconCache[key] = await buildRadarIcon(
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
        final (:minLat, :maxLat, :minLng, :maxLng) = boundsOf(pts);
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
                  Container(width: 2, height: 12, color: _themeController.isNight ? Colors.grey.shade600 : Colors.grey.shade300),
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
                    style: TextStyle(fontSize: 12, color: _themeController.isNight ? Colors.grey.shade400 : Colors.grey.shade600),
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

  void _refreshPoliceAlerts(LatLngBounds bounds) {
    _policeAlertSub?.cancel();
    _policeAlertSub = PoliceAlertService.streamInBounds(
      bounds.southwest.latitude,
      bounds.northeast.latitude,
      bounds.southwest.longitude,
      bounds.northeast.longitude,
    ).listen((alerts) {
      if (mounted) setState(() => _policeAlerts = alerts);
    });
  }

  Future<void> _showPoliceAlertSheet(PoliceAlert alert) async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => PoliceAlertSheet(alert: alert),
    );
  }

  Future<void> _showReportPoliceSheet() async {
    final uid = await AuthService.getUid();
    if (!mounted) return;
    final type = await showModalBottomSheet<PoliceAlertType>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const ReportPoliceSheet(),
    );
    if (type == null) return;
    await PoliceAlertService.report(
      type: type,
      lat: _cameraTarget.latitude,
      lng: _cameraTarget.longitude,
      uid: uid,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alerta reportado'),
          duration: Duration(seconds: 2),
        ),
      );
    }
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
      if (!dirtDimmed) {
        polylines.add(Polyline(
          polylineId: const PolylineId('route_dirt_halo'),
          points: dirtPts,
          color: Colors.orange.shade700.withAlpha(90),
          width: 18,
          patterns: [PatternItem.dash(24), PatternItem.gap(12)],
          zIndex: 0,
        ));
      }
      polylines.add(Polyline(
        polylineId: const PolylineId('route_dirt'),
        points: dirtPts,
        color: Colors.orange.shade700.withAlpha(dirtDimmed ? 60 : 255),
        width: dirtDimmed ? 5 : 10,
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
      if (!pavedDimmed) {
        polylines.add(Polyline(
          polylineId: const PolylineId('route_halo'),
          points: pts,
          color: const Color(0xFF1565C0).withAlpha(90),
          width: 18,
          zIndex: 1,
        ));
      }
      polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: pts,
        color: const Color(0xFF1565C0).withAlpha(pavedDimmed ? 60 : 255),
        width: pavedDimmed ? 5 : 10,
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
          onTap: () => _onRadarTap(r),
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
      final key = 'ur_${r.lat}_${r.lng}_${r.createdAt.millisecondsSinceEpoch}_${r.isVerified}';
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

    for (final alert in _policeAlerts) {
      markers.add(Marker(
        markerId: MarkerId('police_${alert.id}'),
        position: alert.position,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          switch (alert.type) {
            PoliceAlertType.radar  => BitmapDescriptor.hueOrange,
            PoliceAlertType.police => BitmapDescriptor.hueBlue,
            PoliceAlertType.blitz  => BitmapDescriptor.hueRed,
          },
        ),
        infoWindow: InfoWindow(
          title: switch (alert.type) {
            PoliceAlertType.radar  => 'Radar',
            PoliceAlertType.police => 'Polícia',
            PoliceAlertType.blitz  => 'Blitz',
          },
          snippet: alert.timeRemainingText,
        ),
        onTap: () => _showPoliceAlertSheet(alert),
      ));
    }

    // N4 (2ª iteração): se o app só existe nesta tela porque o sistema abriu
    // via deep link (WhatsApp etc.) e o usuário não chegou a calcular rota,
    // back deve encerrar o app de fato — não só desempilhar/minimizar — para
    // o sistema voltar o foco pra task de origem (ex.: WhatsApp) em vez de
    // deixar o Truck Router de pé sobre ela.
    final exitAppOnBack = _openedViaDeepLink && routeProvider.status == RouteStatus.idle;

    return PopScope(
      canPop: !exitAppOnBack,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) SystemNavigator.pop();
      },
      child: Scaffold(
      body: Column(
        children: [
          // Mapa ocupa todo o espaço disponível — estrutura do Stack nunca muda
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: _initialPosition,
                  onMapCreated: (c) {
                    _mapController = c;
                  },
                  style: _themeController.isNight ? kNightMapStyle : null,
                  onCameraMove: (pos) {
                    if ((pos.zoom - _currentZoom).abs() > 0.3) {
                      setState(() => _currentZoom = pos.zoom);
                    }
                    _cameraTarget = pos.target;
                  },
                  onCameraIdle: () async {
                    final bounds = await _mapController?.getVisibleRegion();
                    if (bounds != null) _refreshPoliceAlerts(bounds);
                  },
                  polylines: polylines,
                  markers: markers,
                  trafficEnabled: false,
                  myLocationButtonEnabled: false,
                ),
                if (!_markingMode) ...[
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Material(
                      color: _themeController.isNight ? const Color(0xFF1E1E1E) : Colors.white,
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
                          child: routeProvider.status == RouteStatus.loading
                              ? FilledButton(
                                  onPressed: null,
                                  child: RouteLoadingIndicator(
                                    truckAsset: _loadingTruckAsset ??= randomLoaderAsset(),
                                    bare: true,
                                  ),
                                )
                              : FilledButton.icon(
                                  onPressed: _calculate,
                                  icon: const Icon(Icons.route),
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
                if (!_markingMode)
                  Positioned(
                    bottom: routeProvider.result != null && _panelCollapsed ? 64 : 16,
                    right: 16,
                    child: FloatingActionButton.small(
                      heroTag: 'report_police',
                      onPressed: _showReportPoliceSheet,
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blue.shade700,
                      elevation: 3,
                      tooltip: 'Reportar polícia',
                      child: const Icon(Icons.local_police_outlined),
                    ),
                  ),
                if (_showTruckTip)
                  Positioned(
                    top: 100,
                    right: 12,
                    child: GestureDetector(
                      onTap: _dismissTruckTip,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 14),
                            child: CustomPaint(
                              size: const Size(12, 8),
                              painter: UpArrowPainter(
                                  color: Theme.of(context).colorScheme.primary),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: const [
                                BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 6,
                                    offset: Offset(0, 2))
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.local_shipping_rounded,
                                    color: Colors.white, size: 15),
                                const SizedBox(width: 6),
                                Text(
                                  'Configure seu caminhão aqui',
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimary,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
                      child: DirtRoadChoiceSheet(
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
                : ResultCard(
                    result: routeProvider.result!,
                    departureTime: _departureTime,
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
                    onBlockedTap: routeProvider.result!.restrictionsBlocked.isEmpty
                        ? null
                        : () => showModalBottomSheet(
                              context: context,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                              ),
                              builder: (_) => BlockedSheet(
                                blocked: routeProvider.result!.restrictionsBlocked,
                                onAddWaypoint: () {
                                  setState(() => _panelCollapsed = false);
                                  _addWaypoint();
                                },
                              ),
                            ),
                  ),
          ),
        ],
      ),
      ),
    );
  }
}
