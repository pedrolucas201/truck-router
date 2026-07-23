import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show listEquals, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
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
import '../services/radar_direction.dart';
import '../services/firestore_radar_service.dart';
import '../utils/radar_tts.dart';
import '../utils/geo_angle.dart';
import '../utils/geo_bounds.dart';
import '../utils/maneuver_phrase.dart';
import '../services/restriction_service.dart';
import '../data/map_styles.dart';
import '../data/pois.dart';
import '../models/poi.dart';
import '../models/route_event.dart';
import '../models/weather_alert.dart';
import '../widgets/map/marker_icons.dart';
import '../providers/theme_controller.dart';
import '../widgets/add_restriction_sheet.dart';
import '../widgets/add_radar_sheet.dart';
import '../widgets/crosshair.dart';
import '../widgets/next_event_strip.dart';
import '../widgets/speed_plate.dart';
import '../widgets/upcoming_dots.dart';
import '../widgets/nav/bottom_bar.dart';
import '../widgets/nav/instruction_bar.dart';
import '../widgets/nav/nav_puck.dart';
import '../widgets/nav/nav_ui_defs.dart';

@pragma('vm:entry-point')
void _navForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_NavTaskHandler());
}

class _NavTaskHandler extends TaskHandler {
  @override Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override void onRepeatEvent(DateTime timestamp) {}
  @override Future<void> onDestroy(DateTime timestamp) async {}
}

// Velocidade FÍSICA mínima pra confiar no rumo do GPS. Abaixo disso o heading é
// ruído (parado, o GPS gira sozinho).
const kRerouteCourseMinKmh = 8.0;

// Janela em que um move de câmera ainda pode ser CONSEQUÊNCIA de um toque (o
// settle/inércia chega depois do dedo sair). Fora dela, move sem toque = move
// NOSSO, nunca gesto.
const kGestureGraceMs = 1200;

// Puro/testável: este move de câmera é um GESTO do motorista (→ olhar-ao-redor)?
//
// Portão duro: gesto tem DEDO. Sem toque recente no mapa, nenhum move vira gesto —
// ponto. O discriminador geométrico (isEcho) sozinho é indefensável: o padding do
// mapa faz a plataforma reportar um alvo deslocado do que comandamos, e esse
// deslocamento é fixo em PIXELS — em metros ele cresce ao recuar o zoom E muda com
// o tamanho da TELA do aparelho. Não existe constante em metros que sirva pra todo
// device/zoom, e foi por isso que este P0 ressuscitou release após release com cara
// nova (campo 2026-07-13: 6 free-looks espúrios, panM=127m, ninguém tocando na tela).
// O dedo não depende de nada disso: settle de câmera NUNCA tem toque; arrasto real
// SEMPRE tem.
//
// isEcho fica como 2ª linha: DENTRO de um toque real, separa o arrasto (alvo novo)
// do eco do follow. E fingerActive cobre o arrasto COLINEAR (pra frente), que cai
// perto da rota e pareceria eco.
bool cameraMoveIsGesture({
  required int touchAgeMs, // -1 = nunca tocou no mapa
  required bool isEcho,
  required bool fingerActive,
  required bool zoomJustChanged,
}) {
  final touchedRecently = touchAgeMs >= 0 && touchAgeMs < kGestureGraceMs;
  return touchedRecently && ((!isEcho && !zoomJustChanged) || fingerActive);
}

// Puro/testável: dá pra confiar no rumo do GPS deste fix?
//
// Mede a velocidade FÍSICA (a do próprio fix), NUNCA a velocidade ao longo da
// rota — esta zera quando o caminhão não avança NA rota, que é exatamente o caso
// de quem anda CONTRA ela, e é justo aí que o rumo é indispensável. Fonte ÚNICA:
// quem decide "desviou?" e quem decide "mando o course pra HERE?" têm que usar
// esta mesma resposta. Duas leituras divergentes disso foi o deadlock de campo de
// 2026-07-13 (42 reroutes em 13 min).
bool headingIsReliable(double rawSpeedMps, double headingDeg) =>
    rawSpeedMps * 3.6 >= kRerouteCourseMinKmh && headingDeg >= 0;

// Metros por pixel na projeção do Google Maps (Web Mercator) no zoom/latitude
// dados. É o que converte um erro de TELA em erro de MUNDO.
double metersPerPixel(double zoom, double lat) =>
    156543.03392 * cos(lat * pi / 180) / pow(2, zoom);

// Tolerância do eco, em PIXELS de tela. O erro que ela precisa absorver é o
// offset do padding da câmera (o mapa é padded pra jogar o puck em _puckYFrac):
// o alvo reportado pela plataforma não é o que comandamos, e a diferença é fixa
// em PIXELS. Convertida pra metros ela QUADRUPLICA a cada 2 níveis de zoom.
const _echoTolPx = 60.0;

// Puro/testável: o alvo da câmera bate com algum move que NÓS comandamos?
// Sim → eco do follow (ignora). Não → dedo do usuário (free-look). É o
// discriminador que separa nosso próprio moveCamera (mesmo atrasado por stall)
// de um gesto real, matando o free-look "do nada" reportado em campo.
//
// A tolerância escala com o zoom porque o erro que ela absorve é de tela, não de
// mundo. Antes era 40m FIXOS: no zoom 17 (padrão) o offset dá ~32m e passava por
// baixo dos 40 por 8m de sorte; no zoom 15 (recuado) vira ~128m e TODO move nosso
// era lido como dedo → free-look → botão azul voltando sozinho. Campo 2026-07-13:
// 6 freelook_enter com cause=pan e panM travado em 127m. Bater metro contra um
// erro de pixel é a raiz — os patches anteriores (_zoomJustChanged, janela de
// 900ms) mascaravam um caller de cada vez.
bool targetIsEcho(List<LatLng> cmds, LatLng target, double zoom) {
  // Piso de 40m = a tolerância antiga. Só ALARGA onde o pixel pede (zoom recuado),
  // nunca aperta: no zoom aproximado a conta daria ~16m e apertar ali plantaria um
  // free-look espúrio novo pra consertar o antigo. Fix de P0 não inventa P0.
  final tolM = max(40.0, _echoTolPx * metersPerPixel(zoom, target.latitude));
  return cmds.any((t) =>
      RadarService.haversine(
          t.latitude, t.longitude, target.latitude, target.longitude) <
      tolM);
}

class NavigationScreen extends StatefulWidget {
  final RouteResult result;
  final LatLng destination;
  final TruckProfile truck;
  final String destinationLabel;
  final List<LatLng> waypoints;
  final List<RadarPoint> initialRadares;
  // Células de clima severo na rota (snapshot do cálculo, como initialRadares).
  final List<WeatherAlert> initialWeatherAlerts;
  // Avisa o mapa quando um radar é removido aqui (voto "não existe"), pra ele
  // podar a lista em cache e o radar não reaparecer ao reabrir a navegação.
  final void Function(RadarPoint)? onRadarRemoved;

  const NavigationScreen({
    super.key,
    required this.result,
    required this.destination,
    required this.truck,
    required this.destinationLabel,
    this.waypoints = const [],
    this.initialRadares = const [],
    this.initialWeatherAlerts = const [],
    this.onRadarRemoved,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();

  /// Escolhe o radar que ocupa o slot de alerta entre os do corredor da rota.
  ///
  /// Regra: o MAIS PRÓXIMO dentro de [_radarAlertM], com UMA ressalva — um radar
  /// que a gente tem CERTEZA que fiscaliza o sentido oposto (classifyRadarDirection
  /// == opposite: fonte oficial + unidirecional + heading confiável + >=145°) só é
  /// escolhido se NÃO houver outro radar no raio. Sem isso, um radar da contramão
  /// coladinho (ex.: 31m) ocupava a vaga e mascarava o radar do SEU sentido logo
  /// atrás (ex.: 200m) — alarme atrasado do radar que pode multar.
  ///
  /// Conservador de propósito: só desprioriza o que é comprovadamente oposto.
  /// `unknown` (sem dado de direção, heading ruim, zona morta angular) conta como
  /// não-oposto e mantém prioridade — então pra radar sem direção, que é a
  /// maioria, o resultado é idêntico ao "mais próximo puro" de antes. E o oposto
  /// NUNCA some: se ele for o único no raio, ainda ganha o slot.
  @visibleForTesting
  static RadarPoint? pickUpcomingRadar(
    List<RadarPoint> visibleRadares,
    LatLng pos,
    double heading,
    double? headingAccuracy,
  ) {
    RadarPoint? closest;      double closestD = double.infinity;
    RadarPoint? closestKeep;  double closestKeepD = double.infinity;
    for (final r in visibleRadares) {
      final d = RadarService.haversine(pos.latitude, pos.longitude, r.lat, r.lng);
      if (d >= _NavigationScreenState._radarAlertM) continue;
      if (d < closestD) { closest = r; closestD = d; }
      final opposite = classifyRadarDirection(
            dir1: r.dir1, dir2: r.dir2, dirSrc: r.dirSrc,
            userHeading: heading, headingAccuracy: headingAccuracy,
          ) ==
          RadarDirMatch.opposite;
      if (!opposite && d < closestKeepD) { closestKeep = r; closestKeepD = d; }
    }
    return closestKeep ?? closest; // oposto só ganha se for o único no raio
  }
}

class _NavigationScreenState extends State<NavigationScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  GoogleMapController? _mapController;
  late ThemeController _themeController;
  StreamSubscription<Position>? _posSub;
  late final FlutterTts _tts;

  late RouteResult _result;
  List<RadarPoint> _radares = [];
  List<RadarPoint> _visibleRadares = [];
  List<WeatherAlert> _weatherAlerts = const [];

  LatLng? _currentPos;
  double _bearing = 0;
  double _speedKmh = 0;
  // Rumo do GPS é confiável? Medido pela velocidade FÍSICA (pos.speed cru), não
  // pela _speedKmh — esta é a velocidade AO LONGO DA ROTA e zera quando
  // !movingByRoute, que é exatamente o caso do caminhão andando CONTRA a rota.
  // Fonte única: calculado no _onPosition e consumido pelo _reroute (o gate do
  // course). Ver o deadlock do field 2026-07-13 no _reroute.
  bool _headingReliable = false;
  double _rawSpeedKmh = 0; // velocidade física do GPS (só p/ telemetria do gate)
  // Telemetria do veredito "parado": o velocímetro mostrou 0 com o caminhão andando
  // (vídeo do drive 2026-07-13, 18:33:13 → tela 0 km/h, GPS 18 km/h). Duas suspeitas:
  // (a) movingByRoute mente — o snap não avança na rota; (b) o recálculo congela a
  // tela. Sem estes três no heartbeat não dá pra separar uma da outra, e o
  // velocímetro alimenta o alerta de excesso E o flash de radar. Não conserto no escuro.
  bool _movingByRoute = false;  // avançando AO LONGO da rota (≠ velocidade do GPS)
  double _netAdvanceM = 0;      // quanto o snap andou na janela (~2,5s)
  double _offRouteDistM = 0;    // distância perpendicular à linha da rota
  int _closestPolylineIdx = 0;
  int _maneuverIndex = 0;
  double _distToNextManeuver = double.infinity;
  AudioLevel _audioLevel = AudioLevel.completo;
  ZoomLevel _zoomLevel = ZoomLevel.medio;
  bool _isRerouting = false;
  // Sequência do recálculo. O enrichment (FASE 2) roda solto, fora do caminho
  // crítico — quando ele volta, a rota que o originou pode já ter sido substituída
  // por outro reroute. O seq é o carimbo que deixa o resultado velho ser descartado
  // em vez de colar radar/restrição da rota morta por cima da viva.
  int _rerouteSeq = 0;
  Timer? _refreshTimer;
  Timer? _heartbeatTimer;
  DateTime? _lastRerouteAt;
  int _offRouteCount = 0;
  int _offRouteStartIdx = 0; // bestIdx quando saiu do corredor (mede avanço p/ telemetria)
  DateTime? _offRouteSince; // instrumentação: quando o caminhão saiu do corredor
  DateTime? _rerouteGraceUntil; // janela de carência pós-reroute (anti-encadeamento)
  RadarPoint? _upcomingRadar;
  // Sentido do _upcomingRadar vs heading do motorista — DECORAÇÃO da UI, nunca
  // gate (invariante). Calculado APÓS o gate escolher o radar, no setState.
  RadarDirMatch _upcomingRadarDir = RadarDirMatch.unknown;
  // Coleta passiva: registra o heading ao cruzar cada radar (1 write por radar por
  // viagem, best-effort). Alimenta a agregação de direção crowd. Zero efeito na
  // tela — observação pura, nunca gate.
  late final RadarPassLogger _radarPassLogger;
  // Curadoria: pop-up que surge sozinho ao chegar num radar SEM verdicto, pergunta
  // "existe?" e (se sim) a velocidade. _curatedKeys = já curados (não re-pergunta);
  // _promptedKeys = já perguntados nesta sessão (não naga na mesma passada).
  final Set<String> _curatedKeys  = {};
  final Set<String> _promptedKeys = {};
  RadarPoint? _curationPrompt;      // radar sendo perguntado agora (null = sem card)
  bool _curationSpeedStep = false;  // 2ª etapa: chips de velocidade
  Timer? _curationTimer;            // auto-some sem mudar nada
  final Set<int> _announced = {};
  int _lastTickMs = 0; // throttle do _predictTick (cap ~30fps, alivia main thread/channel)
  // Histórico curto de posições projetadas na rota (tempoMs, snap) p/ detectar
  // "parado" pelo avanço líquido ao longo da rota — imune ao jitter de velocidade.
  final List<(int, LatLng)> _snapHistory = [];
  final List<(int, double)> _offDistHistory = []; // (ms, bestDist) p/ trend de afastamento

  // Cache de ícones para radares
  final _iconCache = <String, BitmapDescriptor>{};
  Future<List<BitmapDescriptor>>? _radarIconsFuture;

  // Seta do puck rasterizada em ícone de mapa (mesmo desenho do NavPuck), usada
  // como marker que anda/gira no olhar-ao-redor. null até _loadPuckIcon terminar.
  BitmapDescriptor? _puckIcon;
  BitmapDescriptor? _weatherIcon; // ícone de clima do mapa (um só, cacheado)

  final List<UserRestriction> _userRestrictions = [];
  final _restrictionIconCache = <String, BitmapDescriptor>{};

  bool _markingMode = false;
  bool _markingRadar = false; // marcando radar (true) vs restrição (false)
  bool _paused = false;
  bool _arrived = false;
  // Olhar-ao-redor: o usuário moveu o mapa (pinch/arrasto) → para de seguir a
  // câmera até ele tocar "centralizar" ou passar o timeout sem mexer.
  bool _freeLook = false;
  DateTime? _lastUserGestureAt;   // marca o último gesto, p/ auto-retorno
  DateTime? _lastZoomAt;          // último gesto de zoom, p/ não confundir o pan
                                  // que acompanha a pinça com olhar-ao-redor
  // Último toque no mapa (down/move). O follow se suspende enquanto o dedo está
  // ativo (últimos _pointerActiveMs), p/ o arrasto colinear (pra frente) não ser
  // cancelado. Timestamp em vez de bool: AUTO-EXPIRA — se um pointer-up se perder
  // na platform view, o follow se recupera sozinho (nunca trava suspenso).
  DateTime? _lastPointerAt;
  bool get _fingerActive =>
      _lastPointerAt != null &&
      DateTime.now().difference(_lastPointerAt!).inMilliseconds < _pointerActiveMs;
  DateTime? _ignoreGestureUntil;  // ignora os frames do _recenter (não re-entra)
  // Trocar de nível de zoom é um move NOSSO (programático). O settle do zoom
  // reporta um alvo divergente (offset do padding, maior quanto mais recuado)
  // que escapa a janela dos 900ms e ligava o free-look "do nada" (botão azul no
  // cycle de zoom — relato Gilberto). Enquanto esta flag estiver armada e sem
  // dedo, o ramo !isEcho não engata free-look. QUALQUER toque a desarma → o
  // olhar-ao-redor volta ao normal (arrasto/pinça do usuário).
  bool _zoomJustChanged = false;
  DateTime? _lastProgrammaticMoveAt; // instrumentação: quanto depois de um
                                     // recenter/zoom o free-look disparou (bug do marker azul)
  // Ring-buffer dos alvos que NÓS comandamos (follow/recenter/resume). O
  // _onCameraMove escuta TODO move de câmera — inclusive os nossos. Um alvo que
  // bate com algo comandado nos últimos ~4s é eco do follow, não o dedo do
  // usuário. Discriminador ESPACIAL (não temporal): follow e dedo se intercalam
  // no tempo, então janela de tempo não separa; mas o dedo leva a câmera a um
  // alvo que nunca comandamos. Mata os 3 gatilhos espúrios (startup / catch-up
  // pós-stall / refire do recenter) que faziam free-look "do nada".
  final List<LatLng> _cmdTargets = [];
  // Estado "chegando": contador ancorado antes de finalizar (não mata o GPS —
  // o motorista ainda manobra / dá a volta no quarteirão).
  bool _arriving = false;
  LatLng? _arrivalAnchor;
  Timer? _arrivalTimer;
  double _arrivalProgress = 0.0; // 0→1 ao longo da contagem
  bool _ttsActive = false;
  // Solta o _ttsActive quando o engine não avisa que terminou (perda de foco de
  // áudio, engine engolindo a utterance). Sem isto, _ttsActive fica preso em true
  // e o gate do _speak cala a navegação INTEIRA pelo resto da viagem.
  Timer? _ttsWatchdog;
  // Falas descartadas por colisão (outra já tocando). Sai no nav_end: hoje esse
  // descarte é invisível em campo, então "a voz sumiu" nunca vira causa raiz.
  int _ttsDropped = 0;
  bool _speedAlertActive = false;
  DateTime? _lastSpeedAlertAt;
  final Set<String> _actionedRestrictions = {};
  LatLng? _snappedPos;
  PoliceAlert? _nearestPoliceAlert;
  bool _hasFirstFix = false;
  LatLng _cameraTarget = const LatLng(-15.788, -47.879);

  // Animação suave do marcador (N3)
  // Dead-reckoning: a seta é extrapolada por velocidade constante AO LONGO da
  // rota a 60fps, a partir do último fix GPS (anchor). Elimina o lag de ~1
  // intervalo que a animação por tween introduzia (seta sempre atrás do carro).
  // Guardas: não prevê parado (anti-freada) e congela após _maxPredictMs sem
  // fix novo (anti-viaduto/perda de sinal), evitando a seta deslizar sozinha.
  late AnimationController _predTicker; // driver de 60fps (.repeat)
  // Flash vermelho de tela cheia: pulsa quando está ACIMA do limite de caminhão
  // DENTRO de área de radar (== _speedAlertActive). Alerta visual pedido pelo
  // Gilberto; gatilho restrito p/ não virar "storm" (só quando tem significado).
  late final AnimationController _flashController;
  late final Animation<double> _flashAnim;
  LatLng _animPos = const LatLng(-15.788, -47.879);
  double _animBearing = 0;
  LatLng? _anchorPos;          // posição snapped do último fix
  int _anchorIdx = 0;          // índice na polyline do último fix
  double _anchorSpeedMps = 0;  // velocidade do último fix (m/s)
  DateTime? _lastPosUpdateAt;  // hora do último fix (= anchor time)
  static const double _stopKmh = 3.0;
  static const int _maxPredictMs = 2500;
  // Suavização da rotação da câmera (heading-up). Lerp angular por tick (~30fps):
  // o degrau de bearing por-segmento vira giro contínuo, matando o "salto" na curva.
  // ponytail: knob de calibração de campo — subir (0.3-0.4) reduz o lag da câmera
  // em curva fechada; baixar deixa mais lisa porém mais atrasada.
  static const double _bearingLerp = 0.2;
  // Detecção de parado por progresso ao longo da rota (não pela velocidade do GPS,
  // que dá spikes de 6-22 km/h parado). Calibráveis no device.
  static const int _stopWindowMs = 2500;
  static const double _stopNetM = 7.0;

  // Cache dos overlays do mapa (polylines/circles). A animação do marcador
  // dispara setState a 60fps; sem cache, o build() realocava as sublists da
  // rota toda a cada frame e o google_maps_flutter re-enviava a geometria
  // pelo platform channel. Recomputamos só quando o índice/raio muda.
  Set<Polyline> _polylines = {};
  int? _overlaysSplitIdx;
  // Rastro cinza colado na seta: a divisa segue o predIdx interpolado (onde a
  // seta está), não o _closestPolylineIdx do GPS (1Hz, que saltava atrás). O
  // rebuild é throttled (~250ms) pra não voltar ao setState de 60fps no Adreno.
  int _predIdx = 0;
  int _lastTrailMs = 0;

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
  bool _timeBannerVisible = false; // banner genérico de horário: some após alguns segundos
  Timer? _timeBannerTimer;
  String? _restrictionLabel; // tipo/limite da restrição (do details da HERE), p/ o banner
  List<RestrictionPoint> _restrictionPoints = const []; // pontos p/ pin + toque-no-banner

  // Corredor de desvio: 70m. Histórico: 120m (errava um quarteirão inteiro numa
  // rua paralela) → 40m (rápido demais) → 70m. O 40m era apertado pra pista
  // dupla: na Fernão Dias a linha da HERE fica ~45m do lado onde o caminhão roda
  // (field_logs 01/07: off_route em rajada, distM cravado 40-49m → storm de
  // reroute a cada ~7s). 70m ignora a separação de pista mas ainda pega rua
  // errada (quarteirão é 80-120m). O debounce de 3 fixes segura ruído de GPS.
  // ponytail: knob de campo — se voltar a storm no log, subir; se atrasar
  // correção legítima de rua errada, baixar.
  static const _offRouteThresholdM  = 70.0;
  // Portão CURTO usado só quando o rumo está divergindo (ele virou pra fora): não
  // espera os 70m (~8s a 30km/h) pra reagir, basta afastar ~25m (~3s). Seguindo a
  // rota ele fica a <15m da linha, então nunca cruza 25m → não dispara falso na
  // curva legítima. Acima do ruído de GPS urbano (~10m).
  static const _offRouteNearM       = 25.0;
  // Quanto a separação da rota precisa CRESCER na janela (~2,5s) pra contar como
  // "saindo". Pista paralela (mesmo na curva) fica ~plana; saída real sobe. É o
  // que separa desvio de verdade do fantasma da curva, onde o ângulo engana.
  static const _offGrowM            = 12.0;
  // Acima disso NÃO é pista paralela — é rua/rodovia diferente. Reroteia mesmo
  // avançando (o gate de "movingByRoute" abaixo só vale entre 70 e 150m).
  static const _offRouteHardM       = 150.0;
  static const _offRouteCountLimit  = 3;
  // Throttle do reroute: 10s pro refresh periódico/background; piso curto de 4s
  // pra desvio real (urgent), que já é naturalmente limitado pelo re-arm do
  // _offRouteCount (precisa de 3 fixes novos) + guarda _isRerouting.
  static const _rerouteThrottleSec     = 10;
  static const _rerouteUrgentFloorSec  = 4;
  // O piso de velocidade pra confiar no rumo mora em kRerouteCourseMinKmh (topo
  // do arquivo), junto de headingIsReliable — fonte única de quem decide "desviou?"
  // e de quem decide "mando o course pra HERE?".
  // "Map matching do pobre": rumo do caminhão vs rumo da rota no ponto mais
  // próximo. Fora do corredor MAS rumo alinhado = pista paralela (mesma mão) →
  // segura (mata storm). Rumo divergindo = ele virou pra fora da rota → encolhe o
  // portão (reage em ~25m/~3s, não 70m/~8s) E fura a supressão, rerotando já. Só o
  // rumo é o 3º peso do map matching que a gente já tem de graça (sem grafo no
  // device). 45° = "virou de forma perceptível" (transversal/saída), bem acima do
  // fantasma de pista paralela (~0°) e do ruído de heading do GPS.
  // ponytail: se pegar curva legítima (só dispara já >25m fora, então improvável),
  // subir; se deixar passar saída rasa, baixar.
  static const _divergeDeg             = 45.0;
  // Carência pós-reroute: depois que a rota nova cai, origem/GPS ainda estão
  // defasados e o caminhão pode aparecer fora do corredor por 1-2s — o que
  // re-disparava 2-3 reroutes encadeados (field 2026-06-29, ~20s "atualizando").
  // Segura o re-disparo até a rota assentar; encerra cedo se snapar de volta.
  // ponytail: knob de campo — se 5s ainda encadear, subir; se atrasar correção
  // legítima, baixar.
  static const _rerouteGraceMs         = 5000;
  // Olhar-ao-redor: volta a seguir sozinho após Xs sem o usuário tocar o mapa.
  // ponytail: knob de campo — subir se ele reclamar que volta cedo demais.
  static const _freeLookAutoReturnMs   = 10000;
  // Rescaldo de pinça: por Xms após um gesto de zoom, um pan é tratado como parte
  // da pinça (não vira olhar-ao-redor). Sem isto, o pequeno pan que acompanha o
  // zoom jogava a câmera pra free-look ("dei zoom e virou pino" — Gilberto).
  static const _zoomCooldownMs         = 450;
  // Janela em que um toque conta como "dedo ativo" (suspende o follow). Curta o
  // bastante pra o follow retomar logo ao soltar; longa o bastante pra cobrir a
  // pausa entre eventos de arrasto.
  static const _pointerActiveMs        = 150;
  // Chegada: contador de 15s antes de finalizar; se o caminhão se afastar mais
  // que 40m da âncora durante a contagem, cancela e reroteia (deu a volta).
  static const _arrivalCountdownMs = 15000;
  static const _arrivalMoveM       = 40.0;
  // Reta final: com a rota restante abaixo disso, uma divergência é manobra de
  // chegada, não desvio — o reroute cede (senão manda "voltar" pro destino que o
  // caminhão está passando). P0 Gilberto 2026-07-12.
  static const _arrivalZoneM       = 150.0;
  static const _radarAlertM         = 400.0;
  static const _restrictionAlertM   = 300.0;
  static const _radarLookAheadM     = 1500.0;
  // Distância perpendicular máxima do radar ao segmento da rota para contar
  // como "na via" (~largura de pista + erro de GPS). Antes era raio a pontos
  // soltos (60m), que vazava pra ruas paralelas. Tunável em campo.
  static const _radarCorridorM      = 22.0;
  // Distância pra o pop-up de curadoria surgir (chegou no radar). Tunável em campo.
  static const _radarReachedM       = 60.0;
  static const _prefAudioLevel = 'nav_audio_level';
  static const _prefZoomLevel  = 'nav_zoom_level';

  @override
  void initState() {
    super.initState();
    _result  = widget.result;
    // Telemetria: marca o início do drive — garante rastro mesmo num trajeto
    // limpo (sem reroute), pra diagnosticar "travou" onde o heartbeat parar.
    FieldLog.event('nav_start', {
      'points': _result.polylinePoints.length,
      'distM':  _result.distanceMeters,
      'durS':   _result.durationSeconds,
      // Precisão do destino (diag. "cheguei mas o app achava que faltava X"):
      // qual coord virou destino e se a polyline termina nela ou desviada.
      'destLat': widget.destination.latitude,
      'destLng': widget.destination.longitude,
      'polyEndLat': _result.polylinePoints.isNotEmpty ? _result.polylinePoints.last.latitude : null,
      'polyEndLng': _result.polylinePoints.isNotEmpty ? _result.polylinePoints.last.longitude : null,
      'destToPolyEndM': _result.polylinePoints.isNotEmpty
          ? RadarService.haversine(
              widget.destination.latitude, widget.destination.longitude,
              _result.polylinePoints.last.latitude, _result.polylinePoints.last.longitude).round()
          : null,
    });
    _radarPassLogger = RadarPassLogger(flush: FirestoreRadarService.logRadarPasses);
    _radares        = List.of(widget.initialRadares);
    _weatherAlerts  = List.of(widget.initialWeatherAlerts);
    _visibleRadares = List.of(widget.initialRadares);
    _radarIconsFuture = Future.wait(_radares.map(_radarIcon));
    _hasTimeRestrictionAlert = widget.result.hasTimeRestriction;
    _restrictionLabel        = widget.result.restrictionLabel;
    _restrictionPoints       = widget.result.restrictionPoints;
    WidgetsBinding.instance.addObserver(this);
    _loadAudioLevel();
    _loadZoomLevel();
    // Radares já curados neste device → não perguntar de novo no pop-up.
    FirestoreRadarService.localOverrideKeys()
        .then((k) { if (mounted) _curatedKeys.addAll(k); });
    _loadPuckIcon();
    _loadWeatherIcon();
    _loadUserRestrictions();
    _startForegroundService();
    _initTts();
    _themeController = context.read<ThemeController>();
    _themeController.addListener(_onThemeChanged);
    _startGps();
    _predTicker = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..addListener(_predictTick)
      ..repeat();
    _flashController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650));
    _flashAnim = Tween<double>(begin: 0.12, end: 0.40).animate(
        CurvedAnimation(parent: _flashController, curve: Curves.easeInOut));
    _refreshTimer = Timer.periodic(const Duration(minutes: 10), (_) => _periodicRefresh());
    WakelockPlus.enable();
    _loadRoutePois();
    _policeTimelineTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _refreshPoliceTimeline(),
    );
    // Heartbeat de campo: posição/velocidade a cada 30s enquanto navega de fato.
    // Num freeze, o último heartbeat marca ONDE travou (o motorista não captura
    // logcat dirigindo). A 60 km/h, 30s ≈ 500m de resolução.
    // NOTA: em produção com muitos usuários, gatear/aumentar o intervalo.
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_paused || _arrived || _currentPos == null) return;
      FieldLog.event('heartbeat', {
        'idx':  _closestPolylineIdx,
        'kmh':  _speedKmh.round(),        // o que o MOTORISTA vê no velocímetro
        'rawKmh': _rawSpeedKmh.round(),   // o que o GPS realmente diz
        'moving': _movingByRoute,         // avançando AO LONGO da rota?
        'netM': _netAdvanceM.round(),     // quanto o snap andou em ~2,5s (limiar: 7m)
        'offM': _offRouteDistM.round(),   // distância da linha da rota
        'rerot': _isRerouting,            // a amostra caiu DENTRO de um recálculo?
        'remM': _remainingDistanceM().round(),
      });
    });
    // Ciclo de vida da nav: nav_start aqui, nav_end no dispose (com arrived),
    // app_lifecycle nas transições. Se um nav_end arrived=false vier logo depois
    // de um app_lifecycle resumed, é a "rota some no background" reproduzida.
    FieldLog.event('nav_start', {'wpts': widget.waypoints.length});
  }

  @override
  void dispose() {
    // No fecho (chegada OU X manual): onde o caminhão estava, a quantos metros
    // EM LINHA RETA do destino, e quanto o app achava que faltava PELA ROTA.
    // straightToDestM pequeno + remainingRouteM grande = distância de rota (H-D),
    // não geocode errado. Ambos grandes = destino de fato deslocado.
    FieldLog.event('nav_end', {
      'arrived': _arrived,
      'idx': _closestPolylineIdx,
      'curLat': _currentPos?.latitude,
      'curLng': _currentPos?.longitude,
      'straightToDestM': _currentPos != null
          ? RadarService.haversine(
              _currentPos!.latitude, _currentPos!.longitude,
              widget.destination.latitude, widget.destination.longitude).round()
          : null,
      'remainingRouteM': _remainingDistanceM().round(),
      'speedKmh': _speedKmh.round(),
      'ttsDropped': _ttsDropped, // falas comidas por colisão nesta viagem
    });
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _timeBannerTimer?.cancel();
    _policeTimelineTimer?.cancel();
    _heartbeatTimer?.cancel();
    _arrivalTimer?.cancel();
    _posSub?.cancel();
    _radarPassLogger.endTrip(); // fecho pelo X manual: drena o que sobrou na fila
    _ttsWatchdog?.cancel();
    _tts.stop();
    _ttsActive = false;
    _themeController.removeListener(_onThemeChanged);
    FlutterForegroundTask.stopService();
    WakelockPlus.disable();
    _predTicker.dispose();
    _flashController.dispose();
    _curationTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    FieldLog.event('app_lifecycle', {
      'state':   state.name,
      'arrived': _arrived,
      'hasPos':  _currentPos != null,
    });
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
    // Re-arma o seguir ao voltar do background: sem isso, se o motorista mexeu
    // no mapa antes de sair (free-look), o app não voltava a seguir sozinho e
    // exigia toque manual em "centralizar". _ignoreGestureUntil tranca o gesto
    // pro moveCamera abaixo não re-disparar o free-look que acabamos de limpar.
    _freeLook = false;
    final resumeNow = DateTime.now();
    _lastProgrammaticMoveAt = resumeNow;
    _ignoreGestureUntil = resumeNow.add(const Duration(milliseconds: 900));
    // moveCamera (instantâneo) evita giros: animateCamera competia com
    // os primeiros updates de GPS no resume e causava rotações bruscas.
    if (!_markingMode && _mapController != null) {
      final pos = _snappedPos ?? _currentPos;
      if (pos != null) {
        _recordCmd(pos);
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
        ? 'Em ${_fmtDist(dist)}. ${_speech(m)}'
        : _speech(m);
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
    // flutter_tts multiplica por 2 no Android (rate*2 → engine), onde 1.0 = normal.
    // 0.9 dava 1.8× (quase o dobro) e o Gilberto reclamou que fala rápido demais.
    // 0.5 = velocidade normal de fala; bom pra instrução no volante. Knob de campo.
    _tts.setSpeechRate(0.5);
    _tts.setVolume(1.0);
    // Debounce de 300ms: evita que completionHandler prematuro (chunk interno do engine)
    // abra a janela para um novo _speak interromper a utterance em andamento.
    _tts.setCompletionHandler(() =>
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _ttsActive = false;
        }));
    _tts.setCancelHandler(() => _ttsActive = false);
    // speak.onError NÃO chama completion nem cancel (tabela de dispatch do
    // flutter_tts 4.2.0). Sem este handler o _ttsActive fica preso em true e o
    // gate do _speak cala a navegação inteira — manobra, radar, restrição,
    // chegada — pelo resto da viagem, sem deixar rastro.
    _tts.setErrorHandler((msg) {
      _ttsActive = false;
      _ttsWatchdog?.cancel();
      FieldLog.event('tts_error', {'msg': msg.toString()});
    });
  }

  Future<void> _startForegroundService() async {
    // Sem estas duas permissões a nav some em background: sem POST_NOTIFICATIONS
    // (Android 13+) a notificação do foreground service não aparece; sem isenção
    // de bateria, OEMs agressivos (Xiaomi/Redmi, Samsung) matam o service. Só
    // dispara o diálogo se ainda não concedido — aceito uma vez, nunca repergunta.
    if (await FlutterForegroundTask.checkNotificationPermission() !=
        NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    final ignoringBattery =
        await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    if (!ignoringBattery) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    // Estado da isenção é o diagnóstico direto do "nav some no background".
    FieldLog.event('bg_battery_opt', {'ignoring': ignoringBattery});
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
    if (mounted) {
      setState(() {
        _zoomLevel = ZoomLevel.values[idx.clamp(0, 2)];
        _zoom = _zoomForLevel(_zoomLevel);
      });
    }
  }

  // Ícone de clima do mapa (⛈️ laranja, mesmo glifo da barra), UM só cacheado em
  // _weatherIcon — não é lista indexada, então imune ao RangeError do reroute.
  // Reusa o builder de POI existente.
  Future<void> _loadWeatherIcon() async {
    final icon = await buildPoiIcon(Colors.deepOrange.shade600, Icons.thunderstorm);
    if (mounted) setState(() => _weatherIcon = icon);
  }

  // Rasteriza a seta do NavPuck num ícone de mapa, pra usar como marker que anda
  // e gira (rotation=bearing) no olhar-ao-redor. Uma vez, cacheado em _puckIcon.
  Future<void> _loadPuckIcon() async {
    const size = 44.0;
    final recorder = ui.PictureRecorder();
    const PuckPainter().paint(Canvas(recorder), const Size(size, size));
    final img = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    if (bytes != null && mounted) {
      setState(() => _puckIcon = BitmapDescriptor.bytes(bytes.buffer.asUint8List()));
    }
  }

  Future<void> _saveZoomLevel(ZoomLevel level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefZoomLevel, level.index);
  }

  void _cycleZoomLevel() {
    final next = ZoomLevel.values[(_zoomLevel.index + 1) % ZoomLevel.values.length];
    setState(() { _zoomLevel = next; _zoom = _zoomForLevel(next); });
    _saveZoomLevel(next);
    _zoomJustChanged = true; // suprime free-look no settle do zoom até o próximo toque
    _recenter();
  }

  // Zoom livre: o pinch grava QUALQUER valor aqui (não só os 3 presets), então a
  // seta segue em qualquer distância. O botão continua saltando entre os presets
  // via _zoomForLevel. Fonte única do follow (lida em todos os moveCamera).
  double _zoom = 17.0;

  static double _zoomForLevel(ZoomLevel l) => switch (l) {
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
    if (_ttsActive) {
      _ttsDropped++; // descarte silencioso: só medimos, comportamento intacto
      return;
    }
    _ttsActive = true;
    // ponytail: teto de sanidade, não constante calibrada. A fala mais longa do
    // app (manobra com nome de via) mede ~10s; 15s cobre folgado. Se estourar, o
    // engine não avisou que terminou — soltar é sempre melhor que emudecer.
    _ttsWatchdog?.cancel();
    _ttsWatchdog = Timer(const Duration(seconds: 15), () {
      if (!_ttsActive) return;
      _ttsActive = false;
      FieldLog.event('tts_watchdog', {'chars': text.length});
    });
    // O Future do speak() era descartado: uma PlatformException (engine ausente,
    // pt-BR indisponível, foco de áudio negado) virava erro async não tratado e
    // deixava o _ttsActive preso em true.
    _tts.speak(text).catchError((Object e, StackTrace st) {
      _ttsActive = false;
      _ttsWatchdog?.cancel();
      FieldLog.error('tts_speak', e, st);
      return null;
    });
  }

  // Entra no estado "chegando": ancora a posição, fala uma vez e arma a contagem.
  // NÃO cancela o GPS — _onPositionUpdate continua pra detectar se o caminhão
  // se afasta (manobra / volta no quarteirão) e cancelar a finalização.
  void _beginArrival(LatLng anchor) {
    if (_arrived || _arriving) return;
    _arriving = true;
    FieldLog.event('arrival');
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
    FieldLog.event('arrival_cancel');
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
    // Gap do destino logado AQUI (não só no nav_end): a chegada rola em background
    // e o pop/dispose não completa com o app pausado — o nav_end não dispararia.
    // straightToDestM pequeno + remainingRouteM grande = distância de rota (H-D).
    FieldLog.event('arrival_done', {
      'straightToDestM': _currentPos != null
          ? RadarService.haversine(
              _currentPos!.latitude, _currentPos!.longitude,
              widget.destination.latitude, widget.destination.longitude).round()
          : null,
      'remainingRouteM': _remainingDistanceM().round(),
    });
    _arrivalTimer?.cancel();
    _arrivalTimer = null;
    _arriving = false;
    // Mata o reroute periódico aqui: a chegada em background não dá dispose
    // (transição do pop congela pausada), então o _refreshTimer vazava e
    // rerroteava de 10 em 10 min parado no destino.
    _refreshTimer?.cancel();
    _posSub?.cancel();
    _radarPassLogger.endTrip(); // drena a fila de passagens (best-effort)
    // Mesmo motivo do _refreshTimer: stopService vivia só no dispose, que não
    // roda na chegada em background — a notificação "Navegando" ficava órfã
    // (ongoing, não-dismissível) por dias. Para aqui; idempotente (dispose
    // ainda chama pro caminho do X manual em foreground).
    FlutterForegroundTask.stopService();
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

  // Confirma antes de encerrar: o X é pequeno e fácil de tocar sem querer
  // dirigindo — sem isso, um toque errado mata a navegação inteira.
  Future<void> _confirmFinish() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Encerrar a rota?'),
        content: const Text('A navegação será finalizada.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continuar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Encerrar'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) Navigator.of(context).pop();
  }

  /// Limite de caminhão vigente na posição atual (HERE, por trecho).
  /// Null quando a rota não trouxe dados de limite.
  int? get _currentLimitKmh => _result.limitAt(_closestPolylineIdx);

  void _checkSpeedAlert(double kmh) {
    // Alerta de excesso por VOZ só em área de radar (pedido do Gilberto): fora de
    // radar o excesso fica só no visual (barra vermelha), sem repetir voz.
    // _upcomingRadar != null == a mensagenzinha de radar está na tela.
    final radar = _upcomingRadar;
    if (radar == null) {
      _speedAlertActive = false;
      return;
    }
    // Mais restritivo entre o postado no radar e o limite de caminhão do trecho;
    // piso 90 sem nenhum dado. Nunca avisa no limite de carro (report Gilberto).
    final limit =
        truckRadarLimit(radar.speedKmh, officialTruckLimit: radar.truckLimitOff) ??
            kTruckCapKmh;
    if (kmh >= limit + 2) { // +2: folga de arredondamento, evita nag no limite exato
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
    } else if (kmh < limit - 3) { // histerese: só rearma bem abaixo do limite
      _speedAlertActive = false;
    }
  }

  // Liga/desliga o flash vermelho de tela conforme _speedAlertActive (acima do
  // limite de caminhão em área de radar). Idempotente — só age na virada.
  // Banner de horário não tem coordenada (é bool da HERE) — deixá-lo a viagem
  // toda só comia tela, às vezes por cima da seta. Aparece ~8s e some; a voz
  // ("Atenção! Restrição...") já dá o aviso. O banner de restrição FÍSICA
  // (com local + botões) é outro e continua por proximidade.
  void _flashTimeBanner() {
    _timeBannerTimer?.cancel();
    setState(() => _timeBannerVisible = true);
    _timeBannerTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _timeBannerVisible = false);
    });
  }

  // Toque no banner de restrição → leva a câmera ao ponto restrito mais próximo
  // (o notice antes só falava/piscava SEM dizer onde — report Gilberto 12/07).
  // Usa as guardas do free-look (mesma higiene do _recenter) pra o move
  // programático não ser lido como gesto/echo pelo listener (P0 free-look).
  void _showRestrictionOnMap() {
    final pts = _restrictionPoints;
    if (pts.isEmpty || _mapController == null) return;
    final from = _snappedPos ?? _currentPos;
    final target = from == null
        ? pts.first.position
        : pts.map((p) => p.position).reduce((a, b) =>
            RadarService.haversine(from.latitude, from.longitude, a.latitude, a.longitude) <=
                    RadarService.haversine(from.latitude, from.longitude, b.latitude, b.longitude)
                ? a
                : b);
    final progNow = DateTime.now();
    _lastProgrammaticMoveAt = progNow;
    _ignoreGestureUntil = progNow.add(const Duration(milliseconds: 900));
    // Carimba o gesto AGORA: senão o auto-return (tick, _freeLookAutoReturnMs) lê
    // um _lastUserGestureAt velho e volta pro puck no próximo tick, matando a ida.
    // Com o carimbo, o motorista tem a janela cheia p/ olhar a restrição e volta só.
    _lastUserGestureAt = progNow;
    setState(() => _freeLook = true);
    _mapController!.animateCamera(CameraUpdate.newLatLngZoom(target, 15));
  }

  void _syncRadarFlash() {
    if (_speedAlertActive && !_flashController.isAnimating) {
      _flashController.repeat(reverse: true);
    } else if (!_speedAlertActive && _flashController.isAnimating) {
      _flashController.stop();
      _flashController.reset();
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
        // Sem onError, um erro do stream (perda de sinal, permissão revogada em
        // runtime, erro do plugin) CONGELA a navegação em silêncio absoluto —
        // nem visual, nem log. É o ponto cego mais grave do app.
        .listen(_onPositionUpdate,
            onError: (Object e, StackTrace st) => FieldLog.error('gps_stream', e, st));
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
    }).catchError((Object e, StackTrace st) {
      // Firestore falhou: sem isto era uma exceção async não tratada.
      FieldLog.error('police_check', e, st);
    });
  }

  void _onPositionUpdate(Position pos) {
    if (!mounted) return;
    final firstFix = !_hasFirstFix;
    _hasFirstFix = true;
    if (firstFix && _hasTimeRestrictionAlert && !_timeRestrictionAlertSpoken) {
      _timeRestrictionAlertSpoken = true;
      _speak('Atenção! Restrição para caminhões nesta via');
      _flashTimeBanner();
    }
    if (firstFix) _refreshPoliceTimeline();
    final latLng = LatLng(pos.latitude, pos.longitude);

    if (_paused) {
      // Pausado: o pino fica CONGELADO onde parou (pedido do Gilberto) — não segue
      // o GPS. Só registra a posição real e a velocidade; _snappedPos e o anchor
      // ficam no valor de quando pausou (predição parada, speed 0).
      setState(() {
        _currentPos = latLng;
        _speedKmh   = pos.speed * 3.6 < 2.5 ? 0.0 : (pos.speed * 3.6).clamp(0.0, 300.0);
      });
      final frozen = _snappedPos ?? latLng;
      _setAnchor(frozen, _closestPolylineIdx, _bearing, 0);
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

    // 2.5 Parado vs andando — pelo PROGRESSO AO LONGO DA ROTA, não pela velocidade
    // do GPS (que mente parado: jitter vira spikes de 6-22 km/h). bestSnap já é a
    // projeção na rota, então o jitter lateral some; só o avanço líquido na janela
    // conta. Parado → velocidade efetiva 0 → predição congela (puck para de andar
    // sozinho) e o TTS não dispara (mata o "Em 500m" espúrio). Tradeoff: abaixo de
    // ~_stopNetM/_stopWindowMs (~10 km/h) o puck pode ficar um tico duro — aceitável
    // p/ caminhão (phantom parado no semáforo é pior que crawl levemente travado).
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _snapHistory.add((nowMs, bestSnap));
    _snapHistory.removeWhere((e) => nowMs - e.$1 > _stopWindowMs);
    final winStart = _snapHistory.first;
    final netAdvanceM = RadarService.haversine(
        winStart.$2.latitude, winStart.$2.longitude, bestSnap.latitude, bestSnap.longitude);
    // Só confia no veredito "parado" quando a janela já encheu (~>60%); antes disso
    // (início da nav) cai no gate de velocidade pra não congelar à toa.
    final windowReady = (nowMs - winStart.$1) >= (_stopWindowMs * 0.6);
    // Antes da janela encher (~1,5s do início) NÃO caímos na pos.speed (fantasma)
    // — assumimos parado. Senão o jitter no start reabre o phantom/TTS espúrio
    // exatamente quando a nav abre perto da 1ª manobra.
    final movingByRoute = windowReady && netAdvanceM >= _stopNetM;
    final effSpeedMps = movingByRoute ? pos.speed : 0.0;
    // Espelha pro heartbeat (ver comentário na declaração): é o que separa
    // "movingByRoute mente" de "o recálculo congelou a tela".
    _movingByRoute = movingByRoute;
    _netAdvanceM   = netAdvanceM;
    _offRouteDistM = bestDist;

    // Separação da rota está CRESCENDO na janela? Saída real afasta; pista paralela
    // (mesmo numa curva, onde o ângulo engana) fica ~plana. first = amostra mais
    // antiga na janela; exige janela cheia p/ não confiar em 1 tranco de GPS.
    _offDistHistory.add((nowMs, bestDist));
    _offDistHistory.removeWhere((e) => nowMs - e.$1 > _stopWindowMs);
    final distGrowthM = bestDist - _offDistHistory.first.$2;
    final distGrowing = windowReady && distGrowthM > _offGrowM;

    // 3. Desvio de rota
    // Carência pós-reroute: a rota nova recém-aplicada + origem/GPS defasados
    // faziam o caminhão reaparecer fora do corredor e re-disparar 2-3 reroutes
    // encadeados (field 2026-06-29). Durante a janela não conta nem dispara;
    // ao expirar, se ainda estiver fora, a detecção reinicia do zero (detectMs
    // honesto). Snapar de volta ao corredor encerra a janela cedo (else).
    // Rumo do caminhão vs rumo da rota no ponto mais próximo. Heading do GPS só
    // é confiável com movimento FÍSICO (pos.speed cru, NÃO effSpeedMps — este
    // zera quando !movingByRoute, que é exatamente o caso do desvio contrário).
    // ponytail: 1 segmento da rota basta — se ficar ruidoso perto de curva,
    // alargar pra média de 2-3 segmentos.
    final vehBearing = pos.heading;
    final headingReliable = headingIsReliable(pos.speed, vehBearing);
    final routeBearing = _segmentBearing(pts, bestIdx);
    final headingDelta = headingReliable
        ? (((vehBearing - routeBearing + 540) % 360) - 180).abs()
        : -1.0;
    // "Saiu de verdade" = apontou pra fora (rumo divergindo) E está se afastando
    // (distância crescendo). Os DOIS: o ângulo sozinho engana na curva de via
    // dividida (rumo torto mas paralelo, distância plana); exigir afastamento mata
    // esse fantasma. Seguindo a rota o rumo acompanha o segmento (delta baixo) e a
    // distância não sobe — nada dispara.
    final diverging = headingReliable && headingDelta > _divergeDeg;
    final leavingRoute = diverging && distGrowing;
    // Só quem saiu de verdade ganha o portão curto (~25m/~3-5s em vez de 70m/~8s).
    final offRouteGate = leavingRoute ? _offRouteNearM : _offRouteThresholdM;

    final inRerouteGrace = _rerouteGraceUntil != null &&
        DateTime.now().isBefore(_rerouteGraceUntil!);
    if (bestDist > offRouteGate && !inRerouteGrace) {
      if (_offRouteCount == 0) {
        _offRouteSince = DateTime.now();
        _offRouteStartIdx = bestIdx;
        FieldLog.event('off_route', {
          'distM': bestDist.round(),
          'moving': movingByRoute,
          'hdgDelta': headingDelta.round(),
          'growM': distGrowthM.round(),
          // POR QUE moving deu false? netM é o avanço do snap na janela (limiar 7m).
          // Suspeita do drive 2026-07-13: no pára-e-anda da cidade netM fica abaixo
          // de 7m mesmo com o caminhão andando → a supressão de pista paralela nunca
          // engata (ela EXIGE movingByRoute) → rerota indo reto. 7 dos 12 off_route
          // vieram com hdgDelta<=20 (alinhado!). Confirmar antes de mexer no gate.
          'netM': netAdvanceM.round(),
          'rawKmh': (pos.speed * 3.6).round(),
        });
      }
      _offRouteCount++;
      if (_offRouteCount >= _offRouteCountLimit) {
        // Freio de chegada: na reta final da rota, divergência é manobra de
        // chegada, não desvio. Reroteiar aqui manda o caminhão "voltar" pro
        // destino que ele está passando (P0 Gilberto 2026-07-12: parou ~85m do
        // pino, fora do corredor, e tomou 4 reroutes urgentes em 76s até a
        // chegada armar). Cede ANTES dos outros gates.
        // ponytail: teto por distância de rota; se tropeçar, virar zona por tempo.
        final remainingRouteM =
            RadarService.remainingAlongRoute(pts, bestIdx, _arrivalZoneM);
        if (remainingRouteM < _arrivalZoneM) {
          FieldLog.event('reroute_suppressed', {
            'distM': bestDist.round(),
            'idxDelta': bestIdx - _offRouteStartIdx,
            'reason': 'near_dest',
            'remainingM': remainingRouteM.round(),
          });
          _offRouteCount = _offRouteCountLimit - 1; // re-arma sem martelar
        }
        // Pista dupla: fora do corredor MAS avançando ao longo da rota
        // (movingByRoute) E no mesmo rumo = a linha da HERE está na outra mão da
        // MESMA via. Reroteiar não ajuda (não cruza o canteiro) e gera o storm
        // do field_log (72-77m cravado, rota nova só crescendo). Só reroteia se:
        // travou (não avança), longe demais p/ ser pista paralela (_offRouteHardM),
        // OU saiu de verdade (leavingRoute — apontou pra fora E se afastando).
        else if (!movingByRoute || bestDist > _offRouteHardM || leavingRoute) {
          _reroute(fromPos: latLng, urgent: true);
        } else {
          FieldLog.event('reroute_suppressed', {
            'distM': bestDist.round(),
            'idxDelta': bestIdx - _offRouteStartIdx,
            'hdgDelta': headingDelta.round(),
            'growM': distGrowthM.round(),
          });
          _offRouteCount = _offRouteCountLimit - 1; // re-arma sem martelar
        }
      }
    } else {
      _offRouteCount = 0;
      _offRouteSince = null;
      if (bestDist <= offRouteGate) _rerouteGraceUntil = null;
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
      if (movingByRoute) _checkTts(nextIdx, distToNext, nextManeuver);
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
    final upcoming = NavigationScreen.pickUpcomingRadar(
      visibleRadares, latLng, pos.heading, pos.headingAccuracy);

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
      _headingReliable            = headingReliable;
      _rawSpeedKmh                = pos.speed * 3.6;
      _speedKmh                   = effSpeedMps * 3.6 < 2.5 ? 0.0 : (effSpeedMps * 3.6).clamp(0.0, 300.0);
      _closestPolylineIdx         = bestIdx;
      _maneuverIndex              = nextIdx;
      _distToNextManeuver         = distToNext;
      _upcomingRadar              = upcoming;
      // Classifica DEPOIS do gate ter escolhido (nunca dentro da condição do
      // gate). Só decora a UI; não altera se/como o alerta dispara.
      _upcomingRadarDir           = upcoming == null
          ? RadarDirMatch.unknown
          : classifyRadarDirection(
              dir1: upcoming.dir1,
              dir2: upcoming.dir2,
              dirSrc: upcoming.dirSrc,
              userHeading: pos.heading,
              headingAccuracy: pos.headingAccuracy,
            );
      _nearbyBlockedRestriction   = nearestBlocked;
      _visibleRadares             = visibleRadares;
      if (radarListChanged) {
        _radarIconsFuture = Future.wait(visibleRadares.map(_radarIcon));
      }
    });
    // Bearing único para seta e câmera: o segmento da rota (estável), não o
    // heading bruto do GPS. Evita a "pescadinha" — a seta balançando em cima
    // de um mapa que já gira suave. Fallback para heading só sem rota.
    final anchorBearing = pts.length >= 2 ? routeBearing : pos.heading;
    _setAnchor(pts.isNotEmpty ? bestSnap : latLng, bestIdx, anchorBearing, effSpeedMps);
    _updateRestrictionAlert(nearestBlocked, nearestBlockedDist);
    _updateRadarAlert(upcoming);
    // Coleta passiva: observa o cruzamento que o gate JÁ detectou, sem tocá-lo.
    // rid = chave estável do radar (lat_lng), igual à dedupe do curador. O logger
    // dedupa 1 write por radar por viagem, então chamar todo tick é inócuo.
    if (upcoming != null) {
      _radarPassLogger.onRadarCrossed(
        radarId: dismissalKey(upcoming.lat, upcoming.lng),
        heading: pos.heading,
        speedKmh: _speedKmh,
      );
    }
    _checkSpeedAlert(_speedKmh);
    _syncRadarFlash();
    _maybePromptCuration(upcoming, latLng);
    _checkPoliceAlerts(latLng);
    _buildUpcomingEvents();

    // 8. Câmera: o follow é feito no _predictTick (segue a predição a ~30fps,
    // com o puck fixo embaixo). Aqui só atualizamos a âncora (acima, _setAnchor);
    // o animateCamera de 1Hz foi removido pra não brigar com o follow contínuo.
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

    // Cap ~30fps: a 60fps cada tick faz setState→build→update do marker pelo
    // method channel; em device fraco isso satura a main thread e a seta atrasa.
    // 30fps é liso pra um puck e corta o tráfego/rebuild pela metade.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastTickMs < 30) return;
    _lastTickMs = nowMs;

    // Olhar-ao-redor: a seta CONTINUA andando no mapa (segue o cálculo abaixo), só
    // a câmera é que não segue (guarda no moveCamera). Volta sozinho pro follow
    // após _freeLookAutoReturnMs sem toque.
    if (_freeLook &&
        _lastUserGestureAt != null &&
        DateTime.now().difference(_lastUserGestureAt!).inMilliseconds >=
            _freeLookAutoReturnMs) {
      _recenter();
      return;
    }

    final elapsedMs = DateTime.now()
        .difference(anchorTime)
        .inMilliseconds
        .clamp(0, _maxPredictMs);
    final advanceM = (_anchorSpeedMps * 3.6 >= _stopKmh)
        ? _anchorSpeedMps * (elapsedMs / 1000.0)
        : 0.0;

    final (predPos, predIdx) = _advanceAlongRoute(pts, _anchorIdx, anchor, advanceM);
    // Rumo do segmento SOB o puck (não à frente): o puck é fixo apontando pra cima,
    // então a câmera tem que girar NA posição. Mirar à frente girava a estrada antes
    // da curva e o puck saía de lado ("derrapava" — relato de campo 2026-06-29).
    final targetBearing = _segmentBearing(pts, predIdx);

    // Menor arco entre o bearing atual e o alvo: se já convergiu (e a posição não
    // mudou), não há o que mover.
    final bearingDelta = ((targetBearing - _animBearing + 540) % 360) - 180;
    if (_sameLatLng(predPos, _animPos) && bearingDelta.abs() < 0.1) {
      return;
    }
    // Sem Marker pra animar: NÃO faz setState (o puck é widget estático). Só move
    // a câmera seguindo a predição a ~30fps → o mapa desliza liso sob o puck fixo,
    // e some o rebuild de 60fps que saturava a main thread do device fraco.
    // O bearing vai por lerp angular (menor arco) → o degrau por-segmento vira
    // giro contínuo, matando o "salto" na curva.
    _animPos     = predPos;
    _animBearing = lerpAngleDeg(_animBearing, targetBearing, _bearingLerp);
    // Rastro segue a seta: reparte a polyline no predIdx (onde a seta está), não
    // no _closestPolylineIdx do GPS. Throttle ~250ms — colado o suficiente sem
    // re-difundir a geometria pelo channel a cada frame (perf Adreno 610).
    _predIdx = predIdx;
    if (!_markingMode && !_paused && predIdx != _overlaysSplitIdx) {
      final tMs = DateTime.now().millisecondsSinceEpoch;
      if (tMs - _lastTrailMs >= 250 && mounted) {
        _lastTrailMs = tMs;
        setState(() {}); // build() reparte a rota no _predIdx; memoização cuida do resto
      }
    }
    // Free-look: a seta anda (o setState do trail acima reposiciona o marker), mas
    // a câmera NÃO segue. !_fingerDown: com o dedo na tela o follow também para —
    // senão cancela o arrasto colinear (pra frente) antes de virar olhar-ao-redor.
    if (!_markingMode && !_paused && !_freeLook && !_fingerActive) {
      _recordCmd(predPos);
      _mapController?.moveCamera(
        CameraUpdate.newCameraPosition(CameraPosition(
          target:  predPos,
          zoom:    _zoom,
          tilt:    45,
          bearing: _animBearing,
        )),
      );
    }
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

  // Texto falado/exibido da manobra: usa a instrução da HERE; se vier vazia
  // (acontece no truck routing), sintetiza de action+direction ("vire à direita").
  String _speech(RouteManeuver m) =>
      resolveManeuverText(m.instruction, m.action, m.direction);

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
      // Threshold mais próximo primeiro: ao iniciar/reentrar já perto da manobra
      // (ex.: 184m), evita soltar "Em 500 metros" espúrio. Cada ramo semeia os
      // thresholds mais longes, então a aproximação normal anuncia 500→200→50.
      if (distM <= 50 && !_announced.contains(k50)) {
        _announced.add(k50);
        _announced.add(k200);
        _announced.add(k500);
        _speak(_speech(m));
      } else if (distM <= 200 && !_announced.contains(k200)) {
        _announced.add(k200);
        _announced.add(k500);
        _speak('Em 200 metros. ${_speech(m)}');
      } else if (_audioLevel == AudioLevel.completo && distM <= 500 && !_announced.contains(k500)) {
        // 500m só no nível completo
        _announced.add(k500);
        _speak('Em 500 metros. ${_speech(m)}');
      }
    } else if (isExit) {
      // Saídas: 200m no completo, 50m em ambos — mais próximo primeiro (idem acima)
      if (distM <= 50 && !_announced.contains(k50)) {
        _announced.add(k50);
        _announced.add(k200);
        _announced.add(k500);
        _speak(_speech(m));
      } else if (_audioLevel == AudioLevel.completo && distM <= 200 && !_announced.contains(k200)) {
        _announced.add(k200);
        _announced.add(k500);
        _speak('Em 200 metros. ${_speech(m)}');
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
    // EXCEÇÃO ÚNICA do invariante: radar OFICIALMENTE desativado (status inactive,
    // fonte oficial) rebaixa de fala para bip discreto. Nunca some do mapa (visual
    // "desativado" na UI). Todo o resto da lógica de voz abaixo fica intacto.
    if (radar.status == 'inactive') {
      SystemSound.play(SystemSoundType.click);
      return;
    }
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
    final seq = ++_rerouteSeq;
    try {
      final prevDistM = _result.distanceMeters;
      final repo = context.read<RestrictionRepository>();

      final manualAvoidAreas = [
        ..._userRestrictions
            .where((r) => r.toBridgeRestriction().conflictsWith(widget.truck))
            .map((r) => r.toBridgeRestriction().toAvoidArea()),
        ..._result.restrictionsAvoided.map((r) => r.toAvoidArea()),
      ];

      // Rumo de marcha entra sempre que o GPS dá rumo confiável — medido pela
      // velocidade FÍSICA (_headingReliable), NÃO pela _speedKmh, que é a
      // velocidade ao longo da rota e zera quando !movingByRoute.
      //
      // Era o deadlock do field 2026-07-13 (42 reroutes em 13 min): o caminhão
      // andava CONTRA a rota → não avançava NA rota → _speedKmh=0 → course=null →
      // a HERE recalculava CEGA e devolvia a mesma meia-volta → hdgDelta seguia
      // ~177° → rerotava de novo. O course era suprimido exatamente na situação em
      // que ele é indispensável. Probe na HERE: sem course a rota nasce a 177° do
      // rumo dele; com course, a 16° (mesma quilometragem) → o storm morre.
      final course = _headingReliable ? _bearing : null;
      FieldLog.event('reroute_course', {
        'course': course?.round(),
        'speedKmh': _speedKmh.round(),
        'rawKmh': _rawSpeedKmh.round(),
      });

      final newResult = await HereRoutingService.calculateRoute(
        origin:      origin,
        destination: widget.destination,
        truck:       widget.truck,
        course:      course,
        waypoints:   widget.waypoints,
        avoidAreas:  manualAvoidAreas,
      );
      final hereMs = recalcSw.elapsedMilliseconds;
      if (!mounted || seq != _rerouteSeq) return;

      // ── FASE 1: destravar a tela ─────────────────────────────────────────────
      // Só entra aqui o que NÃO depende de rede. Enquanto _isRerouting está de pé o
      // _onPositionUpdate faz early-return: a seta congela, a instrução some e o
      // velocímetro para. Segurar isso esperando radar do Firestore cegava o
      // motorista por 2,8s na mediana e 20,8s no pior caso (field 2026-07-13) — e o
      // Pedro desviou 11 vezes num drive de 12min, ou seja, pagou o preço 11 vezes.
      // A rota nova é o que tira ele da cegueira; radar e restrição crowd são
      // enriquecimento e vão pra FASE 2, em background.
      final csvNearby = await _csvRadaresNearRoute(newResult.polylinePoints);
      // Verdictos do curador deste device: cache em memória, sem rede. Sem eles um
      // radar NEGADO ressuscitaria na tela durante a janela do enrichment.
      final localOverrides = await FirestoreRadarService.loadLocalOverrides();
      if (!mounted || seq != _rerouteSeq) return;
      setState(() {
        _result                  = newResult;
        _radares                 = applyOverrides(csvNearby, localOverrides);
        _closestPolylineIdx      = 0;
        _predIdx                 = 0; // rota nova começa na posição atual (índice 0)
        _anchorIdx               = 0;
        _overlaysSplitIdx        = null; // invalida cache de overlays: geometria mudou
        _maneuverIndex           = 0;
        _distToNextManeuver      = double.infinity;
        _hasTimeRestrictionAlert = newResult.hasTimeRestriction;
        _restrictionLabel        = newResult.restrictionLabel;
        _restrictionPoints       = newResult.restrictionPoints;
        _announced.clear();
        _lastRadarAlertKey       = null;
        _lastRestrictionAlertKey = null;
        // NÃO limpar _iconCache: é keyed por conteúdo (tipo+velocidade), não por
        // rota — os mesmos bitmaps servem após o reroute. Limpar forçava regerar
        // todos via PictureRecorder.toImage() = pico de main thread a cada
        // recálculo (pior no storm). _radarIconsFuture rebuilda com cache-hit.
        _radarIconsFuture        = null;
      });
      // Abre a carência: segura o re-disparo enquanto a rota nova assenta e o
      // GPS/âncora alcançam (anti-encadeamento, field 2026-06-29).
      _rerouteGraceUntil = DateTime.now().add(
          const Duration(milliseconds: _rerouteGraceMs));
      // Pós-reroute: não re-anunciar (storm "Em 500 metros") manobra que já
      // estamos em cima. Semeia os tiers já ultrapassados no instante do
      // recálculo — só fala quando o caminhão chegar MAIS perto. (maneuvers em
      // ordem de rota → para de semear ao passar de 500m.)
      for (var i = 0; i < newResult.maneuvers.length; i++) {
        final mv = newResult.maneuvers[i];
        if (mv.action == 'depart' || mv.action == 'arrive') continue;
        final d = RadarService.haversine(origin.latitude, origin.longitude,
            mv.position.latitude, mv.position.longitude);
        if (d > 500) break;
        _announced.add(i * 10 + 0);
        if (d <= 200) _announced.add(i * 10 + 1);
        if (d <= 50)  _announced.add(i * 10 + 2);
      }
      // Instrumentação P0 (logcat / `flutter logs`): separa detecção (corredor) de
      // recálculo. hereMs = só a rota (o que o motorista espera de fato desde o
      // fix da FASE 1); recalcMs = até a tela destravar. A diferença entre os dois
      // é o que a FASE 1 tirou do caminho crítico — o antigo recalcMs incluía os 4
      // round-trips de Firestore que hoje rodam em background.
      debugPrint('[REROUTE] urgent=$urgent detecção=${detectMs}ms '
          'here=${hereMs}ms destravou=${recalcSw.elapsedMilliseconds}ms');
      FieldLog.event('reroute_done', {
        'urgent':   urgent,
        'detectMs': detectMs,
        'hereMs':   hereMs,
        'recalcMs': recalcSw.elapsedMilliseconds,
        'points':   newResult.polylinePoints.length,
        'distM':    newResult.distanceMeters.round(),
      });
      if (newResult.hasTimeRestriction && !_timeRestrictionAlertSpoken) {
        _timeRestrictionAlertSpoken = true;
        _speak('Atenção! Restrição para caminhões nesta via');
        _flashTimeBanner();
      } else if (!newResult.hasTimeRestriction) {
        _timeRestrictionAlertSpoken = false;
      }
      _loadRoutePois();
      _refreshPoliceTimeline();
      // Só anuncia num desvio REAL (urgent = saiu do corredor). O refresh
      // periódico de 10min é background: atualiza trânsito/rota em silêncio —
      // falar "Rota recalculada" sem o motorista ter saído da rota era o ruído
      // que o Gilberto reclamou. Ainda exige nível completo e mudança >500m.
      if (urgent &&
          _audioLevel == AudioLevel.completo &&
          (newResult.distanceMeters - prevDistM).abs() > 500) {
        _speak('Rota recalculada');
      }

      // ── FASE 2: enrichment ───────────────────────────────────────────────────
      // Sai do caminho crítico: a rota já está na tela e o _isRerouting cai no
      // finally logo abaixo. Sem await de propósito — é isto que destrava a seta.
      unawaited(_enrichRoute(newResult, seq, csvNearby, repo));
    } catch (e, st) {
      // Não vaza pro usuário (princípio do Márcio), mas não some: sobe como
      // non-fatal pro Crashlytics + breadcrumb. Antes era catch(_) {} mudo.
      FieldLog.error('reroute', e, st);
    } finally {
      // Só o reroute mais recente destrava: um encadeado (seq maior) já assumiu o
      // controle e não pode ter o _isRerouting derrubado pelo finally do antigo.
      if (mounted && seq == _rerouteSeq) setState(() => _isRerouting = false);
    }
  }

  /// Radares do CSV perto da rota. Tudo local: o `load()` é cache estático, o resto
  /// é CPU. Lombada sem velocidade é ruído da base — não vira alerta.
  Future<List<RadarPoint>> _csvRadaresNearRoute(List<LatLng> pts) async {
    final all = await RadarService.load();
    return RadarService.deduplicateNearby(RadarService.filterNearRoute(all, pts))
        .where((r) =>
            !(r.type.toLowerCase().contains('lombada') && r.speedKmh == 0))
        .toList();
  }

  /// FASE 2 do recálculo: o que depende de REDE (restrições crowd + radar crowd +
  /// verdictos globais do curador). Roda DEPOIS que a rota já está na tela, porque
  /// nada disso justifica congelar a navegação — eram 4 round-trips de Firestore
  /// em série dentro do recalcMs.
  ///
  /// Fail-open: se a rede cair, o motorista fica com a rota da HERE + os radares do
  /// CSV + os verdictos locais. Perde o crowd, não perde a navegação.
  Future<void> _enrichRoute(RouteResult route, int seq,
      List<RadarPoint> csvNearby, RestrictionRepository repo) async {
    final sw = Stopwatch()..start();
    try {
      final pts = route.polylinePoints;
      // Independentes entre si → em paralelo. Em série uma rede ruim somava os RTTs.
      final (restrictions, radares) = await (
        repo.fetchNearRoute(pts),
        FirestoreRadarService.mergeCrowd(csvNearby, pts),
      ).wait;
      // Outro reroute entrou no meio: este resultado é de uma rota que já morreu.
      // Aplicá-lo colaria radar/restrição da rota velha por cima da nova.
      if (!mounted || seq != _rerouteSeq) return;
      final conflicts =
          restrictions.where((r) => r.conflictsWith(widget.truck)).toList();
      setState(() {
        if (conflicts.isNotEmpty) {
          _result = _result.copyWith(restrictionsBlocked: conflicts);
        }
        _radares = radares;
        // NÃO zera _radarIconsFuture: ele é indexado por _visibleRadares, que não
        // mudou aqui. O próximo _onPositionUpdate recalcula os visíveis a partir do
        // _radares novo e refaz os ícones via radarListChanged. Zerar só faria o
        // radar sumir do mapa até o fix seguinte — um piscar a mais por recálculo.
      });
      FieldLog.event('reroute_enrich', {
        'ms':      sw.elapsedMilliseconds,
        'radares': radares.length,
        'restr':   conflicts.length,
      });
    } catch (e, st) {
      FieldLog.error('reroute_enrich', e, st);
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
      const h = 50.0;
      // número + " km/h" na mesma linha embaixo. O km/h ao lado do número deixa
      // claro que é velocidade (pedido Gilberto/Pedro 2026-07-09). Largura do
      // retângulo cresce pra caber o grupo.
      final numTp = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
          text: r.speedKmh.toString(),
          style: TextStyle(
            fontSize: r.speedKmh >= 100 ? 11.0 : 13.0,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        )
        ..layout();
      final unitTp = TextPainter(textDirection: TextDirection.ltr)
        ..text = const TextSpan(
          text: ' km/h',
          style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600, color: Colors.white),
        )
        ..layout();
      final rowW = numTp.width + unitTp.width;
      final w = max(44.0, rowW + 12.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(8)),
        Paint()..color = bgColor,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(8)),
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
      // centrados como grupo, alinhados pela base.
      final rowX  = (w - rowW) / 2;
      final baseY = h - numTp.height - 4;
      numTp.paint(canvas, Offset(rowX, baseY));
      unitTp.paint(
          canvas, Offset(rowX + numTp.width, baseY + (numTp.height - unitTp.height)));
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
      // Trânsito: pinta só os trechos lentos à frente por cima do azul.
      ..._trafficOverlays(pts, splitIdx),
    };
  }

  // Overlay de trânsito: um Polyline por trecho lento/parado da parte AINDA não
  // percorrida (>= splitIdx). free não pinta — a linha azul base aparece. Cada
  // span vale do seu offset até o offset do próximo (por isso o serviço guarda
  // os free como fronteira). Bounds defensivos (RangeError já mordeu aqui antes).
  Iterable<Polyline> _trafficOverlays(List<LatLng> pts, int splitIdx) sync* {
    final spans = _result.trafficSpans;
    for (var i = 0; i < spans.length; i++) {
      if (spans[i].level == TrafficLevel.free) continue;
      final start = spans[i].offset.clamp(0, pts.length - 1);
      final end = (i + 1 < spans.length ? spans[i + 1].offset : pts.length - 1)
          .clamp(0, pts.length - 1);
      final from = start < splitIdx ? splitIdx : start; // só o que falta andar
      if (from >= end) continue;
      yield Polyline(
        polylineId: PolylineId('traffic_$i'),
        points: pts.sublist(from, end + 1),
        color: spans[i].level == TrafficLevel.heavy
            ? Colors.red.shade600
            : Colors.orange.shade600,
        width: 10,
        zIndex: 2, // acima do nav_remaining (azul)
      );
    }
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

  // O follow comanda sempre zoom==_zoom e target==_animPos. Se o onCameraMove
  // reporta algo divergente, foi o dedo do usuário (pinch/arrasto) → olhar-ao-redor.
  void _onCameraMove(CameraPosition pos) {
    _cameraTarget = pos.target;
    if (_markingMode || _paused || _arrived) return;
    // Antes do primeiro fix o _animPos ainda está no default (Brasília): o fit
    // inicial no GPS real dá panM de centenas de km e disparava free-look em
    // TODA abertura. Sem posição real não há follow nem gesto que faça sentido.
    if (_lastPosUpdateAt == null) return;
    if (_ignoreGestureUntil != null &&
        DateTime.now().isBefore(_ignoreGestureUntil!)) {
      return;
    }
    final zoomDelta = pos.zoom - _zoom;
    final zoomDiverged = zoomDelta.abs() > 0.2;
    // Eco do nosso próprio follow? Se o alvo bate (<40m) com QUALQUER alvo que
    // comandamos nos últimos frames, foi moveCamera nosso — mesmo atrasado por
    // um stall da main thread (o callback chega defasado, mas a posição defasada
    // ainda é uma que nós mandamos). Só um alvo que NUNCA comandamos é o dedo.
    // Zoom REPORTADO (pos.zoom), não o comandado: a tolerância tem que valer pro
    // frame que a plataforma acabou de mandar, que é onde o offset do padding vive.
    final isEcho = targetIsEcho(_cmdTargets, pos.target, pos.zoom);

    // Pinça (zoom): adota o zoom do gesto (fonte única) e MANTÉM o estado — no
    // follow a câmera segue já no novo zoom; em free-look só ajusta o nível. Nunca
    // dispara free-look (o pan que acompanha a pinça é ignorado de propósito). Sem
    // isto o follow reverteria o zoom do usuário no tick seguinte (zoom preso).
    if (zoomDiverged) {
      _zoom = pos.zoom;
      _lastUserGestureAt = DateTime.now();
      _lastZoomAt = DateTime.now();
      return;
    }

    // Olhar-ao-redor: só com DEDO. Ver cameraMoveIsGesture (topo do arquivo) — é lá
    // que mora a invariante e o porquê de a geometria sozinha não bastar.
    final touchAgeMs = _lastPointerAt == null
        ? -1
        : DateTime.now().difference(_lastPointerAt!).inMilliseconds;
    if (cameraMoveIsGesture(
      touchAgeMs: touchAgeMs,
      isEcho: isEcho,
      fingerActive: _fingerActive,
      zoomJustChanged: _zoomJustChanged,
    )) {
      // Rescaldo de pinça: o pan que acompanha o zoom não vira olhar-ao-redor —
      // adota o zoom (já feito acima) e segue no follow.
      if (_lastZoomAt != null &&
          DateTime.now().difference(_lastZoomAt!).inMilliseconds < _zoomCooldownMs) {
        return;
      }
      _lastUserGestureAt = DateTime.now();
      if (!_freeLook) {
        final msSinceProg = _lastProgrammaticMoveAt != null
            ? DateTime.now().difference(_lastProgrammaticMoveAt!).inMilliseconds
            : -1;
        final panM = RadarService.haversine(
            pos.target.latitude, pos.target.longitude,
            _animPos.latitude, _animPos.longitude);
        // cause='finger': ativou pelo _fingerActive (alvo eco/colinear + dedo na
        // tela) = o arrasto reto pra frente. Se este cause aparecer no field_log,
        // o Listener PEGOU o toque na platform view → valida o fix do item 1.
        final cause = isEcho ? 'finger' : 'pan';
        debugPrint('[FREELOOK] enter cause=$cause '
            'panM=${panM.round()} msSinceProg=$msSinceProg');
        // zoom + touchAgeMs são os pontos cegos que impediram o diagnóstico de
        // 2026-07-13: sem o zoom não dá pra saber se o panM é offset de padding
        // (que escala com o zoom) ou arrasto de verdade, e sem a idade do toque
        // não dá pra provar que ninguém encostou na tela. Nunca mais sem eles.
        FieldLog.event('freelook_enter', {
          'cause': cause,
          'panM': panM.round(),
          'msSinceProg': msSinceProg,
          'zoom': pos.zoom.toStringAsFixed(1),
          'touchAgeMs': touchAgeMs,
        });
        setState(() => _freeLook = true);
      }
    }
  }

  void _recenter() {
    // Qualquer retomada de câmera sai do olhar-ao-redor. O snap único de moveCamera
    // não deve re-disparar o free-look (_ignoreGestureUntil cobre o frame de transição).
    if (_freeLook) setState(() => _freeLook = false);
    final progNow = DateTime.now();
    _lastProgrammaticMoveAt = progNow;
    _ignoreGestureUntil = progNow.add(const Duration(milliseconds: 900));
    final pos = _snappedPos ?? _currentPos;
    if (pos == null || _mapController == null) return;
    // moveCamera (instantâneo), NÃO animateCamera: o glide do animate transmitia
    // frames de zoom divergente que ligavam o free-look → marker azul travado e
    // recenter que não "pegava" (P0 Gilberto, v2.4.5). É o mesmo motivo de resume
    // e follow usarem moveCamera. Snap no zoom é aceitável e mata o loop de vez.
    _recordCmd(pos);
    _mapController!.moveCamera(
      CameraUpdate.newCameraPosition(CameraPosition(
        target:  pos,
        zoom:    _zoom,
        tilt:    45,
        bearing: _bearing,
      )),
    );
  }

  // Registra um alvo que comandamos, p/ o _onCameraMove distinguir eco de gesto.
  // Cap ~120 (a 30fps do follow ≈ 4s) cobre o atraso de callback de um stall.
  void _recordCmd(LatLng t) {
    _cmdTargets.add(t);
    if (_cmdTargets.length > 120) _cmdTargets.removeAt(0);
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

  // ── Marcar restrição / radar — fluxo crosshair ───────────────────────────────

  // Um FAB só: escolhe o que marcar antes de entrar no crosshair (UI glanceável).
  Future<void> _startMarking() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.add_road, color: Colors.teal),
            title: const Text('Restrição'),
            subtitle: const Text('Altura, peso, largura, terra…'),
            onTap: () => Navigator.pop(context, 'restriction'),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Colors.red),
            title: const Text('Radar'),
            subtitle: const Text('Radar fixo ou lombada'),
            onTap: () => Navigator.pop(context, 'radar'),
          ),
        ]),
      ),
    );
    if (kind == null || !mounted) return;
    _enterMarkingMode(radar: kind == 'radar');
  }

  void _enterMarkingMode({bool radar = false}) {
    final pos = _currentPos ?? widget.destination;
    _cameraTarget = pos;
    setState(() { _markingMode = true; _markingRadar = radar; _freeLook = false; });
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(
        target: pos,
        zoom: 17,
        tilt: 0,
      )),
    );
  }

  void _exitMarkingMode() {
    setState(() { _markingMode = false; _markingRadar = false; });
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

    final (:minLat, :maxLat, :minLng, :maxLng) = boundsOf(pts);
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

    final (:minLat, :maxLat, :minLng, :maxLng) = boundsOf(ahead);
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

    final (:minLat, :maxLat, :minLng, :maxLng) = boundsOf(aheadPts);
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

    // Clima severo à frente (Fatia B, visual). Célula amostrada da própria
    // polyline, então corredor generoso. Sem voz — só entra na barra de eventos.
    double bestWeatherDist = double.infinity;
    WeatherAlert? nearestWeather;
    for (final a in _weatherAlerts) {
      if (!isAhead(a.position.latitude, a.position.longitude, 500)) continue;
      final d = distFrom(a.position.latitude, a.position.longitude);
      if (d < bestWeatherDist) {
        bestWeatherDist = d;
        nearestWeather = a;
      }
    }
    if (nearestWeather != null) {
      candidates.add(RouteEvent(
        type: RouteEventType.weather,
        distanceM: bestWeatherDist,
        label: nearestWeather.shortLabel, // "Chuva"/"Vento"/"Neblina" da HERE
      ));
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
    final isRadar = _markingRadar;
    setState(() { _markingMode = false; _markingRadar = false; });
    if (isRadar) { await _confirmRadarMark(pos); return; }
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

  Future<void> _confirmRadarMark(LatLng pos) async {
    final radar = await showModalBottomSheet<RadarPoint>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => AddRadarSheet(position: pos),
    );
    if (radar == null || !mounted) { _recenter(); return; }
    String? id;
    try {
      final uid = await AuthService.getUid();
      id = await FirestoreRadarService.add(
        lat: radar.lat, lng: radar.lng, type: radar.type,
        speedKmh: radar.speedKmh, uid: uid,
      );
    } catch (_) {/* sem auth: mostra local nesta sessão, sem id (não compartilha) */}
    if (!mounted) return;
    // Mostra já localmente (com o id do doc, pra permitir remover depois).
    final local = RadarPoint(lat: radar.lat, lng: radar.lng, type: radar.type,
        speedKmh: radar.speedKmh, id: id, source: 'user');
    setState(() {
      _radares.add(local);
      _visibleRadares = List.of(_visibleRadares)..add(local);
      _radarIconsFuture = Future.wait(_visibleRadares.map(_radarIcon));
    });
    _recenter();
  }

  // Toque num radar: curadoria do Gilberto (palavra = fato). Não existe → some;
  // existe → mantém; existe @ X → troca a velocidade. Grava override local-first
  // (autoritativo, offline) + espelho no Firestore. Editável passando de novo.
  Future<void> _onRadarTap(RadarPoint r) => _curateRadar(r);

  Future<void> _curateRadar(RadarPoint r) async {
    final action = await _showCurationSheet(r);
    if (action == null || !mounted) return;
    if (action == 'remove') { await _applyRadarVerdict(r, false); return; }
    // 'confirm' (mantém velocidade) ou 'speed:X' (troca)
    final speed = action.startsWith('speed:') ? int.parse(action.substring(6)) : 0;
    await _applyRadarVerdict(r, true, speed: speed);
  }

  // Grava o verdicto (override local-first + Firestore) e atualiza as listas na
  // hora. Compartilhado pela folha (toque) e pelo pop-up automático.
  Future<void> _applyRadarVerdict(RadarPoint r, bool exists, {int speed = 0}) async {
    _curatedKeys.add(dismissalKey(r.lat, r.lng));
    final uid = await AuthService.getUid();
    await FirestoreRadarService.setOverride(
        lat: r.lat, lng: r.lng, exists: exists, speedKmh: speed, uid: uid);
    if (exists && speed <= 0) return; // confirmado sem trocar velocidade: nada muda na lista
    if (!mounted) return;
    bool sameAs(RadarPoint x) => x.lat == r.lat && x.lng == r.lng && x.type == r.type;
    setState(() {
      if (!exists) {
        _radares.removeWhere(sameAs);
        _visibleRadares = List.of(_visibleRadares)..removeWhere(sameAs);
      } else {
        _radares = _radares.map((x) => sameAs(x) ? x.copyWith(speedKmh: speed) : x).toList();
        _visibleRadares =
            _visibleRadares.map((x) => sameAs(x) ? x.copyWith(speedKmh: speed) : x).toList();
      }
      _radarIconsFuture = Future.wait(_visibleRadares.map(_radarIcon));
    });
    if (!exists) widget.onRadarRemoved?.call(r); // poda o cache do mapa
  }

  // ── Pop-up de curadoria (surge sozinho ao chegar no radar) ────────────────────

  // Chegou num radar sem verdicto → abre o card (uma vez por radar/sessão).
  void _maybePromptCuration(RadarPoint? radar, LatLng pos) {
    if (radar == null || _markingMode || _arrived || _curationPrompt != null) return;
    final key = dismissalKey(radar.lat, radar.lng);
    if (_curatedKeys.contains(key) || _promptedKeys.contains(key)) return;
    if (RadarService.haversine(pos.latitude, pos.longitude, radar.lat, radar.lng) >
        _radarReachedM) {
      return;
    }
    _promptedKeys.add(key);
    setState(() { _curationPrompt = radar; _curationSpeedStep = false; });
    _restartCurationTimer();
  }

  void _restartCurationTimer() {
    _curationTimer?.cancel();
    _curationTimer = Timer(const Duration(seconds: 6), _closeCuration);
  }

  void _closeCuration() {
    _curationTimer?.cancel();
    if (mounted) setState(() { _curationPrompt = null; _curationSpeedStep = false; });
  }

  void _curationDeny() {
    final r = _curationPrompt;
    if (r != null) _applyRadarVerdict(r, false);
    _closeCuration();
  }

  // "Existe" confirma na hora (mantém velocidade) e abre os chips pra refinar.
  void _curationConfirm() {
    final r = _curationPrompt;
    if (r == null) return;
    _applyRadarVerdict(r, true);
    setState(() => _curationSpeedStep = true);
    _restartCurationTimer();
  }

  void _curationSetSpeed(int speed) {
    final r = _curationPrompt;
    if (r != null) _applyRadarVerdict(r, true, speed: speed);
    _closeCuration();
  }

  Widget _buildCurationCard() {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: _curationSpeedStep
            // Presets + placa EM BRANCO. O Gilberto passou por um radar de 40 na
            // cidade e aqui o mínimo era 60 (campo 13/07) — a curadoria não podia
            // corrigir a velocidade real, que é justamente o que ela existe pra fazer.
            ? SpeedPlatePicker(
                selected: null,
                onChanged: _curationSetSpeed,
              )
            : Row(
                children: [
                  const Icon(Icons.camera_alt, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Tem radar aqui?',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    onPressed: _curationDeny,
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.red.shade300),
                    child: const Text('NÃO'),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton(
                    onPressed: _curationConfirm,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white),
                    child: const Text('SIM'),
                  ),
                ],
              ),
      ),
    );
  }

  // Folha de curadoria: 1 toque resolve. Chips 60/70/80/90 = velocidade real
  // (confirma + troca). "Existe" mantém a atual. "Não existe" mata.
  Future<String?> _showCurationSheet(RadarPoint r) => showModalBottomSheet<String>(
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
    // Split segue o predIdx interpolado (a seta), não o _closestPolylineIdx do
    // GPS — assim o rastro cinza cola na seta. O tick throttla o rebuild.
    final splitIdx = _predIdx.clamp(0, pts.length - 1);
    // Memoização: recomputa overlays só quando o trecho/raio realmente muda
    // (≈1Hz do GPS), não a cada frame da animação do marcador (60fps).
    // Mantendo a mesma instância de Set entre frames, o google_maps_flutter
    // não re-difunde a geometria pelo channel.
    if (_overlaysSplitIdx != splitIdx) {
      _overlaysSplitIdx = splitIdx;
      _polylines        = _buildPolylines(pts, splitIdx);
    }
    final polylines    = _polylines;

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('destination'),
        position: widget.destination,
        infoWindow: InfoWindow(title: 'Destino', snippet: widget.destinationLabel),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      // Puck do usuário NÃO é mais um Marker. Atualizar posição de Marker via
      // method channel a cada frame era o gargalo do lag (flutter#33430). Agora
      // é um widget Flutter fixo (NavPuck) sobreposto no Stack — câmera segue a
      // posição (com padding pra deixar a seta embaixo). Só o destino é Marker.
      // Pausado: a câmera e o caminhão estão parados → pino ancorado no mapa.
      if (_paused && _currentPos != null)
        Marker(
          markerId: const MarkerId('you_freelook'),
          position: _snappedPos ?? _currentPos!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.5),
        ),
      // Olhar-ao-redor: a seta CONTINUA andando no mapa (posição predita + rumo),
      // enquanto a câmera fica livre onde o usuário arrastou (ex: olhar uns km à
      // frente pra ver blitz sem perder de vista onde está). Pino é só no pause.
      if (_freeLook && !_paused && _puckIcon != null && _currentPos != null)
        Marker(
          markerId: const MarkerId('you_freelook'),
          position: _animPos,
          icon: _puckIcon!,
          rotation: _animBearing,
          flat: true,
          anchor: const Offset(0.5, 0.5),
        ),
    };

    // Pins das restrições de caminhão da HERE (altura/peso/horário/acesso).
    // Laranja = distinto de destino (verde), radar (ícone) e você (azul).
    // Toque abre o rótulo (InfoWindow nativo).
    for (final rp in _restrictionPoints) {
      markers.add(Marker(
        markerId: MarkerId('hrestr_${rp.position.latitude}_${rp.position.longitude}'),
        position: rp.position,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(title: rp.label),
      ));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Barra de instrução ──────────────────────────────────────────
            InstructionBar(
              maneuver:     nextM,
              distance:     _distToNextManeuver,
              dirIcon:      nextM != null ? _dirIcon(nextM) : Icons.straight,
              audioLevel:   _audioLevel,
              rerouting:    _isRerouting,
              isNight:      _themeController.isNight,
              onAudioCycle: _cycleAudioLevel,
              onClose:      _confirmFinish,
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
                        // _visibleRadares e os ícones (snap.data) são listas
                        // PARALELAS montadas em momentos diferentes. No reroute
                        // _radarIconsFuture vira null → Future.value([]) → ícones
                        // vazios enquanto _visibleRadares ainda tem radar; indexar
                        // snap.data![i] com i de _visibleRadares dava RangeError
                        // TODO FRAME e pintava o mapa de cinza. Limita ao menor.
                        final icons = snap.data!;
                        final n = min(_visibleRadares.length, icons.length);
                        for (var i = 0; i < n; i++) {
                          final radar = _visibleRadares[i];
                          markers.add(Marker(
                            markerId: MarkerId('r_${radar.lat}_${radar.lng}'),
                            position: LatLng(radar.lat, radar.lng),
                            icon: icons[i],
                            onTap: () => _onRadarTap(radar),
                          ));
                        }
                      }
                      // Clima na rota (Fatia B): marcador simples, SEM lista
                      // indexada de ícones → imune ao RangeError do reroute.
                      for (final a in _weatherAlerts) {
                        markers.add(Marker(
                          markerId: MarkerId('wx_${a.position.latitude}_${a.position.longitude}'),
                          position: a.position,
                          icon: _weatherIcon ??
                              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                          anchor: const Offset(0.5, 0.5),
                          infoWindow: InfoWindow(title: a.label),
                        ));
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
                      // padding.top empurra o alvo da câmera (= posição do
                      // caminhão) pra ~85% da altura → puck embaixo, pista à
                      // frente (UX Márcio). O nativo trata o tilt corretamente.
                      // Listener suspende o follow enquanto o dedo está na tela
                      // (_fingerDown): sem isto o follow — que segue a rota a 30fps —
                      // cancela o arrasto COLINEAR (pra frente) antes de virar
                      // olhar-ao-redor, e o gesto "não pegava" (item 1 do Gilberto).
                      // Não faz setState (lido direto por _predictTick/_onCameraMove).
                      return LayoutBuilder(
                        builder: (context, c) => Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: (_) { _lastPointerAt = DateTime.now(); _zoomJustChanged = false; },
                          onPointerMove: (_) { _lastPointerAt = DateTime.now(); _zoomJustChanged = false; },
                          child: GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: _currentPos ?? widget.destination,
                              zoom: 17,
                              tilt: 45,
                            ),
                            padding: EdgeInsets.only(
                              top: c.maxHeight * (2 * _puckYFrac - 1),
                            ),
                            onMapCreated: (ctrl) {
                              _mapController = ctrl;
                            },
                            style: _themeController.isNight ? kNightMapStyle : null,
                            onCameraMove: _onCameraMove,
                            polylines: polylines,
                            markers: markers,
                            trafficEnabled: false,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            compassEnabled: false,
                          ),
                        ),
                      );
                    },
                  ),
                  // ── Puck do usuário: widget Flutter fixo (fora do channel) ──
                  // Câmera heading-up → a seta aponta sempre pra cima; o mapa gira
                  // por baixo. Posição na tela casa com o padding do mapa.
                  if (_currentPos != null && _lastPosUpdateAt != null && !_markingMode && !_freeLook && !_paused)
                    Align(
                      alignment: const Alignment(0, 2 * _puckYFrac - 1),
                      child: const IgnorePointer(child: NavPuck()),
                    ),
                  // ── Alerta restrição bloqueada / horário ────────────────
                  if ((_nearbyBlockedRestriction != null || _timeBannerVisible) && !_markingMode)
                    Positioned(
                      bottom: 8,
                      left: 12,
                      right: 12,
                      // Banner de restrição da HERE (não o de restrição crowd, que
                      // tem botões próprios) → toque leva a câmera ao ponto restrito.
                      child: GestureDetector(
                        onTap: _nearbyBlockedRestriction == null
                            ? _showRestrictionOnMap
                            : null,
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
                                        : (_restrictionLabel ??
                                            'Restrição para caminhões nesta via'),
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
                        tooltip: 'Marcar restrição ou radar',
                        onPressed: _startMarking,
                        child: const Icon(Icons.add_location_alt),
                      ),
                    ),
                    // Botão centralizar — mesmo canto sempre (memória muscular).
                    // Seguindo: pequeno e neutro. Free-look: cresce e fica azul
                    // pra deixar óbvio que dá pra voltar a seguir.
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: _freeLook
                          ? FloatingActionButton.extended(
                              heroTag: 'nav_recenter',
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              elevation: 4,
                              tooltip: 'Voltar a seguir',
                              onPressed: _recenter,
                              icon: const Icon(Icons.my_location),
                              label: const Text('Centralizar'),
                            )
                          : FloatingActionButton.small(
                              heroTag: 'nav_recenter',
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF1565C0),
                              elevation: 4,
                              tooltip: 'Centralizar',
                              onPressed: _recenter,
                              child: const Icon(Icons.my_location),
                            ),
                    ),
                  ],
                  // Flash vermelho: acima do limite de caminhão em área de radar.
                  if (_speedAlertActive && !_markingMode && !_paused && !_arrived)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _flashAnim,
                          builder: (context, _) => ColoredBox(
                            color: Colors.red.withValues(alpha: _flashAnim.value),
                          ),
                        ),
                      ),
                    ),
                  // ── Pop-up de curadoria: surge sozinho ao chegar no radar ──────
                  if (_curationPrompt != null && !_markingMode && !_arrived)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 84,
                      child: _buildCurationCard(),
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

            // ── Barra inferior ──────────────────────────────────────────────
            BottomBar(
              speedKmh:      _speedKmh,
              limitKmh:      _currentLimitKmh,
              remainingDist: _fmtDist(remaining),
              eta:           _fmtEta(remSec),
              radarAlert:    _upcomingRadar,
              dirMatch:      _upcomingRadarDir,
            ),
          ],
        ),
      ),
    );
  }
}

/// Fração vertical (0=topo, 1=base) onde o puck fica na tela. ~0.85 = seta
/// embaixo, ~90% de pista à frente (pedido UX do Márcio). O padding.top do
/// GoogleMap e o Alignment do puck derivam disto: ambos usam (2*_puckYFrac-1).
const _puckYFrac = 0.85;
