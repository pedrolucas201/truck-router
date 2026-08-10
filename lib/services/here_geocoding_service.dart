import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config.dart';
import 'auth_service.dart';
import 'field_log.dart';

class GeocodingSuggestion {
  final String title;
  final String? hereId;    // autocomplete: lookup para coordenadas precisas
  final LatLng? position;  // geocode/nominatim: coords já resolvidas

  const GeocodingSuggestion._({required this.title, this.hereId, this.position});

  factory GeocodingSuggestion.address({required String title, required String id}) =>
      GeocodingSuggestion._(title: title, hereId: id);

  factory GeocodingSuggestion.place({required String title, required LatLng pos}) =>
      GeocodingSuggestion._(title: title, position: pos);

  bool get needsLookup => position == null;
}

class HereGeocodingService {
  /// Busca endereços e lugares nomeados.
  /// Detecta CEP (XXXXX-XXX) e usa rota específica de código postal.
  /// Caso contrário, tenta HERE (autocomplete + geocode) e cai no Nominatim se vazio.
  static Future<List<GeocodingSuggestion>> search(
      String query, {LatLng? bias}) async {
    if (query.trim().isEmpty) return [];
    if (_isCep(query)) return _cepSearch(query);

    // Endereço de rodovia por km (ex: "Fernão Dias km 936"). A HERE lê o "936"
    // como número de casa: medido contra os radares do PNCV, ela erra 4 km na
    // mediana — 158 km quando o motorista não cita o município. Duas fontes, e
    // ambas disparam JUNTO com a HERE (em série atrasavam cada tecla digitada):
    //  1. /geocode/marco — marcos do SNV/DNIT no backend, mediana ~400 m;
    //  2. a Google, que só acerta onde indexou o marco (~22%, concedidas de SP —
    //     justamente o que o SNV não tem, por serem estaduais).
    final isKm     = _isRodoviaKm(query);
    final marcoKm  = isKm ? _safe('marco_km', () => _marcoKm(query, bias)) : null;
    final googleKm = isKm ? _googleGeocode(query) : null;

    // Endereço com número de casa: o OSM entra como fonte extra — ver houseNumberOf.
    // Dispara JUNTO com as da HERE (mesmo lote, sem await aqui) e não numa segunda
    // rodada: resultado que chega atrasado mexe a lista embaixo do dedo do motorista
    // e ele toca no item errado.
    // ponytail: o Nominatim pede no máximo 1 req/s. Com o debounce do campo e UM
    // motorista isso não chega perto; se escalar de usuário, trocar pelo `qq=`
    // estruturado da HERE, que já foi medido e resolve o mesmo caso.
    final houseNum = houseNumberOf(query);
    final osmNum   = houseNum == null
        ? null
        : _safe('nominatim_num', () => _nominatimSearch(query, bias: bias));

    // _safe isola cada fonte: sem isto, um jsonDecode que lança (backend devolveu
    // HTML/erro em vez de JSON) mata a busca INTEIRA via Future.wait, sem sinal.
    final hereResults = await Future.wait([
      _safe('autocomplete', () => _autocomplete(query, bias: bias)),
      _safe('geocode',      () => _geocodePlaces(query, bias: bias)),
      _safe('discover',     () => _discoverPlaces(query, bias: bias)),
    ]);

    final merged   = <GeocodingSuggestion>[];
    final seenKeys = <String>{};
    for (final list in hereResults) {
      for (final s in list) {
        if (seenKeys.add(s.title.toLowerCase().trim())) merged.add(s);
      }
    }

    // Já estão rodando desde antes do Future.wait; aqui só se colhe o resultado.
    // Só vira sugestão se achou o MARCO — ver [acceptsKmResult].
    final g = await googleKm;
    if (g != null && seenKeys.add(g.title.toLowerCase().trim())) {
      merged.insert(0, g);
    }
    // O marco entra por último pra ficar em PRIMEIRO: dado oficial contra palpite
    // de endereço. Pode vir mais de um — a quilometragem reinicia a cada estado e
    // o motorista não digita a UF, então o backend devolve os dois mais prováveis
    // rotulados com o estado e quem escolhe é ele. Reversed preserva a ordem.
    for (final s in (await marcoKm ?? const <GeocodingSuggestion>[]).reversed) {
      if (seenKeys.add(s.title.toLowerCase().trim())) merged.insert(0, s);
    }

    // Pediu número e nenhuma sugestão da HERE trouxe ESSE número → o resultado do
    // OSM que trouxer entra em primeiro: é o mais específico e é o que ele quer.
    // Só ADICIONA, nunca substitui: a cobertura do OSM no Brasil é irregular (acerta
    // o centro de São Paulo, falha em cidade pequena — justo onde a HERE acerta,
    // como no Tupã deste mesmo caso). As duas fontes se completam.
    if (houseNum != null &&
        !merged.any((s) => labelHasHouseNumber(s.title, houseNum))) {
      for (final s in (await osmNum!).reversed) {
        if (labelHasHouseNumber(s.title, houseNum) &&
            seenKeys.add(s.title.toLowerCase().trim())) {
          merged.insert(0, s);
        }
      }
    }

    // Fallback: Nominatim (OpenStreetMap) quando HERE não encontra nada.
    // Chamado só neste caso para respeitar o limite de 1 req/s do serviço gratuito.
    if (merged.isEmpty) {
      final nominatim = await _safe('nominatim', () => _nominatimSearch(query, bias: bias));
      for (final s in nominatim) {
        if (seenKeys.add(s.title.toLowerCase().trim())) merged.add(s);
      }
    }

    return merged.take(5).toList();
  }

  /// Roda uma fonte de geocoding e devolve [] em falha, logando qual quebrou.
  /// Sem isto uma fonte que lança derruba o Future.wait inteiro.
  static Future<List<GeocodingSuggestion>> _safe(
      String src, Future<List<GeocodingSuggestion>> Function() fn) async {
    try {
      return await fn();
    } catch (e, st) {
      FieldLog.error('geocode_$src', e, st);
      return [];
    }
  }

  // Rodovia por km: "km 936", "km936", "KM 936+700". A HERE erra esse formato.
  static final _kmRe = RegExp(r'\bkm\s*(\d+)', caseSensitive: false);
  static bool _isRodoviaKm(String q) => _kmRe.hasMatch(q);

  // ── Número de casa ───────────────────────────────────────────────────────────
  // Reportado pelo Gilberto em 2026-08-10: "rua guaianases, 1448" devolve o 1448
  // de TUPÃ (600 km longe) e São Paulo só aparece como rua, sem número. Medido na
  // chave real: a HERE TEM o ponto exato de SP, mas os números estão cadastrados
  // sob outro nome da mesma rua ("Rua dos Guaianazes", com Z), então o texto livre
  // nunca chega neles — nem com a cidade digitada junto, nem com `at` na posição
  // dele. Só a busca estruturada com `city` explícita acha, e o motorista não
  // digita a cidade. O OSM acerta esse caso sem cidade nenhuma.
  // Consequência medida: a sugestão de rua que sobrava fica a 975 m do número.

  /// Número de casa da busca, ou null.
  ///
  /// Reconhece as duas formas que o motorista escreve: depois de vírgula
  /// ("Rua X, 1448") ou fechando a busca ("Av Paulista 1000"). "Rua 25 de Março"
  /// não casa em nenhuma das duas — é o que separa nome de rua com número de
  /// número de casa de verdade.
  static final _houseNumRe = RegExp(r',\s*(\d{1,6})(?![\d-])|(\d{1,6})\s*$');
  @visibleForTesting
  static String? houseNumberOf(String q) {
    final s = q.trim();
    if (_isCep(s) || _isRodoviaKm(s)) return null; // ambos já têm dono
    final ms = _houseNumRe.allMatches(s).toList();
    if (ms.isEmpty) return null;
    return ms.last.group(1) ?? ms.last.group(2);
  }

  /// A sugestão já traz esse número de casa?
  ///
  /// Compara no formato de rótulo das duas fontes ("Rua X, 1448, Bairro, ...").
  /// O `(?![\d-])` evita casar 1448 dentro de "14480" ou de um CEP.
  /// NUNCA comparar nome de rua: em São Paulo o número mora sob "Rua dos
  /// Guaianazes" e a busca é "Rua Guaianases" — um guard por nome reprovaria
  /// exatamente o caso que isto conserta.
  @visibleForTesting
  static bool labelHasHouseNumber(String label, String num) =>
      RegExp(',\\s*$num(?![\\d-])').hasMatch(label);

  /// Marco quilométrico das federais, resolvido no backend a partir do SNV/DNIT.
  ///
  /// O parse do texto (número da BR, apelidos como "Fernão Dias", sufixo "+700")
  /// e o desempate entre estados moram lá de propósito: assim apelido novo e
  /// versão nova do SNV entram sem release, e os 3,5 MB do dado ficam fora do APK.
  static Future<List<GeocodingSuggestion>> _marcoKm(String query, LatLng? bias) async {
    final resp = await http.get(
        Uri.parse('$backendUrl/geocode/marco').replace(queryParameters: {
          'q': query,
          if (bias != null) 'at': '${bias.latitude},${bias.longitude}',
        }),
        headers: await AuthService.getHeaders());
    if (resp.statusCode != 200) return [];
    final items = jsonDecode(resp.body)['items'] as List<dynamic>? ?? [];
    return [
      for (final i in items.cast<Map<String, dynamic>>())
        if (i['lat'] is num && i['lng'] is num)
          GeocodingSuggestion.place(
            title: i['title'] as String? ?? query,
            pos: LatLng((i['lat'] as num).toDouble(), (i['lng'] as num).toDouble()),
          )
    ];
  }

  /// A Google só serve aqui quando achou o MARCO, não a rodovia.
  ///
  /// Medido em 18 consultas reais (2026-07-31): 10 de 12 rodovias devolvem
  /// `GEOMETRIC_CENTER`, que é o centro do trecho da via — "BR-116 km 210,
  /// Jacareí" cai em -18.67/-41.98, **Minas Gerais, ~600 km fora**. O guard
  /// antigo só barrava `APPROXIMATE`, então esse ponto iria pro topo da lista.
  ///
  /// E `ROOFTOP` sozinho também não basta: "Imigrantes km 28" veio ROOFTOP
  /// apontando pra "Av. Sapopemba, 25720a" — casou com outro endereço. Por isso
  /// o segundo teste: o endereço devolvido tem que citar o mesmo km pedido.
  static bool acceptsKmResult(String query, String locationType, String formatted) {
    if (locationType != 'ROOFTOP') return false;
    final want = _kmRe.firstMatch(query)?.group(1);
    return want != null && want == _kmRe.firstMatch(formatted)?.group(1);
  }

  // Google Geocoding para endereço de rodovia por km.
  //
  // ponytail: esta chamada NUNCA funcionou. A `googleMapsApiKey` é a chave
  // "Android SDK", restrita ao pacote — e o Geocoding é web service, que só
  // autoriza via X-Android-Package/X-Android-Cert, headers que apenas o SDK
  // nativo assina. O `http` do Dart não manda nenhum dos dois: 403 em 100% das
  // chamadas entre 07/07 e 31/07 (172 requests, zero 200 — métricas do
  // maps-route-495614), sempre em silêncio. Teto conhecido: só volta a viver
  // quando passar pelo proxy do backend com chave sem restrição de app, igual
  // HERE/TomTom. Até lá o `geocode_google_km` abaixo é o que prova o estado.
  static Future<GeocodingSuggestion?> _googleGeocode(String query) async {
    try {
      final resp = await http.get(Uri.https(
        'maps.googleapis.com', '/maps/api/geocode/json',
        {'address': query, 'components': 'country:BR', 'language': 'pt-BR', 'key': googleMapsApiKey},
      ));
      if (resp.statusCode != 200) {
        FieldLog.event('geocode_google_km', {'http': resp.statusCode});
        return null;
      }
      final body   = jsonDecode(resp.body) as Map<String, dynamic>;
      final status = body['status'] as String? ?? '';
      if (status != 'OK') {
        FieldLog.event('geocode_google_km', {'status': status});
        return null;
      }
      final results = (body['results'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      if (results.isEmpty) return null;
      final first     = results.first;
      final geom      = first['geometry'] as Map<String, dynamic>?;
      final locType   = geom?['location_type'] as String? ?? '';
      final loc       = geom?['location'] as Map<String, dynamic>?;
      final formatted = first['formatted_address'] as String? ?? '';
      final ok        = loc != null && acceptsKmResult(query, locType, formatted);
      // Enquanto o transporte estiver quebrado este ramo é inalcançável (só sai
      // o `status` acima). Depois do proxy, é ele que mede em campo a cobertura
      // real da Google — na amostra de 18 consultas de 31/07 foram 4 aceitas.
      FieldLog.event('geocode_google_km', {'lt': locType, 'ok': ok});
      if (!ok) return null;
      return GeocodingSuggestion.place(
        title: formatted.isEmpty ? query : formatted,
        pos:   LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble()),
      );
    } catch (e, st) {
      FieldLog.error('geocode_google_km', e, st);
      return null;
    }
  }

  // Autocomplete HERE: endereços com ID único (sem ambiguidade de coords).
  static Future<List<GeocodingSuggestion>> _autocomplete(
      String query, {LatLng? bias}) async {
    final params = <String, String>{
      'q':      query,
      'lang':   'pt-BR',
      'limit':  '4',
      'in':     'countryCode:BRA',
      if (bias != null) 'at': '${bias.latitude},${bias.longitude}',
    };
    final response = await http.get(
        Uri.parse('$backendUrl/here/autocomplete').replace(queryParameters: params),
        headers: await AuthService.getHeaders());
    if (response.statusCode != 200) return [];

    final items = jsonDecode(response.body)['items'] as List<dynamic>? ?? [];
    return items
        .cast<Map<String, dynamic>>()
        .where((i) => i['id'] != null)
        .map((i) => GeocodingSuggestion.address(
              title: i['address']?['label'] as String? ?? i['title'] as String,
              id:    i['id'] as String,
            ))
        .toList();
  }

  // Geocode HERE: lugares nomeados (empresas, instituições) com coords diretas.
  static Future<List<GeocodingSuggestion>> _geocodePlaces(
      String query, {LatLng? bias}) async {
    final params = <String, String>{
      'q':      query,
      'lang':   'pt-BR',
      'limit':  '3',
      'in':     'countryCode:BRA',
      if (bias != null) 'at': '${bias.latitude},${bias.longitude}',
    };
    final response = await http.get(
        Uri.parse('$backendUrl/here/geocode').replace(queryParameters: params),
        headers: await AuthService.getHeaders());
    if (response.statusCode != 200) return [];

    final items = jsonDecode(response.body)['items'] as List<dynamic>? ?? [];
    return items
        .cast<Map<String, dynamic>>()
        .where((i) => i['position'] != null)
        .map((i) {
          final pos = i['position'] as Map<String, dynamic>;
          return GeocodingSuggestion.place(
            title: i['address']?['label'] as String? ?? i['title'] as String,
            pos:   LatLng(
              (pos['lat'] as num).toDouble(),
              (pos['lng'] as num).toDouble(),
            ),
          );
        })
        .toList();
  }

  // Discover HERE: busca livre por nome de empresa, POI e endereço.
  // Endpoint específico para texto livre — cobre o que /geocode não encontra por nome.
  static Future<List<GeocodingSuggestion>> _discoverPlaces(
      String query, {LatLng? bias}) async {
    // /v1/discover exige 'at'; sem bias usa Brasília como âncora neutra para o Brasil.
    final at = bias != null
        ? '${bias.latitude},${bias.longitude}'
        : '-15.7801,-47.9292';
    final params = <String, String>{
      'q':      query,
      'lang':   'pt-BR',
      'limit':  '5',
      'in':     'countryCode:BRA',
      'at':     at,
    };
    final response = await http.get(
        Uri.parse('$backendUrl/here/discover').replace(queryParameters: params),
        headers: await AuthService.getHeaders());
    if (response.statusCode != 200) return [];

    final items = jsonDecode(response.body)['items'] as List<dynamic>? ?? [];
    return items
        .cast<Map<String, dynamic>>()
        .where((i) => i['position'] != null)
        .map((i) {
          final pos = i['position'] as Map<String, dynamic>;
          return GeocodingSuggestion.place(
            title: i['address']?['label'] as String? ?? i['title'] as String,
            pos: LatLng(
              (pos['lat'] as num).toDouble(),
              (pos['lng'] as num).toDouble(),
            ),
          );
        })
        .toList();
  }

  // Nominatim (OpenStreetMap): fallback gratuito com boa cobertura de POIs no Brasil.
  static Future<List<GeocodingSuggestion>> _nominatimSearch(
      String query, {LatLng? bias}) async {
    final params = <String, String>{
      'q':              query,
      'format':         'jsonv2',
      'countrycodes':   'br',
      'limit':          '5',
      'accept-language':'pt-BR',
      'addressdetails': '1',
      if (bias != null) 'viewbox':
          '${bias.longitude - 1},${bias.latitude + 1},'
          '${bias.longitude + 1},${bias.latitude - 1}',
      if (bias != null) 'bounded': '0',
    };
    // Timeout curto porque isto está no caminho de DIGITAÇÃO: a busca inteira
    // espera por ele antes de mostrar a lista, e o http.get do Dart não tem
    // timeout padrão nenhum. Serviço gratuito e sem SLA não pode segurar a tela
    // do motorista. Estourando, o _safe devolve [] e sobra o resultado da HERE,
    // que é o comportamento de antes desta fonte existir.
    final response = await http
        .get(
          Uri.https('nominatim.openstreetmap.org', '/search', params),
          headers: {'User-Agent': 'TruckRouterApp/1.0 (devgomesss@gmail.com)'},
        )
        .timeout(const Duration(seconds: 3));
    if (response.statusCode != 200) return [];

    final items = jsonDecode(response.body) as List<dynamic>;
    return items.cast<Map<String, dynamic>>().map((item) {
      final address = item['address'] as Map<String, dynamic>?;
      final name    = (item['name'] as String?)?.trim() ?? '';
      final city    = (address?['city']
              ?? address?['town']
              ?? address?['municipality']
              ?? address?['county']
              ?? '') as String;
      final state   = (address?['state'] ?? '') as String;

      // Endereço com número: rotular igual a HERE ("Rua X, 1448, Bairro, Cidade - UF").
      // Sem isto o resultado de casa cai no fallback do display_name e sai como
      // "1448, Rua Guaianases, Campos Elísios" — começa pelo número e perde a
      // cidade, que é justamente o que o motorista usa pra saber se é a rua certa.
      final houseNum = address?['house_number'] as String?;
      final road     = address?['road'] as String?;
      final district = (address?['suburb'] ?? address?['city_district']) as String?;
      // ISO3166-2-lvl4 vem como "BR-SP"; o campo `state` traz "São Paulo" por extenso.
      final uf = (address?['ISO3166-2-lvl4'] as String?)?.split('-').last ?? state;

      final String title;
      if (houseNum != null && road != null) {
        title = [
          '$road, $houseNum',
          if (district != null && district.isNotEmpty) district,
          if (city.isNotEmpty) uf.isNotEmpty ? '$city - $uf' : city,
        ].join(', ');
      } else if (name.isNotEmpty && city.isNotEmpty) {
        title = state.isNotEmpty ? '$name, $city - $state' : '$name, $city';
      } else {
        // fallback: primeiros segmentos do display_name
        final parts = (item['display_name'] as String).split(',');
        title = parts.take(3).map((s) => s.trim()).join(', ');
      }

      return GeocodingSuggestion.place(
        title: title,
        pos:   LatLng(
          double.parse(item['lat'] as String),
          double.parse(item['lon'] as String),
        ),
      );
    }).toList();
  }

  // ── CEP ──────────────────────────────────────────────────────────────────────

  static bool _isCep(String query) =>
      RegExp(r'^\d{5}-?\d{3}$').hasMatch(query.trim());

  static Future<List<GeocodingSuggestion>> _cepSearch(String raw) async {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 8) return [];
    final cep = '${digits.substring(0, 5)}-${digits.substring(5)}';

    // Passo 1: ViaCEP — resolve o CEP em componentes de endereço.
    try {
      final via = await http
          .get(Uri.parse('https://viacep.com.br/ws/$digits/json/'))
          .timeout(const Duration(seconds: 8));

      if (via.statusCode == 200) {
        final d = jsonDecode(via.body) as Map<String, dynamic>;
        if (d['erro'] != true) {
          final logradouro = (d['logradouro'] as String? ?? '').trim();
          final bairro     = (d['bairro']     as String? ?? '').trim();
          final cidade     = (d['localidade'] as String? ?? '').trim();
          final uf         = (d['uf']         as String? ?? '').trim();

          final labelParts = [logradouro, bairro, cidade, uf].where((s) => s.isNotEmpty).toList();
          final label = labelParts.isNotEmpty ? labelParts.join(', ') : cep;

          // Passo 2: HERE qq estruturado com street+city+state.
          // Suportado: city, country, county, district, houseNumber, postalCode, state, street.
          // Valida cidade E rua no resultado — evita "Rua Riachuelo de SP" quando o CEP é de PE.
          if (logradouro.isNotEmpty && cidade.isNotEmpty) {
            final qqParts = [
              'street=$logradouro',
              if (bairro.isNotEmpty) 'district=$bairro',
              'city=$cidade',
              if (uf.isNotEmpty) 'state=$uf',
              'country=Brazil',
            ];
            try {
              final resp = await http.get(Uri.parse('$backendUrl/here/geocode').replace(
                queryParameters: {'qq': qqParts.join(';'), 'in': 'countryCode:BRA', 'lang': 'pt-BR', 'limit': '5'},
              ), headers: await AuthService.getHeaders());
              if (resp.statusCode == 200) {
                final cidadeN = _norm(cidade);
                final ruaN    = _norm(logradouro);
                final allItems = (jsonDecode(resp.body)['items'] as List<dynamic>? ?? [])
                    .cast<Map<String, dynamic>>();
                for (final item in allItems) {
                  if (item['position'] == null) continue;
                  if ((item['scoring']?['queryScore'] as num? ?? 0) < 0.6) continue;
                  final addr         = item['address'] as Map<String, dynamic>? ?? {};
                  final retCity      = _norm(addr['city'] as String? ?? addr['county'] as String? ?? '');
                  final retStreet    = _norm(addr['street'] as String? ?? '');
                  final cityOk       = retCity.contains(cidadeN) || cidadeN.contains(retCity);
                  final streetOk     = retStreet.isNotEmpty &&
                      ruaN.split(' ').where((w) => w.length > 3).any((w) => retStreet.contains(w));
                  if (cityOk && streetOk) {
                    final pos = item['position'] as Map<String, dynamic>;
                    return [GeocodingSuggestion.place(
                      title: label,
                      pos: LatLng((pos['lat'] as num).toDouble(), (pos['lng'] as num).toDouble()),
                    )];
                  }
                }
              }
            } catch (_) {}
          }

          // Passo 3: Google Geocoding — melhor cobertura de ruas no Brasil, incluindo cidades do interior.
          // Valida location_type != APPROXIMATE (approx = só achou cidade/região, não a rua).
          // ATENÇÃO: mesma chave restrita ao app do _googleGeocode, então este passo
          // também vem tomando 403 desde sempre. Aqui o guard de APPROXIMATE está
          // certo (é endereço de RUA — GEOMETRIC_CENTER é o centro da rua, legítimo);
          // o que faltava era o log. Passo 4 (TomTom) é quem vinha salvando o CEP.
          if (logradouro.isNotEmpty && cidade.isNotEmpty) {
            try {
              final address = [logradouro, if (bairro.isNotEmpty) bairro, cidade, uf, 'Brasil']
                  .join(', ');
              final resp = await http.get(Uri.https(
                'maps.googleapis.com', '/maps/api/geocode/json',
                {'address': address, 'components': 'country:BR', 'language': 'pt-BR', 'key': googleMapsApiKey},
              ));
              if (resp.statusCode != 200) {
                FieldLog.event('geocode_cep_google', {'http': resp.statusCode});
              } else {
                final body    = jsonDecode(resp.body) as Map<String, dynamic>;
                final status  = body['status'] as String? ?? '';
                final results = (body['results'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
                if (status != 'OK') FieldLog.event('geocode_cep_google', {'status': status});
                if (status == 'OK' && results.isNotEmpty) {
                  final first       = results.first;
                  final locType     = (first['geometry'] as Map<String, dynamic>?)?['location_type'] as String? ?? '';
                  final loc         = (first['geometry'] as Map<String, dynamic>?)?['location'] as Map<String, dynamic>?;
                  // APPROXIMATE = só achou cidade; rejeitar para não meter marker em lugar errado.
                  if (locType != 'APPROXIMATE' && loc != null) {
                    return [GeocodingSuggestion.place(
                      title: label,
                      pos: LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble()),
                    )];
                  }
                }
              }
            } catch (e, st) {
              FieldLog.error('geocode_cep_google', e, st);
            }
          }

          // Passo 4: TomTom structured geocoding — dados proprietários, melhor cobertura que OSM no interior.
          if (logradouro.isNotEmpty && cidade.isNotEmpty) {
            try {
              final pos = await _tomtomStructuredGeocode(
                street: logradouro,
                city: cidade,
                district: bairro,
                state: uf,
              );
              if (pos != null) {
                return [GeocodingSuggestion.place(title: label, pos: pos)];
              }
            } catch (_) {}
          }

          // Passo 4: Nominatim com rua — bom para cidades com cobertura OSM.
          if (logradouro.isNotEmpty && cidade.isNotEmpty) {
            try {
              final resp = await http.get(
                Uri.https('nominatim.openstreetmap.org', '/search', {
                  'street': logradouro,
                  'city': cidade,
                  'countrycodes': 'br',
                  'format': 'jsonv2',
                  'limit': '1',
                  'accept-language': 'pt-BR',
                }),
                headers: {'User-Agent': 'TruckRouterApp/1.0 (devgomesss@gmail.com)'},
              );
              if (resp.statusCode == 200) {
                final items = (jsonDecode(resp.body) as List<dynamic>).cast<Map<String, dynamic>>();
                if (items.isNotEmpty) {
                  return [GeocodingSuggestion.place(
                    title: label,
                    pos: LatLng(
                      double.parse(items.first['lat'] as String),
                      double.parse(items.first['lon'] as String),
                    ),
                  )];
                }
              }
            } catch (_) {}
          }

          // Passo 5: fallback para centróide da cidade — rua não mapeada em nenhum geocoder,
          // mas ao menos posiciona no município correto com o label do ViaCEP.
          if (cidade.isNotEmpty) {
            try {
              final resp = await http.get(
                Uri.https('nominatim.openstreetmap.org', '/search', {
                  'city': cidade,
                  if (uf.isNotEmpty) 'state': uf,
                  'countrycodes': 'br',
                  'format': 'jsonv2',
                  'limit': '1',
                  'accept-language': 'pt-BR',
                }),
                headers: {'User-Agent': 'TruckRouterApp/1.0 (devgomesss@gmail.com)'},
              );
              if (resp.statusCode == 200) {
                final items = (jsonDecode(resp.body) as List<dynamic>).cast<Map<String, dynamic>>();
                if (items.isNotEmpty) {
                  return [GeocodingSuggestion.place(
                    title: label,
                    pos: LatLng(
                      double.parse(items.first['lat'] as String),
                      double.parse(items.first['lon'] as String),
                    ),
                  )];
                }
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    // Passo 5: HERE postalCode qq (fallback se ViaCEP falhar).
    try {
      final resp = await http.get(Uri.parse('$backendUrl/here/geocode').replace(
        queryParameters: {'qq': 'postalCode=$cep;country=Brazil', 'in': 'countryCode:BRA', 'lang': 'pt-BR', 'limit': '3'},
      ), headers: await AuthService.getHeaders());
      if (resp.statusCode == 200) {
        final items = (jsonDecode(resp.body)['items'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>()
            .where((i) => i['position'] != null)
            .toList();
        if (items.isNotEmpty) {
          return items.map((i) {
            final pos   = i['position'] as Map<String, dynamic>;
            final lbl   = (i['address'] as Map<String, dynamic>?)?['label'] as String? ?? cep;
            return GeocodingSuggestion.place(
              title: lbl,
              pos: LatLng((pos['lat'] as num).toDouble(), (pos['lng'] as num).toDouble()),
            );
          }).toList();
        }
      }
    } catch (_) {}

    // Todas as etapas falharam pra um CEP que existe (ou nem o ViaCEP respondeu):
    // "CEP esgotado" é indistinguível de "CEP inexistente" na UI — o log separa.
    FieldLog.event('cep_exhausted', {'cep': cep});
    return [];
  }

  // TomTom structured geocoding: dados proprietários com boa cobertura de ruas no Brasil.
  // Valida que a cidade retornada bate com a cidade do ViaCEP — evita pegar
  // "Rua Riachuelo" de São Paulo quando o CEP é de Vitória de Santo Antão.
  static Future<LatLng?> _tomtomStructuredGeocode({
    required String street,
    required String city,
    String district = '',
    String state = '',
  }) async {
    final params = <String, String>{
      'countryCode':  'BR',
      'streetName':   street,
      'municipality': city,
      'language':     'pt-BR',
      'limit':        '5',
      if (district.isNotEmpty) 'municipalitySubdivision': district,
      if (state.isNotEmpty)    'countrySubdivision': state,
    };
    final uri = Uri.parse('$backendUrl/tomtom/geocode').replace(queryParameters: params);
    final resp = await http.get(uri, headers: await AuthService.getHeaders()).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;

    final results = (jsonDecode(resp.body)['results'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    if (results.isEmpty) return null;

    final cityNorm   = _norm(city);
    final streetNorm = _norm(street);
    final streetKeys = streetNorm.split(' ').where((w) => w.length > 3).toList();

    Map<String, dynamic>? match;
    for (final r in results) {
      final addr           = r['address'] as Map<String, dynamic>? ?? {};
      final returnedCity   = _norm(addr['municipality'] as String? ?? '');
      final returnedStreet = _norm(addr['streetName']   as String? ?? '');
      if (returnedStreet.isEmpty) continue;
      final cityOk   = returnedCity.contains(cityNorm) || cityNorm.contains(returnedCity);
      final streetOk = streetKeys.any((w) => returnedStreet.contains(w));
      if (cityOk && streetOk) { match = r; break; }
    }

    if (match == null) return null;
    final pos = match['position'] as Map<String, dynamic>?;
    if (pos == null) return null;
    return LatLng(
      (pos['lat'] as num).toDouble(),
      (pos['lon'] as num).toDouble(),
    );
  }

  static String _norm(String s) => s.toLowerCase().trim();

  // Lookup HERE: ID do autocomplete → coordenadas precisas.
  static Future<LatLng?> lookup(String hereId) async {
    final response = await http.get(
        Uri.parse('$backendUrl/here/lookup').replace(queryParameters: {
          'id':   hereId,
          'lang': 'pt-BR',
        }),
        headers: await AuthService.getHeaders());
    if (response.statusCode != 200) return null;

    final pos = jsonDecode(response.body)['position'] as Map<String, dynamic>?;
    if (pos == null) return null;
    return LatLng(
      (pos['lat'] as num).toDouble(),
      (pos['lng'] as num).toDouble(),
    );
  }

  static Future<String> reverseGeocode(LatLng position) async {
    final response = await http.get(
        Uri.parse('$backendUrl/here/revgeocode').replace(queryParameters: {
          'at':    '${position.latitude},${position.longitude}',
          'lang':  'pt-BR',
          'limit': '1',
        }),
        headers: await AuthService.getHeaders());
    if (response.statusCode != 200) {
      return '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
    }
    final items = jsonDecode(response.body)['items'] as List<dynamic>? ?? [];
    if (items.isEmpty) {
      return '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
    }
    return (items[0] as Map<String, dynamic>)['address']?['label'] as String?
        ?? '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
  }
}
