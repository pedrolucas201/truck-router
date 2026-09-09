import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../utils/google_cache.dart';

/// Memória local de lugares que o usuário já escolheu (partida/destino/parada).
/// Sobrevive ao corte do histórico de rotas (10 itens): digitar de novo um
/// endereço usado antes re-sugere ele na hora. Recente primeiro, dedup por label.
///
/// Lugar cuja coordenada veio da Google carrega `g:true` + `at` (quando a
/// Google entregou) e é APAGADO do disco 30 dias depois — termo 6.3.1, ver
/// utils/google_cache.dart. O label desses é o texto digitado pelo motorista.
class PlacesService {
  // Histórico separado POR PAPEL (origem/destino/parada): partida e destino são
  // conjuntos diferentes de lugares. `_legacyKey` é o histórico antigo (único,
  // compartilhado): quando um papel ainda não tem dados próprios, ele HERDA o
  // legado uma vez — assim ninguém perde o histórico ao atualizar.
  static const _legacyKey = 'known_places_v1';
  static const _max = 150; // ponytail: teto simples; evict o mais antigo

  static String _keyFor(String role) => 'known_places_v1_$role';

  static List<String> _stored(SharedPreferences prefs, String role) =>
      prefs.getStringList(_keyFor(role)) ??
      (role == 'destination' ? prefs.getStringList(_legacyKey) : null) ??
      const [];

  // Tira do disco o que a Google não deixa mais guardar. Entrada google sem
  // `at` também cai (não dá pra provar que está no prazo). Corrompida fica,
  // como antes (o leitor pula).
  static List<String> _prune(List<String> raw, DateTime now) => raw.where((s) {
        try {
          final m = jsonDecode(s) as Map<String, dynamic>;
          if (m['g'] != true) return true;
          final at = m['at'] as int?;
          return at != null &&
              !googleCacheExpired(DateTime.fromMillisecondsSinceEpoch(at), now);
        } catch (_) {
          return true;
        }
      }).toList();

  /// `$3` = coordenada veio da Google: quem consome não pode guardar sem prazo
  /// (histórico de rotas marca a entrada com `google: true`).
  static Future<List<(String, LatLng, bool google)>> all(String role) async {
    final prefs  = await SharedPreferences.getInstance();
    final stored = _stored(prefs, role);
    final raw    = _prune(stored, DateTime.now());
    // Expirado sai do disco, não só da lista: o termo manda apagar.
    if (raw.length != stored.length) await prefs.setStringList(_keyFor(role), raw);
    final out = <(String, LatLng, bool)>[];
    for (final s in raw) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        out.add((
          m['label'] as String,
          LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
          m['g'] == true,
        ));
      } catch (_) {}
    }
    return out;
  }

  /// Semeia a memória (uma vez) a partir de lugares já existentes — ex: o
  /// histórico de rotas — pra não nascer vazia. Não faz nada se já houver dados.
  /// `places` deve vir recente primeiro e SEM entrada da Google (a marca não
  /// viaja por aqui).
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

  /// `google: true` = a coordenada ACABOU de vir da Google → prazo novo.
  /// Re-escolher um recente (sem `google`) só sobe ele na lista: a marca e o
  /// `at` originais ficam, porque o prazo conta da entrega da Google, não da
  /// reutilização.
  static Future<void> record(String role, String label, LatLng pos,
      {bool google = false}) async {
    final l = label.trim();
    if (l.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final now   = DateTime.now();
    final raw   = List<String>.from(_stored(prefs, role));
    Map<String, dynamic>? prev;
    raw.removeWhere((s) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        if ((m['label'] as String).toLowerCase() != l.toLowerCase()) return false;
        prev = m;
        return true;
      } catch (_) {
        return false;
      }
    });
    final entry = <String, dynamic>{'label': l, 'lat': pos.latitude, 'lng': pos.longitude};
    if (google) {
      entry['g']  = true;
      entry['at'] = now.millisecondsSinceEpoch;
    } else if (prev?['g'] == true) {
      entry['g']  = true;
      entry['at'] = prev!['at'];
    }
    raw.insert(0, jsonEncode(entry));
    final kept = _prune(raw, now); // inclusive a recém-inserida, se herdou at vencido
    if (kept.length > _max) kept.removeRange(_max, kept.length);
    await prefs.setStringList(_keyFor(role), kept);
  }
}
