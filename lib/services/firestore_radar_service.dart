import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../utils/geo_bounds.dart';
import '../models/radar_point.dart';
import 'auth_service.dart';
import 'field_log.dart';
import 'radar_service.dart';

/// Verdicto do curador sobre um ponto: existe ou não, e a velocidade real
/// (0 = não informada → mantém a da CSV). Vale mais que o dado bruto.
class RadarOverride {
  final bool exists;
  final int speedKmh;

  /// O servidor apurou MAIORIA sobre isto (3+ votos, sem empate) e ela vale pra
  /// todos — inclusive pra quem votou o contrário. Decisão do Pedro (17/09):
  /// "se 90 pessoas concordam e 1 discorda, a que discorda aceita a da maioria".
  /// Só com estes ligados o remoto passa por cima do voto local; ver
  /// [mesclarOverrides].
  final bool mandaExists;
  final bool mandaKmh;

  const RadarOverride(this.exists, this.speedKmh,
      {this.mandaExists = false, this.mandaKmh = false});
}

/// Junta o que o servidor apurou com o voto DESTE aparelho. Puro/testável
/// porque é a regra que o motorista sente na cara: ou ele vê o próprio palpite,
/// ou vê o da maioria.
///
/// Sem maioria, o local manda — é o que faz a curadoria valer offline e o que
/// impede radar negado de ressuscitar quando a cota do Firestore estoura. Com
/// maioria, o remoto manda naquilo que foi decidido, campo por campo: dá pra ter
/// maioria sobre "existe" e empate sobre o limite ao mesmo tempo.
Map<String, RadarOverride> mesclarOverrides(
  Map<String, RadarOverride> remoto,
  Map<String, RadarOverride> local,
) {
  final out = Map<String, RadarOverride>.from(remoto);
  local.forEach((k, meu) {
    final deles = remoto[k];
    if (deles == null) {
      out[k] = meu;
      return;
    }
    out[k] = RadarOverride(
      deles.mandaExists ? deles.exists : meu.exists,
      deles.mandaKmh ? deles.speedKmh : meu.speedKmh,
      mandaExists: deles.mandaExists,
      mandaKmh: deles.mandaKmh,
    );
  });
  return out;
}

/// Chave determinística de localização (~1m). Mesma p/ Firestore e set local.
String dismissalKey(double lat, double lng) =>
    '${lat.toStringAsFixed(5)}_${lng.toStringAsFixed(5)}';

/// Aplica os overrides do curador a uma lista de radares (CSV+crowd). Puro/testável:
/// exists=false → some; exists=true & speedKmh>0 → troca a velocidade; sem override
/// → intacto. Casa por chave exata (as coords do radar são determinísticas).
List<RadarPoint> applyOverrides(
    List<RadarPoint> radars, Map<String, RadarOverride> overrides) {
  if (overrides.isEmpty) return radars;
  final out = <RadarPoint>[];
  for (final r in radars) {
    final o = overrides[dismissalKey(r.lat, r.lng)];
    if (o == null) {
      out.add(r);
    } else if (o.exists) {
      out.add(o.speedKmh > 0 ? r.copyWith(speedKmh: o.speedKmh) : r);
    }
    // o.exists == false → removido (não entra)
  }
  return out;
}

/// Camada crowd-source sobre o CSV estático de radar.
/// - `radars`: radares ADICIONADOS por usuários (mirror de `restrictions`).
/// - `radar_dismissals`: votos de "não existe" contra um ponto (CSV ou user),
///    agregados por chave de localização. Some quando passa o limiar.
class FirestoreRadarService {
  static final _db = FirebaseFirestore.instance;
  static const _radarsCol     = 'radars';
  static const _dismissalsCol = 'radar_dismissals';
  static const _overridesCol  = 'radar_overrides';
  static const _radarPassCol  = 'radar_pass';
  static const _localKey      = 'radar_overrides_local';
  static const _localRadarKey = 'radar_crowd_local';
  // Cache em memória do set local persistente (carrega uma vez).
  static Map<String, RadarOverride>? _localCache;
  static List<RadarPoint>? _localRadarCache;

  // ponytail: limiar de votos pra sumir global. 1 enquanto há ~1 usuário; subir
  // conforme a base cresce (3 vira razoável). Vale p/ reportedBy e p/ dismissals.
  static const _hideThreshold = 1;

  /// Junta o crowd do Firestore com os radares deste device, sem duplicar.
  /// Puro/testável: o remoto manda (traz id e votos), o local só ACRESCENTA o que
  /// não veio. Chave de local (~1m) é a mesma do resto do arquivo.
  static List<RadarPoint> mergeLocalCrowd(
      List<RadarPoint> remoto, List<RadarPoint> locais, List<LatLng> points) {
    if (locais.isEmpty) return remoto;
    final vistos = remoto.map((r) => dismissalKey(r.lat, r.lng)).toSet();
    final out = List.of(remoto);
    for (final r in locais) {
      // Proximidade ANTES do dedup: marcar como visto um radar que nem entrou
      // deixaria o set mentindo pro resto do laço.
      if (!RadarService.isNearRoute(r.lat, r.lng, points)) continue;
      if (vistos.add(dismissalKey(r.lat, r.lng))) out.add(r);
    }
    return out;
  }

  /// Radares crowd (adicionados) perto da rota, já filtrando os derrubados por voto.
  /// Sempre uni os DESTE device (local-first): a cota diária de leitura do Spark
  /// estoura e o Firestore devolve vazio — e radar que some é alerta que NÃO TOCA,
  /// que é multa. Proteger o override (falso alarme) e deixar o radar adicionado
  /// desprotegido era blindar o lado barato e deixar passar o caro.
  static Future<List<RadarPoint>> fetchNearRoute(List<LatLng> points) async {
    if (points.isEmpty) return [];
    final locais = await _loadLocalRadars();
    final (:minLat, :maxLat, :minLng, :maxLng) = boundsOf(points);
    const pad = 0.05; // ~5 km
    try {
      final snap = await _db
          .collection(_radarsCol)
          .where('lat', isGreaterThanOrEqualTo: minLat - pad)
          .where('lat', isLessThanOrEqualTo: maxLat + pad)
          .get();
      final remoto = snap.docs
          .where((d) {
            final m = d.data();
            final lng = (m['lng'] as num).toDouble();
            final reported = (m['reportedBy'] as num?)?.toInt() ?? 0;
            return lng >= minLng - pad &&
                lng <= maxLng + pad &&
                reported < _hideThreshold &&
                RadarService.isNearRoute((m['lat'] as num).toDouble(), lng, points);
          })
          .map((d) {
            final m = d.data();
            return RadarPoint(
              lat: (m['lat'] as num).toDouble(),
              lng: (m['lng'] as num).toDouble(),
              type: m['type'] as String? ?? 'Radar',
              speedKmh: (m['speedKmh'] as num?)?.toInt() ?? 0,
              id: d.id,
              source: 'user',
            );
          })
          .toList();
      return mergeLocalCrowd(remoto, locais, points);
    } catch (e, st) {
      FieldLog.error('radar_fetch', e, st);
      // NÃO é [] : é exatamente aqui que a cota estourada apagava o radar que o
      // motorista marcou com a própria mão.
      return mergeLocalCrowd(const [], locais, points);
    }
  }

  /// Localizações com votos de dispensa acima do limiar (pra suprimir radar do CSV).
  static Future<List<LatLng>> fetchDismissals(List<LatLng> points) async {
    if (points.isEmpty) return [];
    final (:minLat, :maxLat, :minLng, :maxLng) = boundsOf(points);
    const pad = 0.05;
    try {
      final snap = await _db
          .collection(_dismissalsCol)
          .where('lat', isGreaterThanOrEqualTo: minLat - pad)
          .where('lat', isLessThanOrEqualTo: maxLat + pad)
          .get();
      return snap.docs
          .where((d) {
            final m = d.data();
            final lng = (m['lng'] as num).toDouble();
            final count = (m['count'] as num?)?.toInt() ?? 0;
            return lng >= minLng - pad && lng <= maxLng + pad && count >= _hideThreshold;
          })
          .map((d) {
            final m = d.data();
            return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
          })
          .toList();
    } catch (e, st) {
      FieldLog.error('radar_dismissals_fetch', e, st);
      return [];
    }
  }

  /// Junta CSV (perto da rota) + crowd, aplicando os verdictos do curador
  /// (override: some / troca velocidade) e as dispensas antigas por voto.
  /// O override LOCAL é autoritativo (offline, imediato, sobrevive reroute) — é
  /// o que impede o radar dispensado de ressuscitar do _cache estático. A leitura
  /// do Firestore é fail-open: se falhar, cai só no local (não esconde radar real
  /// por erro de rede).
  static Future<List<RadarPoint>> mergeCrowd(
      List<RadarPoint> csvNearRoute, List<LatLng> points) async {
    // As três leituras são independentes entre si. Em série custavam 3 round-trips
    // de Firestore empilhados dentro do recálculo de rota; em paralelo custam só o
    // mais lento. Cada uma é fail-open por dentro (erro → vazio), então o .wait
    // não tem como estourar.
    final (crowd, dismissals, overrides) = await (
      fetchNearRoute(points),
      fetchDismissals(points),
      loadOverrides(points),
    ).wait;
    // Dispensas antigas (voto por local) → tratadas como override exists=false,
    // sem sobrescrever um override novo mais específico.
    for (final d in dismissals) {
      overrides.putIfAbsent(
          dismissalKey(d.latitude, d.longitude), () => const RadarOverride(false, 0));
    }
    return applyOverrides([...csvNearRoute, ...crowd], overrides);
  }

  // ── Overrides do curador (fato: existe/não + velocidade real) ────────────────

  static Future<Map<String, RadarOverride>> _loadLocal() async {
    if (_localCache != null) return _localCache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localKey);
    final m = <String, RadarOverride>{};
    if (raw != null) {
      try {
        (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
          final o = v as Map<String, dynamic>;
          m[k] = RadarOverride(o['exists'] as bool? ?? true,
              (o['speed'] as num?)?.toInt() ?? 0);
        });
      } catch (_) {/* JSON corrompido → começa limpo */}
    }
    _localCache = m;
    return m;
  }

  static Future<void> _persistLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _localKey,
        jsonEncode((_localCache ?? {}).map(
            (k, o) => MapEntry(k, {'exists': o.exists, 'speed': o.speedKmh}))));
  }

  /// Chaves de local com verdicto local (pra nav não re-perguntar radar já curado).
  static Future<Set<String>> localOverrideKeys() async =>
      (await _loadLocal()).keys.toSet();

  /// Só os verdictos DESTE device — sem rede (cache em memória após o 1º load).
  /// A nav usa isto pra aplicar os radares do CSV assim que a rota nova chega, sem
  /// esperar o Firestore: senão um radar que o curador NEGOU ressuscitaria na tela
  /// durante a janela do enrichment (a ressurreição que o v2.4.26 matou).
  static Future<Map<String, RadarOverride>> loadLocalOverrides() async =>
      Map.of(await _loadLocal());

  /// Overrides válidos = Firestore (global) ⊕ local (deste device, vence).
  static Future<Map<String, RadarOverride>> loadOverrides(
      List<LatLng> points) async {
    final fs    = await fetchOverrides(points);
    final local = await _loadLocal();
    return mesclarOverrides(fs, local);
  }

  /// Veredito do curador: UM voto deste motorista sobre este radar.
  ///
  /// Grava LOCAL na hora (autoritativo enquanto não há maioria, funciona offline
  /// e imediato) e manda o voto pro BACKEND, que conta e publica o resultado.
  ///
  /// Por que não escreve mais direto no Firestore: era um `set()` num doc por
  /// radar, então o último a votar apagava os outros — Beto dizendo 80 e
  /// Fernando 90 nunca convergiam, e ninguém ficava sabendo que houve
  /// discordância. E contagem feita no celular não resiste a má-fé, que é
  /// justamente o que a maioria deve barrar (decisão do Pedro, 17/09/2026).
  ///
  /// Falha de rede não perde o veredito: o local já está gravado e o motorista
  /// segue vendo o dele. O voto é que não entra na contagem — ele revota quando
  /// passar de novo. [speedKmh] 0 = só confirma existência.
  static Future<void> setOverride({
    required double lat,
    required double lng,
    required bool exists,
    int speedKmh = 0,
    required String uid,
  }) async {
    final rid = dismissalKey(lat, lng);
    final local = await _loadLocal();
    local[rid] = RadarOverride(exists, speedKmh);
    await _persistLocal();
    try {
      final resp = await http
          .post(
            Uri.parse('$backendUrl/radar/voto'),
            headers: {
              'Content-Type': 'application/json',
              ...await AuthService.getHeaders(),
            },
            // `rid` vai pronto: recalcular a chave no servidor abriria a chance
            // de a 5ª casa arredondar diferente e o voto não casar com o radar.
            body: jsonEncode({
              'rid': rid, 'lat': lat, 'lng': lng,
              'exists': exists, 'kmh': speedKmh,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode >= 300) {
        FieldLog.event('voto_falhou', {'http': resp.statusCode, 'rid': rid});
      }
    } catch (e, st) {
      FieldLog.error('radar_override', e, st);
    }
  }

  /// Overrides do Firestore perto da rota. Fail-open ({}) em erro de rede.
  static Future<Map<String, RadarOverride>> fetchOverrides(
      List<LatLng> points) async {
    if (points.isEmpty) return {};
    final (:minLat, :maxLat, :minLng, :maxLng) = boundsOf(points);
    const pad = 0.05;
    try {
      final snap = await _db
          .collection(_overridesCol)
          .where('lat', isGreaterThanOrEqualTo: minLat - pad)
          .where('lat', isLessThanOrEqualTo: maxLat + pad)
          .get();
      final m = <String, RadarOverride>{};
      for (final d in snap.docs) {
        final data = d.data();
        final lng = (data['lng'] as num).toDouble();
        if (lng < minLng - pad || lng > maxLng + pad) continue;
        m[d.id] = RadarOverride(
          data['exists'] as bool? ?? true,
          (data['speedKmh'] as num?)?.toInt() ?? 0,
          // Docs gravados ANTES da apuração no servidor não têm estes campos.
          // Default false = tratados como voto comum, sem força pra sobrepor o
          // local — que é o comportamento que sempre existiu.
          mandaExists: data['mandaExists'] as bool? ?? false,
          mandaKmh: data['mandaKmh'] as bool? ?? false,
        );
      }
      return m;
    } catch (e, st) {
      FieldLog.error('radar_overrides_fetch', e, st);
      return {};
    }
  }

  // ── Radares adicionados por ESTE device (local-first, igual ao override) ─────

  static Future<List<RadarPoint>> _loadLocalRadars() async {
    if (_localRadarCache != null) return _localRadarCache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localRadarKey);
    final out = <RadarPoint>[];
    if (raw != null) {
      try {
        for (final e in jsonDecode(raw) as List) {
          final m = e as Map<String, dynamic>;
          out.add(RadarPoint(
            lat: (m['lat'] as num).toDouble(),
            lng: (m['lng'] as num).toDouble(),
            type: m['type'] as String? ?? 'Radar',
            speedKmh: (m['speedKmh'] as num?)?.toInt() ?? 0,
            id: m['id'] as String?,
            source: 'user',
          ));
        }
      } catch (_) {/* JSON corrompido → começa limpo, igual _loadLocal */}
    }
    _localRadarCache = out;
    return out;
  }

  /// Grava o radar marcado neste device. Sobrescreve pela chave de local, então
  /// chamar de novo com o `id` do Firestore só completa o registro.
  /// Chamado ANTES de tentar o Firestore: se o write remoto falhar (sem auth,
  /// offline, cota), o radar tem que continuar existindo pro dono dele.
  static Future<void> addLocal(RadarPoint r) async {
    final atuais = await _loadLocalRadars();
    final key = dismissalKey(r.lat, r.lng);
    atuais.removeWhere((x) => dismissalKey(x.lat, x.lng) == key);
    atuais.add(r);
    _localRadarCache = atuais;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _localRadarKey,
        jsonEncode(atuais
            .map((x) => {
                  'lat': x.lat,
                  'lng': x.lng,
                  'type': x.type,
                  'speedKmh': x.speedKmh,
                  if (x.id != null) 'id': x.id,
                })
            .toList()));
  }

  static Future<String?> add({
    required double lat,
    required double lng,
    required String type,
    required int speedKmh,
    required String uid,
  }) async {
    try {
      final doc = await _db.collection(_radarsCol).add({
        'lat': lat,
        'lng': lng,
        'type': type,
        'speedKmh': speedKmh,
        'createdAt': FieldValue.serverTimestamp(),
        'createdByUid': uid,
        'confirmedBy': 0,
        'reportedBy': 0,
        'source': 'user',
      });
      return doc.id;
    } catch (e, st) {
      FieldLog.error('radar_add', e, st);
      return null;
    }
  }

  /// "Existe sim" num radar crowd → sobe a confiança.
  static Future<void> confirm(String docId) async {
    try {
      await _db.collection(_radarsCol).doc(docId).update(
          {'confirmedBy': FieldValue.increment(1)});
    } catch (e, st) {
      FieldLog.error('radar_confirm', e, st);
    }
  }

  /// "Não existe" num radar crowd → voto de remoção.
  static Future<void> report(String docId) async {
    try {
      await _db.collection(_radarsCol).doc(docId).update(
          {'reportedBy': FieldValue.increment(1)});
    } catch (e, st) {
      FieldLog.error('radar_report', e, st);
    }
  }

  /// Coleta passiva de passagens por radar (radar_pass). Grava o batch já pronto
  /// vindo do RadarPassLogger — cada item é {rid, h, v, ts}. Best-effort ABSOLUTO:
  /// erro de write JAMAIS pode afetar a navegação, então engole com log. Só cria
  /// (a regra do Firestore proíbe read/update/delete nesta coleção).
  static Future<void> logRadarPasses(List<Map<String, dynamic>> batch) async {
    if (batch.isEmpty) return;
    try {
      final wb = _db.batch();
      for (final e in batch) {
        wb.set(_db.collection(_radarPassCol).doc(), e);
      }
      await wb.commit();
    } catch (e, st) {
      FieldLog.error('radar_pass', e, st);
    }
  }

  /// "Não existe" num radar do CSV → agrega voto por localização (doc determinístico).
  static Future<void> dismissCsv(double lat, double lng) async {
    try {
      final key = '${lat.toStringAsFixed(5)}_${lng.toStringAsFixed(5)}';
      await _db.collection(_dismissalsCol).doc(key).set({
        'lat': lat,
        'lng': lng,
        'count': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (e, st) {
      FieldLog.error('radar_dismiss', e, st);
    }
  }

}
