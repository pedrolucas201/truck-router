import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Memória local de lugares que o usuário já escolheu (partida/destino/parada).
/// Sobrevive ao corte do histórico de rotas (10 itens): digitar de novo um
/// endereço usado antes re-sugere ele na hora. Recente primeiro, dedup por label.
class PlacesService {
  // Histórico separado POR PAPEL (origem/destino/parada): partida e destino são
  // conjuntos diferentes de lugares. `_legacyKey` é o histórico antigo (único,
  // compartilhado): quando um papel ainda não tem dados próprios, ele HERDA o
  // legado uma vez — assim ninguém perde o histórico ao atualizar.
  static const _legacyKey = 'known_places_v1';
  static const _max = 150; // ponytail: teto simples; evict o mais antigo

  static String _keyFor(String role) => 'known_places_v1_$role';

  static Future<List<(String, LatLng)>> all(String role) async {
    final prefs = await SharedPreferences.getInstance();
    // O histórico antigo (sem papel) herda só pro DESTINO — é onde ficam quase
    // todos os lugares salvos. A origem começa limpa (evita a duplicação).
    final raw = prefs.getStringList(_keyFor(role)) ??
        (role == 'destination' ? prefs.getStringList(_legacyKey) : null) ??
        const [];
    final out = <(String, LatLng)>[];
    for (final s in raw) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        out.add((
          m['label'] as String,
          LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
        ));
      } catch (_) {}
    }
    return out;
  }

  /// Semeia a memória (uma vez) a partir de lugares já existentes — ex: o
  /// histórico de rotas — pra não nascer vazia. Não faz nada se já houver dados.
  /// `places` deve vir recente primeiro.
  static Future<void> seedIfEmpty(List<(String, LatLng)> places) async {
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getStringList(_legacyKey) ?? []).isNotEmpty) return;
    final seen = <String>{};
    final raw = <String>[];
    for (final p in places) {
      final l = p.$1.trim();
      if (l.isEmpty || !seen.add(l.toLowerCase())) continue;
      raw.add(jsonEncode({'label': l, 'lat': p.$2.latitude, 'lng': p.$2.longitude}));
      if (raw.length >= _max) break;
    }
    if (raw.isNotEmpty) await prefs.setStringList(_legacyKey, raw);
  }

  static Future<void> record(String role, String label, LatLng pos) async {
    final l = label.trim();
    if (l.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final k = _keyFor(role);
    // Se este papel ainda não tem histórico próprio, o destino herda o legado
    // uma vez (a origem não — começa limpa).
    final raw = List<String>.from(prefs.getStringList(k) ??
        (role == 'destination' ? prefs.getStringList(_legacyKey) : null) ??
        const []);
    raw.removeWhere((s) {
      try {
        return ((jsonDecode(s) as Map)['label'] as String).toLowerCase() ==
            l.toLowerCase();
      } catch (_) {
        return false;
      }
    });
    raw.insert(0, jsonEncode({'label': l, 'lat': pos.latitude, 'lng': pos.longitude}));
    if (raw.length > _max) raw.removeRange(_max, raw.length);
    await prefs.setStringList(k, raw);
  }
}
