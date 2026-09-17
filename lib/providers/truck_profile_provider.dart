import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/truck_profile.dart';
import '../services/driver_profile_service.dart';

class TruckProfileProvider extends ChangeNotifier {
  static const _profilesKey = 'truck_profiles_v2';
  static const _activeKey   = 'truck_active_id';
  static const _migradoKey  = 'truck_identity_migrated';

  List<TruckProfile> _profiles = [];
  String? _activeId;

  List<TruckProfile> get profiles => List.unmodifiable(_profiles);

  TruckProfile get profile {
    if (_profiles.isEmpty) {
      return TruckProfile(
        id: 'default', name: 'Padrão',
        heightCm: 420, lengthCm: 1400, weightKg: 25000, axleCount: 5,
      );
    }
    return _profiles.firstWhere(
      (p) => p.id == _activeId,
      orElse: () => _profiles.first,
    );
  }

  String? get activeId => _activeId;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_profilesKey);

    if (raw == null) {
      // Migra perfil único do formato antigo (ou cria padrão).
      final p = TruckProfile(
        id:        DateTime.now().millisecondsSinceEpoch.toString(),
        name:      'Padrão',
        heightCm:  prefs.getInt('truck_height')     ?? 420,
        widthCm:   prefs.getInt('truck_width')      ?? 260,
        lengthCm:  prefs.getInt('truck_length')     ?? 1400,
        weightKg:  prefs.getInt('truck_weight')     ?? 25000,
        axleCount: prefs.getInt('truck_axle_count') ?? 5,
      );
      _profiles = [p];
      _activeId = p.id;
      await _persist(prefs);
    } else {
      _profiles = raw
          .map((s) => TruckProfile.fromJson(
              jsonDecode(s) as Map<String, dynamic>))
          .toList();
      _activeId = prefs.getString(_activeKey) ?? _profiles.first.id;
    }
    await _migrarIdentidade(prefs);
    notifyListeners();
  }

  /// Traz modelo/cor/placa do perfil do MOTORISTA (onde moravam até 2.4.73) pro
  /// caminhão ativo. Roda uma vez por instalação: com flag, e não "só quando
  /// está vazio", senão apagar o modelo de propósito faria ele voltar no
  /// próximo boot.
  Future<void> _migrarIdentidade(SharedPreferences prefs) async {
    if (prefs.getBool(_migradoKey) ?? false) return;
    await prefs.setBool(_migradoKey, true);
    final legado = await DriverProfileService.legadoIdentidade();
    if (legado == null || _profiles.isEmpty) return;
    final i = _profiles.indexWhere((p) => p.id == _activeId);
    final idx = i >= 0 ? i : 0;
    _profiles[idx] = _profiles[idx].copyWith(
      model: legado.model,
      color: legado.color,
      plate: legado.plate,
    );
    await _persist(prefs);
  }

  Future<void> setActive(String id) async {
    if (!_profiles.any((p) => p.id == id)) return;
    _activeId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, id);
    notifyListeners();
  }

  Future<void> saveProfile(TruckProfile profile) async {
    final idx = _profiles.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      _profiles[idx] = profile;
    } else {
      _profiles.add(profile);
    }
    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs);
    notifyListeners();
  }

  Future<void> deleteProfile(String id) async {
    if (_profiles.length <= 1) return;
    _profiles.removeWhere((p) => p.id == id);
    if (_activeId == id) {
      _activeId = _profiles.first.id;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, _activeId!);
    await _persist(prefs);
    notifyListeners();
  }

  Future<void> _persist(SharedPreferences prefs) async {
    await prefs.setStringList(
      _profilesKey,
      _profiles.map((p) => jsonEncode(p.toJson())).toList(),
    );
  }
}
