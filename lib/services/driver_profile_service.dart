import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/driver_profile.dart';
import 'auth_service.dart';
import 'field_log.dart';

/// Perfil do motorista: local-first (SharedPreferences), espelhado em
/// `profiles/{uid}` no Firestore (regra: só o dono lê e escreve).
///
/// O espelho é o que faz o perfil sobreviver a uma reinstalação: quando o
/// motorista entra com o Google num aparelho limpo, [AuthService.linkWithGoogle]
/// recupera o uid antigo e [fetchRemote] traz o perfil de volta. Sem Google o
/// uid é anônimo e o espelho morre junto com ele (é o item aberto desde a
/// 2.4.53) — por isso a tela empurra pro login.
class DriverProfileService {
  DriverProfileService._();

  static const _key = 'driver_profile_v1';
  static final _col = FirebaseFirestore.instance.collection('profiles');

  static Future<DriverProfile?> loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return DriverProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Identidade do caminhão como era gravada até 2.4.73 (`truck`/`color`/
  /// `plate` dentro do perfil do MOTORISTA). Lê o JSON cru porque
  /// [DriverProfile] não tem mais esses campos.
  ///
  /// Existe só pra [TruckProfileProvider.migrarIdentidade] não jogar fora o que
  /// o motorista já digitou. Quando não houver mais perfil gravado no formato
  /// antigo em campo, isto e a migração saem juntos.
  static Future<({String model, String color, String plate})?>
      legadoIdentidade() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final r = (
        model: (j['truck'] as String?) ?? '',
        color: (j['color'] as String?) ?? '',
        plate: (j['plate'] as String?) ?? '',
      );
      if (r.model.isEmpty && r.color.isEmpty && r.plate.isEmpty) return null;
      return r;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveLocal(DriverProfile p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(p.toJson()));
  }

  /// Grava local (sempre) e no Firestore (best-effort: sem rede o local vale,
  /// e o próximo save sincroniza). Nunca lança pro chamador.
  static Future<void> save(DriverProfile p) async {
    await _saveLocal(p);
    try {
      final uid = await AuthService.getUid();
      await _col.doc(uid).set(
        {...p.toJson(), 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      FieldLog.event('profile_save', {
        'phone': p.phone.isNotEmpty,
        'google': AuthService.isGoogleLinked,
      });
    } catch (e, st) {
      FieldLog.error('profile_save', e, st);
    }
  }

  /// Busca o espelho do uid atual e o torna o local. Null se não existe ou
  /// se falhou (sem rede): o chamador segue com o que tem.
  static Future<DriverProfile?> fetchRemote() async {
    try {
      final uid = await AuthService.getUid();
      final snap = await _col.doc(uid).get();
      final data = snap.data();
      if (data == null) return null;
      final p = DriverProfile.fromJson(data);
      await _saveLocal(p);
      return p;
    } catch (e, st) {
      FieldLog.error('profile_fetch', e, st);
      return null;
    }
  }
}
