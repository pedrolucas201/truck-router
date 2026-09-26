import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/truck_profile.dart';
import '../services/auth_service.dart';
import '../services/driver_profile_service.dart';
import '../services/field_log.dart';
import '../services/truck_mirror.dart';

class TruckProfileProvider extends ChangeNotifier {
  static const _profilesKey = 'truck_profiles_v2';
  static const _activeKey   = 'truck_active_id';
  static const _migradoKey  = 'truck_identity_migrated';
  static const _editadoKey  = 'truck_editado';

  List<TruckProfile> _profiles = [];
  String? _activeId;

  /// O motorista já configurou caminhão NESTE aparelho.
  ///
  /// É o que separa "celular novo, ainda sem nada" de "celular em uso", e o
  /// espelho ([TruckMirror]) obedece a ele nos dois sentidos:
  /// falso = não sobe e pode receber; verdadeiro = sobe e nunca recebe.
  ///
  /// Flag, e não comparação com 4,20 m / 25 t: constante calibrada erraria num
  /// caminhão real que por acaso meça o padrão de fábrica.
  bool _editado = false;

  List<TruckProfile> get profiles => List.unmodifiable(_profiles);

  /// Leitura do [_editado] (o onboarding abre a garagem com "O meu" marcado).
  bool get editado => _editado;

  TruckProfile get profile {
    if (_profiles.isEmpty) {
      return TruckProfile(
        id: 'default', name: 'Padrão',
        heightCm: kAlturaPadraoCm, lengthCm: 1400, weightKg: 25000, axleCount: 5,
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
    _editado = prefs.getBool(_editadoKey) ?? false;
    // A flag nasceu depois do app. Ausente = este boot é o PRIMEIRO que a
    // enxerga, e é a única chance de decidir o que esta instalação é: ter
    // `truck_profiles_v2` sem nunca ter tido a flag só acontece se ela já
    // rodou numa versão anterior, logo o caminhão dela é real.
    //
    // Sem esta decisão o espelho ficava MORTO pra todo usuário existente:
    // `_editado` continuava falso até ele tocar na tela de caminhões, e o
    // primeiro campo (22/09, v2.4.87) mostrou exatamente isso — zero
    // `truck_mirror_save` numa viagem inteira.
    final semFlag = !prefs.containsKey(_editadoKey);

    if (raw == null) {
      // Migra perfil único do formato antigo (ou cria padrão).
      final legadoAltura = prefs.getInt('truck_height');
      final p = TruckProfile(
        id:        DateTime.now().millisecondsSinceEpoch.toString(),
        name:      'Padrão',
        heightCm:  legadoAltura                     ?? kAlturaPadraoCm,
        widthCm:   prefs.getInt('truck_width')      ?? 260,
        lengthCm:  prefs.getInt('truck_length')     ?? 1400,
        weightKg:  prefs.getInt('truck_weight')     ?? 25000,
        axleCount: prefs.getInt('truck_axle_count') ?? 5,
      );
      _profiles = [p];
      _activeId = p.id;
      // Quem vinha do formato antigo JÁ tinha configurado o caminhão. Sem
      // isto o espelho o trataria como aparelho novo e poderia trocar a
      // altura real dele pela de outro aparelho. Marca ANTES do persist pra
      // que a configuração real dele suba já neste boot.
      if (legadoAltura != null) {
        await _marcarEditado(prefs);
      } else if (semFlag) {
        // Instalação limpa de verdade: CRAVA o falso. Sem gravar, o próximo
        // boot veria `truck_profiles_v2` sem flag e se acharia uma instalação
        // antiga — matando a restauração justo em quem trocou de celular.
        await prefs.setBool(_editadoKey, false);
      }
      await _persist(prefs);
    } else {
      _profiles = raw
          .map((s) => TruckProfile.fromJson(
              jsonDecode(s) as Map<String, dynamic>))
          .toList();
      _activeId = prefs.getString(_activeKey) ?? _profiles.first.id;
      // Já tinha caminhão antes da flag existir: é aparelho configurado.
      // Marca ANTES do persist pra que os caminhões dele subam neste boot.
      if (semFlag) {
        await _marcarEditado(prefs);
        await _persist(prefs);
      }
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
    // Modelo/cor/placa digitados pelo motorista: este aparelho está
    // configurado. Antes do persist, pra subir junto.
    await _marcarEditado(prefs);
    await _persist(prefs);
  }

  Future<void> _marcarEditado(SharedPreferences prefs) async {
    if (_editado) return;
    _editado = true;
    await prefs.setBool(_editadoKey, true);
  }

  Future<void> setActive(String id) async {
    if (!_profiles.any((p) => p.id == id)) return;
    _activeId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, id);
    _espelhar();
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
    await _marcarEditado(prefs);
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
    await _marcarEditado(prefs);
    await _persist(prefs);
    notifyListeners();
  }

  Future<void> _persist(SharedPreferences prefs) async {
    await prefs.setStringList(
      _profilesKey,
      _profiles.map((p) => jsonEncode(p.toJson())).toList(),
    );
    _espelhar();
  }

  /// Sobe o espelho, mas só de aparelho configurado.
  ///
  /// Sem o gate, a instalação limpa subiria o caminhão de FÁBRICA por cima dos
  /// caminhões reais no banco — no `load()`, antes de o motorista ter qualquer
  /// chance de restaurá-los.
  void _espelhar() {
    if (!_editado) return;
    unawaited(TruckMirror.salvar(_profiles, _activeId));
  }

  /// Pura, pra teste. O aparelho só recebe caminhões do banco enquanto o
  /// motorista não configurou nenhum aqui.
  ///
  /// Depois que ele configurou, NADA vindo do banco toca a lista: a altura
  /// digitada neste celular é o que decide se o caminhão passa embaixo do
  /// viaduto, e trocá-la pela de outro aparelho é exatamente o acidente que
  /// este espelho existe pra evitar.
  @visibleForTesting
  static bool podeRestaurar({required bool editado, required bool temGoogle}) =>
      !editado && temGoogle;

  /// Traz os caminhões do banco pra um aparelho novo. Devolve true se trouxe.
  ///
  /// Substitui a lista **e o ativo**: restaurar sem trocar o ativo deixaria o
  /// caminhão de fábrica dirigindo com o real parado na lista, que é pior que
  /// não restaurar nada.
  Future<bool> restaurarDoBanco() async {
    if (!podeRestaurar(
        editado: _editado, temGoogle: AuthService.isGoogleLinked)) {
      return false;
    }
    final r = await TruckMirror.buscar();
    if (r == null) return false;
    final prefs = await SharedPreferences.getInstance();
    _profiles = r.trucks;
    _activeId = r.trucks.any((t) => t.id == r.activeId)
        ? r.activeId
        : r.trucks.first.id;
    await prefs.setString(_activeKey, _activeId!);
    // Persiste ANTES de marcar: o `_espelhar` de dentro do `_persist` ainda vê
    // `_editado == false` e não devolve pro banco o que acabou de vir de lá.
    await _persist(prefs);
    await _marcarEditado(prefs);
    FieldLog.event('truck_restore', {'n': _profiles.length});
    notifyListeners();
    return true;
  }
}
