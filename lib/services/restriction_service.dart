import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_restriction.dart';

class RestrictionService {
  static const _key = 'user_restrictions_v1';

  static Future<List<UserRestriction>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final result = <UserRestriction>[];
    for (final s in raw) {
      try {
        result.add(UserRestriction.fromJson(
            jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
    return result;
  }

  static Future<void> add(UserRestriction r) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.add(jsonEncode(r.toJson()));
    await prefs.setStringList(_key, raw);
  }

  static Future<void> remove(UserRestriction r) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final iso = r.createdAt.toIso8601String();
    raw.removeWhere((s) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        return (m['lat'] as num?)?.toDouble() == r.lat &&
            (m['lng'] as num?)?.toDouble() == r.lng &&
            m['createdAt'] == iso;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(_key, raw);
  }
}
