import 'package:shared_preferences/shared_preferences.dart';
import '../models/route_history.dart';

/// Rotas favoritas: cópia fixada pelo usuário (com apelido), independente do
/// histórico (não some no corte de 10). Mesmo RouteHistory → reusa _restoreHistory.
class FavoritesService {
  static const _key = 'favorite_routes_v1';

  // Identidade de uma rota = origem + destino + paradas (mesmo critério do
  // dedup do HistoryService).
  static String keyOf(RouteHistory h) =>
      '${h.originLabel}|${h.destinationLabel}|${h.waypoints.map((w) => w.label).join(",")}';

  static Future<List<RouteHistory>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return RouteHistory.listFromJson(raw);
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<RouteHistory> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, RouteHistory.listToJson(list));
  }

  /// Fixa (com o apelido já setado em `h.name`). Substitui se já existir a rota.
  static Future<void> add(RouteHistory h) async {
    final list = await load();
    final k = keyOf(h);
    list.removeWhere((e) => keyOf(e) == k);
    list.insert(0, h);
    await _save(list);
  }

  static Future<void> remove(RouteHistory h) async {
    final list = await load();
    final k = keyOf(h);
    list.removeWhere((e) => keyOf(e) == k);
    await _save(list);
  }
}
