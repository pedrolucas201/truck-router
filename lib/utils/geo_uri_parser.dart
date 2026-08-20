import 'package:google_maps_flutter/google_maps_flutter.dart';

typedef GeoLocation = ({LatLng coords, String? label});

typedef MapsRoute = ({LatLng? origin, LatLng destination});

enum DeepLinkType { route, destination, unknown }

/// O que fazer com uma localização que chegou por link.
///
/// - [apply]       — não há destino e o mapa está na frente: aplica direto
/// - [ask]         — já existe destino: pergunta antes de substituir
/// - [offerSwap]   — navegação aberta: popup "de X → para Y" DENTRO da nav
/// - [storeQuietly] — outra tela por cima (não é a nav): guarda calado e avisa
enum IncomingLinkAction { apply, ask, offerSwap, storeQuietly }

/// Decide o que fazer com um link recebido.
///
/// [navOnTop] manda mais que tudo: link só chega quando o motorista TOCA nele,
/// então com a navegação aberta o toque é intenção explícita — a nav mostra o
/// popup de troca de destino (decisão do Pedro em 19/08/2026, desfazendo o
/// guardar-calado de 12/08 pra esse caso). [screenOnTop] sem nav (ex.: perfil
/// do caminhão por cima do mapa) mantém o guardar-calado: um diálogo do mapa
/// por baixo de outra tela seguiria sendo o "Usar" mentiroso de antes.
IncomingLinkAction incomingLinkAction({
  required bool screenOnTop,
  required bool hasDestination,
  bool navOnTop = false,
}) {
  if (navOnTop)      return IncomingLinkAction.offerSwap;
  if (screenOnTop)   return IncomingLinkAction.storeQuietly;
  if (hasDestination) return IncomingLinkAction.ask;
  return IncomingLinkAction.apply;
}

// Hosts do Google Maps que carregam coords em ?q= ou saddr/daddr. Shortlink
// (maps.app.goo.gl) NÃO entra aqui: precisa resolver o redirect antes — cai no
// fallback de captura até confirmarmos o formato real em device.
const _mapsHosts = {'maps.google.com', 'www.google.com', 'google.com'};
bool _isMapsHost(Uri uri) => _mapsHosts.contains(uri.host);

/// Classifica uma URL maps.google.com por tipo de conteúdo.
///
/// - [route]       — tem saddr + daddr (rota compartilhada pelo despachante)
/// - [destination] — tem q= (pin de localização simples)
/// - [unknown]     — formato não reconhecido
DeepLinkType classifyMapsUri(Uri uri) {
  if (!_isMapsHost(uri)) return DeepLinkType.unknown;
  final p = uri.queryParameters;
  if (p.containsKey('saddr') && p.containsKey('daddr')) return DeepLinkType.route;
  if (p.containsKey('q'))                               return DeepLinkType.destination;
  return DeepLinkType.unknown;
}

/// Parses a `geo:` URI into coordinates and optional label.
///
/// Handles the four common variants:
///   geo:lat,lng
///   geo:lat,lng?z=15
///   geo:0,0?q=lat,lng
///   geo:0,0?q=lat,lng(Label)
///
/// Returns null for malformed or text-search-only URIs (e.g. geo:0,0?q=Coffee).
GeoLocation? parseGeoUri(Uri uri) {
  if (uri.scheme != 'geo') return null;

  final pathCoords = _parseLatLng(uri.path);

  final q = uri.queryParameters['q'];
  if (q != null) {
    final fromQ = _parseQ(q);
    if (fromQ != null) return fromQ;
    // q é endereço em texto (ex: WhatsApp `geo:LAT,LNG?q=Rua...(Nome)`):
    // usa as coords do path e o texto/paren do q como label.
    if (pathCoords != null) {
      final (text, parenLabel) = _splitLabel(q);
      return (coords: pathCoords, label: parenLabel ?? (text.isNotEmpty ? text : null));
    }
    return null;
  }

  if (pathCoords == null) return null;
  return (coords: pathCoords, label: null);
}

/// Parses a `https://maps.google.com/maps?q=LAT,LNG(Label)` URI — o formato de
/// pin de localização nativo do WhatsApp (sem saddr/daddr).
///
/// Returns null se não for maps.google.com, se não houver `q`, ou se o `q` for
/// busca textual sem coordenadas (ex: `q=pizzaria`).
GeoLocation? parseMapsDestination(Uri uri) {
  if (!_isMapsHost(uri)) return null;
  final q = uri.queryParameters['q'];
  if (q == null) return null;
  return _parseQ(q);
}

/// Extrai coords + label opcional de um parâmetro `q` (`LAT,LNG` ou
/// `LAT,LNG(Label)`), compartilhado entre `geo:` e `maps.google.com?q=`.
GeoLocation? _parseQ(String q) {
  final (coords, label) = _splitLabel(q);
  final latLng = _parseLatLng(coords);
  if (latLng == null) return null;
  return (coords: latLng, label: label);
}

/// Separa um `q` em `(texto antes do parêntese, label do parêntese)`.
/// `LAT,LNG(Nome)` → `('LAT,LNG', 'Nome')`; sem parêntese → `(q, null)`.
(String, String?) _splitLabel(String q) {
  final parenIdx = q.indexOf('(');
  if (parenIdx == -1) return (q.trim(), null);
  final label = q.substring(parenIdx + 1, q.endsWith(')') ? q.length - 1 : q.length);
  return (q.substring(0, parenIdx).trim(), label.isNotEmpty ? label : null);
}

/// Parses a `https://maps.google.com/maps?saddr=...&daddr=...` URI.
/// Returns null if daddr is missing or unparseable.
MapsRoute? parseMapsUri(Uri uri) {
  if (!_isMapsHost(uri)) return null;

  final daddrStr = uri.queryParameters['daddr'];
  if (daddrStr == null) return null;
  final destination = _parseLatLng(daddrStr);
  if (destination == null) return null;

  final saddrStr = uri.queryParameters['saddr'];
  final origin = saddrStr != null ? _parseLatLng(saddrStr) : null;

  return (origin: origin, destination: destination);
}

LatLng? _parseLatLng(String s) {
  final parts = s.split(',');
  if (parts.length < 2) return null;
  final lat = double.tryParse(parts[0].trim());
  final lng = double.tryParse(parts[1].trim());
  if (lat == null || lng == null) return null;
  if (lat == 0.0 && lng == 0.0) return null;
  return LatLng(lat, lng);
}
