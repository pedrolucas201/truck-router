import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config.dart';
import 'auth_service.dart';
import 'field_log.dart';
import '../models/route_maneuver.dart';
import '../models/route_result.dart';
import '../models/truck_profile.dart';
import 'flexible_polyline_decoder.dart';
import 'radar_service.dart';

/// Um span da rota + se ele cai em trecho com restrição violada. Só existe pro
/// invariante do destino inalcançável (ver [HereRoutingService.destinationBlockedLabel]).
typedef SpanViolation = ({int offset, bool violated, bool blocksMode});

class HereRoutingService {
  /// Teto da chamada de rota. Sem ele a navegação inteira congela pelo tempo que
  /// a rede quiser: enquanto `_isRerouting` está de pé, o `_onPositionUpdate`
  /// faz early-return e a seta para, a instrução some e o velocímetro trava.
  ///
  /// Campo 2026-07-22, sessão mrw3mjyd: um reroute levou `hereMs: 131734` — 2min11
  /// de tela morta a 56 km/h, ~2 km dirigidos às cegas. Os reroutes saudáveis da
  /// mesma viagem levaram 893ms, 1074ms, 1626ms e 1765ms, então 12s dá ~7x de
  /// folga sobre o pior caso legítimo e ainda fica abaixo dos 20,8s que a FASE 1
  /// já tinha classificado como inaceitável.
  ///
  /// Estourar é melhor que pendurar: o `_reroute` trata a exceção (loga) e o
  /// `finally` destrava a tela; o motorista segue com a rota anterior e a próxima
  /// tentativa vem sozinha. Ficar preso não tem saída nenhuma.
  static const routeTimeout = Duration(seconds: 12);

  /// Raio da 2ª tentativa quando o destino é inalcançável de caminhão: deixa a
  /// HERE encostar na borda LEGAL em vez de forçar entrada em via proibida.
  ///
  /// 300 m medido em bancada no caso real (centro de Taubaté, 03/08): a rota sai
  /// LIMPA (zero notice), fica **629 m mais curta** (29.087 vs 29.718) e termina
  /// a 194 m do pino. Sem ele a HERE entrega a melhor rota ILEGAL e passa a
  /// oscilar entre alternativas igualmente impossíveis perto do fim — foi o storm
  /// de 11 reroutes em 95 s do drive do Gilberto.
  static const destinationRadiusM = 300;

  /// Teto CURTO da 2ª tentativa. Ela é bônus: a rota da 1ª já está na mão, então
  /// o que não pode é dobrar o congelamento de tela que o `routeTimeout` existe
  /// pra limitar. Pior caso do par vira 12s + 6s em vez de 24s.
  static const _radiusRetryTimeout = Duration(seconds: 6);

  static Future<RouteResult> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    required TruckProfile truck,
    String? departureTime,
    double? course,
    List<LatLng> waypoints   = const [],
    List<String> avoidAreas  = const [],
    bool avoidDirtRoad        = true,
    // Só a 2ª tentativa preenche (ver destinationRadiusM). Null = pede o pino
    // exato, que é o certo pro caso normal — raio SEMPRE degradaria a precisão
    // de chegada de toda rota, inclusive as que alcançam o destino sem problema.
    int? destinationRadius,
    // Trava de recursão: a 2ª tentativa não tem direito a uma 3ª.
    bool allowDestinationRetry = true,
    Duration? timeout,
  }) async {
    // course = rumo de marcha (0-359, N=0). Informado, a HERE inicia a rota NESSE
    // sentido em vez de escolher a mais curta — evita o "dê meia-volta" no reroute.
    final originParam = course == null
        ? '${origin.latitude},${origin.longitude}'
        : '${origin.latitude},${origin.longitude};course=${course.round() % 360}';
    final params = <String, dynamic>{
      'transportMode':   'truck',
      'origin':          originParam,
      'destination':     destinationRadius == null
          ? '${destination.latitude},${destination.longitude}'
          : '${destination.latitude},${destination.longitude}'
              ';radius=$destinationRadius',
      'return':          'polyline,summary,actions',
      // spans é parâmetro PRÓPRIO — NÃO vai dentro de 'return' (isso dá E605001).
      // Com transportMode=truck a HERE já devolve o limite do CAMINHÃO por trecho.
      // dynamicSpeedInfo (sem departureTime) traz baseSpeed vs trafficSpeed = trânsito.
      // notices: cada span referencia o notice por índice + traz o offset → dá pra
      // fixar a restrição de caminhão num ponto do mapa (report Gilberto 12/07).
      'spans':           'speedLimit,dynamicSpeedInfo,notices',
      'lang':            'pt-BR',
      if (avoidDirtRoad) 'avoid[features]': 'dirtRoad',
      ...truck.toHereParams(),
      'departureTime': ?departureTime,
      if (waypoints.isNotEmpty)
        'via': waypoints.map((w) => '${w.latitude},${w.longitude}').toList(),
    };

    // Uri.https encodes brackets as %5B/%5D — HERE requires literal vehicle[height] notation.
    final parts = <String>[];
    params.forEach((key, value) {
      if (value == null) return;
      if (value is List) {
        for (final v in value) {
          parts.add('$key=${Uri.encodeQueryComponent(v.toString())}');
        }
      } else {
        parts.add('$key=${Uri.encodeQueryComponent(value.toString())}');
      }
    });
    // avoid[areas] usa ':' e '|' como delimitadores — não pode ser codificado.
    if (avoidAreas.isNotEmpty) {
      parts.add('avoid[areas]=${avoidAreas.join('|')}');
    }
    final uri = Uri.parse('$backendUrl/route/here?${parts.join('&')}');
    final response =
        await http.get(uri, headers: await AuthService.getHeaders())
            .timeout(timeout ?? routeTimeout);

    if (response.statusCode != 200) {
      throw Exception('HERE API error ${response.statusCode}: ${response.body}');
    }

    final data   = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = data['routes'] as List<dynamic>;
    if (routes.isEmpty) throw Exception('Nenhuma rota encontrada');

    final route0   = routes[0] as Map<String, dynamic>;
    final sections = route0['sections'] as List<dynamic>;

    // violatedVehicleRestriction inclui restrições de horário para caminhões.
    final routeNotices = route0['notices'] as List<dynamic>? ?? [];
    final sectionNotices = sections
        .cast<Map<String, dynamic>>()
        .expand((s) => s['notices'] as List<dynamic>? ?? [])
        .toList();
    final violatedNotices = [...routeNotices, ...sectionNotices]
        .cast<Map<String, dynamic>>()
        .where((n) => n['code'] == 'violatedVehicleRestriction')
        .toList();
    final hasTimeRestriction = violatedNotices.isNotEmpty;
    final restrictionLabel = _restrictionLabel(violatedNotices);

    final allPoints   = <LatLng>[];
    final allManeuvers = <RouteManeuver>[];
    var totalDistance = 0;
    var totalDuration = 0;
    final speedLimits = <SpeedLimitSpan>[];
    final trafficSpans = <TrafficSpan>[];
    final restrictionPoints = <RestrictionPoint>[];
    final seenRestriction = <String>{}; // dedup por posição+rótulo
    // TODOS os spans em ordem (não só o 1º de cada notice): o invariante do
    // destino precisa saber se o ÚLTIMO deles está restrito.
    final spanFlags = <SpanViolation>[];

    for (final s in sections) {
      final section      = s as Map<String, dynamic>;
      final summary      = section['summary'] as Map<String, dynamic>;
      final sectionOffset = allPoints.length;

      totalDistance += (summary['length'] as num).toInt();
      totalDuration += (summary['duration'] as num).toInt();

      final sectionPoints = FlexiblePolylineDecoder.decode(section['polyline'] as String);
      allPoints.addAll(sectionPoints);

      final actions = section['actions'] as List<dynamic>? ?? [];
      for (final a in actions) {
        final action = a as Map<String, dynamic>;
        final localOffset = (action['offset'] as num?)?.toInt() ?? 0;
        final globalOffset = sectionOffset + localOffset;
        final pos = globalOffset < allPoints.length
            ? allPoints[globalOffset]
            : allPoints.last;

        allManeuvers.add(RouteManeuver(
          instruction:     action['instruction'] as String? ?? '',
          action:          action['action'] as String? ?? 'continue',
          direction:       action['direction'] as String?,
          distanceMeters:  (action['length'] as num?)?.toInt() ?? 0,
          durationSeconds: (action['duration'] as num?)?.toInt() ?? 0,
          polylineOffset:  globalOffset,
          position:        pos,
        ));
      }

      // Limite de caminhão por trecho — HERE já dá ciente do modo (m/s).
      // offset do span é relativo à section: soma sectionOffset p/ virar índice
      // global na polyline (mesmo esquema das manobras acima).
      // Notices da seção: os índices em span['notices'] apontam pra CÁ.
      final secNotices =
          (section['notices'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final seenIdxInSection = <int>{}; // 1º offset de cada notice = início do trecho
      final spans = section['spans'] as List<dynamic>? ?? [];
      for (final sp in spans) {
        final span = sp as Map<String, dynamic>;
        final offset = sectionOffset + ((span['offset'] as num?)?.toInt() ?? 0);

        final speedMs = (span['speedLimit'] as num?)?.toDouble();
        if (speedMs != null && speedMs > 0) {
          speedLimits.add(SpeedLimitSpan(offset, (speedMs * 3.6).round()));
        }

        // Restrição de caminhão neste trecho → ponto no mapa. O span traz os
        // índices dos notices da seção; o 1º span que cita um notice = onde o
        // trecho restrito começa.
        var spanViolated = false;
        var spanBlocksMode = false;
        for (final ni in (span['notices'] as List?)?.cast<num>() ?? const []) {
          final i = ni.toInt();
          if (i < 0 || i >= secNotices.length) continue;
          final n = secNotices[i];
          if (n['code'] != 'violatedVehicleRestriction') continue;
          spanViolated = true;
          if (_blocksTransportMode(n)) spanBlocksMode = true;
          // dedup DEPOIS das flags: o 1º span marca o pin, mas todo span
          // restrito conta pro bloco final do invariante.
          if (!seenIdxInSection.add(i)) continue;
          final pos = offset < allPoints.length ? allPoints[offset] : allPoints.last;
          final label = _labelForNotice(n) ?? 'Restrição para caminhões nesta via';
          final key = '${pos.latitude},${pos.longitude}|$label';
          if (seenRestriction.add(key)) {
            restrictionPoints.add(RestrictionPoint(pos, label));
          }
        }
        spanFlags.add(
            (offset: offset, violated: spanViolated, blocksMode: spanBlocksMode));

        // Trânsito: razão trafficSpeed/baseSpeed. Guarda TODOS os spans (inclusive
        // free) — o free serve de fronteira p/ o render saber onde o trecho lento
        // termina; só free não é pintado.
        final dsi = span['dynamicSpeedInfo'] as Map<String, dynamic>?;
        final base = (dsi?['baseSpeed'] as num?)?.toDouble();
        final traffic = (dsi?['trafficSpeed'] as num?)?.toDouble();
        if (base != null && base > 0 && traffic != null) {
          trafficSpans.add(TrafficSpan(offset, TrafficLevel.fromRatio(traffic / base)));
        }
      }
    }

    // ── Destino inalcançável ────────────────────────────────────────────────
    // INVARIANTE: se o trecho restrito alcança o ÚLTIMO span, o problema não é
    // de passagem — é que o DESTINO não é atingível com este veículo.
    //
    // A HERE devolve a rota assim de propósito: quando a restrição cai em cima
    // do waypoint, ela viola o acesso pra conseguir entregar ("violating
    // restrictions can't be avoided when restrictions apply on a waypoint") e
    // sinaliza pelo notice. Nós líamos o notice e dizíamos "restrição NESTA
    // VIA" — aviso de trecho pra um problema de destino. Isso não é neutro:
    // ensina o motorista a ignorar o alerta, porque ele olha a rodovia, não vê
    // restrição nenhuma e conclui que o app erra (campo 03/08: os últimos 225 m
    // até um destino no centro de Taubaté são ruas proibidas a caminhão; a rota
    // vira pedido de retorno + volta pela cidade, e a HERE fica oscilando entre
    // alternativas igualmente impossíveis dentro da tolerância dela).
    //
    // Por que o último span e não "últimos N metros": limiar fixo erra dos dois
    // lados — perde a proibição que começa antes de N e alcança o destino, e
    // pega a que termina antes dele (onde o rótulo de trecho já está certo).
    final blockedLabel = destinationBlockedLabel(spanFlags, allPoints);

    final result = RouteResult(
      polylinePoints:    allPoints,
      distanceMeters:    totalDistance,
      durationSeconds:   totalDuration,
      maneuvers:         allManeuvers,
      hasTimeRestriction: hasTimeRestriction,
      restrictionLabel:   blockedLabel ?? restrictionLabel,
      destinationBlocked: blockedLabel != null,
      restrictionPoints:  restrictionPoints,
      speedLimits:        speedLimits,
      trafficSpans:       trafficSpans,
    );

    // O rótulo EXPLICA o problema mas não muda a rota — sozinho, o motorista
    // segue rodando a rota ilegal (e ouvindo a HERE mandar dar meia-volta perto
    // do fim). A 2ª tentativa é o que muda o que ele DIRIGE.
    //
    // `destinationBlocked` já é o gate certo: ele só fica true quando a violação
    // é de ACESSO (blocksMode) E alcança o último span. Restrição de dimensão ou
    // de trecho no meio do caminho não entra aqui — nessas o pino continua
    // alcançável e relaxar o destino só perderia precisão de chegada à toa.
    if (result.destinationBlocked && allowDestinationRetry) {
      final relaxed = await _retryOutsideBlockedDestination(
        blocked:       result,
        origin:        origin,
        destination:   destination,
        truck:         truck,
        departureTime: departureTime,
        course:        course,
        waypoints:     waypoints,
        avoidAreas:    avoidAreas,
        avoidDirtRoad: avoidDirtRoad,
      );
      if (relaxed != null) return relaxed;
    }
    return result;
  }

  /// 2ª tentativa com raio no destino. Devolve null quando não vale a troca —
  /// aí o chamador segue com [blocked], que ao menos encosta no pino.
  static Future<RouteResult?> _retryOutsideBlockedDestination({
    required RouteResult blocked,
    required LatLng origin,
    required LatLng destination,
    required TruckProfile truck,
    String? departureTime,
    double? course,
    required List<LatLng> waypoints,
    required List<String> avoidAreas,
    required bool avoidDirtRoad,
  }) async {
    try {
      final relaxed = await calculateRoute(
        origin:                origin,
        destination:           destination,
        truck:                 truck,
        departureTime:         departureTime,
        course:                course,
        waypoints:             waypoints,
        avoidAreas:            avoidAreas,
        avoidDirtRoad:         avoidDirtRoad,
        destinationRadius:     destinationRadiusM,
        allowDestinationRetry: false,
        timeout:               _radiusRetryTimeout,
      );
      // Continua presa? Não ganhamos nada — e a rota da 1ª pelo menos vai até o
      // pino. Trocar por outra igualmente ilegal só embaralha.
      if (relaxed.destinationBlocked) return null;

      FieldLog.event('route_dest_radius', {
        'distBeforeM': blocked.distanceMeters,
        'distAfterM':  relaxed.distanceMeters,
        // Negativo = a rota legal ficou MAIS LONGA. No caso medido veio -629
        // (mais curta). Se o campo mostrar rota muito mais longa, é sinal de que
        // a HERE ancorou num ponto ruim — aí o raio vira condicional por delta.
        // ponytail: sem teto de piora por enquanto; o log é que decide o número.
        'deltaM':      relaxed.distanceMeters - blocked.distanceMeters,
      });

      return graftBlockedWarning(relaxed: relaxed, blocked: blocked);
    } catch (e) {
      // A 2ª tentativa é BÔNUS: rede caída, timeout curto, resposta estranha —
      // nada disso pode derrubar uma rota que já está pronta na mão.
      FieldLog.event('route_dest_radius_fail', {'err': e.toString()});
      return null;
    }
  }

  /// Leva o aviso da rota bloqueada pra rota relaxada.
  ///
  /// ⚠️ AQUI mora a coerência da 2ª tentativa. A rota relaxada é LIMPA: zero
  /// notice, então `hasTimeRestriction`, `restrictionLabel` e
  /// `destinationBlocked` voltam vazios — e `_announceRestriction` faz
  /// early-return em `!hasTimeRestriction`. Sem enxertar, o efeito líquido seria
  /// o PIOR dos mundos: a rota para ~200 m antes do pino e o motorista não é
  /// avisado do porquê. Ele encosta, não vê destino nenhum e conclui que o app
  /// errou — que é exatamente o que o rótulo da v2.4.43 foi feito pra impedir.
  ///
  /// O aviso vem da 1ª tentativa porque é ela que MEDIU o trecho proibido; a
  /// relaxada não chega a entrar nele, então não teria o que medir.
  ///
  /// Os `restrictionPoints` vão junto: são coordenadas do MUNDO (as ruas
  /// proibidas), não índices da polilinha — seguem válidos na rota nova e mantêm
  /// o "Ver no mapa" do banner funcionando (v2.4.40). Sem eles o toque no banner
  /// não faria nada.
  @visibleForTesting
  static RouteResult graftBlockedWarning({
    required RouteResult relaxed,
    required RouteResult blocked,
  }) =>
      relaxed.copyWith(
        hasTimeRestriction: true,
        restrictionLabel:   blocked.restrictionLabel,
        destinationBlocked: true,
        restrictionPoints:  blocked.restrictionPoints,
      );

  /// Rótulo do destino inalcançável, ou null quando a rota termina em via
  /// liberada (aí vale o rótulo de trecho de sempre).
  @visibleForTesting
  static String? destinationBlockedLabel(
      List<SpanViolation> spans, List<LatLng> points) {
    if (spans.isEmpty || points.length < 2 || !spans.last.violated) return null;
    // Anda pra trás enquanto o trecho seguir restrito: o começo do BLOCO FINAL é
    // onde a proibição começa. Usar o 1º span restrito da rota inteira mentiria
    // quando o mesmo notice também aparece solto lá atrás.
    var i = spans.length - 1;
    var blocksMode = spans[i].blocksMode;
    while (i > 0 && spans[i - 1].violated) {
      i--;
      if (spans[i].blocksMode) blocksMode = true;
    }
    // ponytail: só acesso proibido ganha texto próprio — é o caso medido em
    // campo. Restrição de dimensão no fim mantém o rótulo de dimensão, que já
    // diz o que o motorista precisa (altura/peso máx) sem eu inventar frase.
    if (!blocksMode) return null;
    final startIdx = spans[i].offset.clamp(0, points.length - 1);
    final m = RadarService.remainingAlongRoute(points, startIdx, double.infinity);
    if (m <= 0) return null;
    return 'Últimos ${_fmtMeters(m)} proibidos para caminhão';
  }

  // 225 m → "230 metros"; 1240 m → "1,2 quilômetros". Arredonda porque a
  // polyline não tem precisão de metro e "227" fingiria que tem.
  //
  // Unidade por EXTENSO porque este texto vai pro banner E pra voz: o app já
  // fala "Em 200 metros" (navigation_screen:1690) e abreviação em TTS é
  // loteria de engine ("m" vira "eme"). Um texto só evita ter que manter duas
  // versões da mesma frase em sincronia.
  static String _fmtMeters(double m) => m >= 1000
      ? '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} quilômetros'
      : '${(m / 10).round() * 10} metros';

  static bool _blocksTransportMode(Map<String, dynamic> n) =>
      ((n['details'] as List?)?.cast<Map<String, dynamic>>() ?? const [])
          .any((d) => d['type'] == 'violatedTransportMode');

  // Monta o texto do banner a partir do `details` do notice (o `title` da HERE
  // vem "Violated vehicle restriction." em inglês genérico — inútil). Dimensão
  // primeiro (concreto), horário como fallback. cm→m, kg→t. Null = texto genérico.
  static String? _restrictionLabel(List<Map<String, dynamic>> notices) {
    for (final n in notices) {
      final l = _labelForNotice(n);
      if (l != null) return l;
    }
    return null;
  }

  // Rótulo de UM notice (dimensão primeiro, horário/acesso como fallback).
  // Null quando não reconhece nada (chamador usa texto genérico).
  static String? _labelForNotice(Map<String, dynamic> n) {
    final details = (n['details'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    for (final d in details) {
      String m(num cm) => (cm / 100).toStringAsFixed(1).replaceAll('.', ',');
      final w = d['maxWeight'] as num?;
      if (w != null) {
        final t = w / 1000;
        final txt = t == t.roundToDouble()
            ? t.round().toString()
            : t.toStringAsFixed(1).replaceAll('.', ',');
        return 'Restrição: peso máx $txt t';
      }
      if (d['maxHeight'] != null) return 'Restrição: altura máx ${m(d['maxHeight'] as num)} m';
      if (d['maxLength'] != null) return 'Restrição: comprimento máx ${m(d['maxLength'] as num)} m';
      if (d['maxWidth']  != null) return 'Restrição: largura máx ${m(d['maxWidth'] as num)} m';
      if (d['type'] == 'violatedTransportMode') return 'Via proibida para caminhões';
      if (d['timeDependent'] == true) return 'Restrição por horário nesta via';
    }
    return null;
  }
}
