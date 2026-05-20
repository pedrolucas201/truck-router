import 'package:shared_preferences/shared_preferences.dart';
import '../models/route_history.dart';

class HistoryService {
  static const _key    = 'route_history';
  static const _maxLen = 10;

  static Future<List<RouteHistory>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return RouteHistory.listFromJson(raw);
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(RouteHistory entry) async {
    final current = await load();
    current.removeWhere((h) =>
        h.originLabel == entry.originLabel &&
        h.destinationLabel == entry.destinationLabel &&
        h.waypoints.length == entry.waypoints.length &&
        List.generate(h.waypoints.length, (i) => i)
            .every((i) => h.waypoints[i].label == entry.waypoints[i].label));
    current.insert(0, entry);
    if (current.length > _maxLen) current.removeLast();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, RouteHistory.listToJson(current));
  }

  static Future<void> remove(int index) async {
    final current = await load();
    if (index < 0 || index >= current.length) return;
    current.removeAt(index);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, RouteHistory.listToJson(current));
  }
}
