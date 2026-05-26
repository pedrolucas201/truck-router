import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config.dart';

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

    final hereResults = await Future.wait([
      _autocomplete(query, bias: bias),
      _geocodePlaces(query, bias: bias),
      _discoverPlaces(query, bias: bias),
    ]);

    final merged   = <GeocodingSuggestion>[];
    final seenKeys = <String>{};
    for (final list in hereResults) {
      for (final s in list) {
        if (seenKeys.add(s.title.toLowerCase().trim())) merged.add(s);
      }
    }

    // Fallback: Nominatim (OpenStreetMap) quando HERE não encontra nada.
    // Chamado só neste caso para respeitar o limite de 1 req/s do serviço gratuito.
    if (merged.isEmpty) {
      final nominatim = await _nominatimSearch(query, bias: bias);
      for (final s in nominatim) {
        if (seenKeys.add(s.title.toLowerCase().trim())) merged.add(s);
      }
    }

    return merged.take(5).toList();
  }

  // Autocomplete HERE: endereços com ID único (sem ambiguidade de coords).
  static Future<List<GeocodingSuggestion>> _autocomplete(
      String query, {LatLng? bias}) async {
    final params = <String, String>{
      'q':      query,
      'lang':   'pt-BR',
      'limit':  '4',
      'in':     'countryCode:BRA',
      'apikey': hereApiKey,
      if (bias != null) 'at': '${bias.latitude},${bias.longitude}',
    };
    final response = await http.get(
        Uri.https('autocomplete.search.hereapi.com', '/v1/autocomplete', params));
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
      'apikey': hereApiKey,
      if (bias != null) 'at': '${bias.latitude},${bias.longitude}',
    };
    final response = await http.get(
        Uri.https('geocode.search.hereapi.com', '/v1/geocode', params));
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
      'apikey': hereApiKey,
    };
    final response = await http.get(
        Uri.https('discover.search.hereapi.com', '/v1/discover', params));
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
    final response = await http.get(
      Uri.https('nominatim.openstreetmap.org', '/search', params),
      headers: {'User-Agent': 'TruckRouterApp/1.0 (devgomesss@gmail.com)'},
    );
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

      final String title;
      if (name.isNotEmpty && city.isNotEmpty) {
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
              final resp = await http.get(Uri.https(
                'geocode.search.hereapi.com', '/v1/geocode',
                {'qq': qqParts.join(';'), 'in': 'countryCode:BRA', 'lang': 'pt-BR', 'limit': '5', 'apikey': hereApiKey},
              ));
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
          if (logradouro.isNotEmpty && cidade.isNotEmpty) {
            try {
              final address = [logradouro, if (bairro.isNotEmpty) bairro, cidade, uf, 'Brasil']
                  .join(', ');
              final resp = await http.get(Uri.https(
                'maps.googleapis.com', '/maps/api/geocode/json',
                {'address': address, 'components': 'country:BR', 'language': 'pt-BR', 'key': googleMapsApiKey},
              ));
              if (resp.statusCode == 200) {
                final body    = jsonDecode(resp.body) as Map<String, dynamic>;
                final status  = body['status'] as String? ?? '';
                final results = (body['results'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
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
            } catch (_) {}
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
      final resp = await http.get(Uri.https(
        'geocode.search.hereapi.com', '/v1/geocode',
        {'qq': 'postalCode=$cep;country=Brazil', 'in': 'countryCode:BRA', 'lang': 'pt-BR', 'limit': '3', 'apikey': hereApiKey},
      ));
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
      'key':          tomTomApiKey,
      'countryCode':  'BR',
      'streetName':   street,
      'municipality': city,
      'language':     'pt-BR',
      'limit':        '5',
      if (district.isNotEmpty) 'municipalitySubdivision': district,
      if (state.isNotEmpty)    'countrySubdivision': state,
    };
    final uri = Uri.https('api.tomtom.com', '/search/2/structuredGeocode.json', params);
    final resp = await http.get(uri).timeout(const Duration(seconds: 8));
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
        Uri.https('lookup.search.hereapi.com', '/v1/lookup', {
      'id':     hereId,
      'lang':   'pt-BR',
      'apikey': hereApiKey,
    }));
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
        Uri.https('revgeocode.search.hereapi.com', '/v1/revgeocode', {
      'at':     '${position.latitude},${position.longitude}',
      'lang':   'pt-BR',
      'limit':  '1',
      'apikey': hereApiKey,
    }));
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
