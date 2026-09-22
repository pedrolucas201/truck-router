import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/truck_profile.dart';
import 'auth_service.dart';
import 'field_log.dart';

/// Espelho dos caminhões em `trucks/{uid}`. Local-first: a verdade vive em
/// SharedPreferences (`TruckProfileProvider`) e isto é só a cópia que sobrevive
/// a trocar de celular ou reinstalar sem backup.
///
/// **Documento separado de `profiles/{uid}` de propósito.** A regra de lá exige
/// `name` não-vazio e usa `hasOnly` sobre o doc MESCLADO; o motorista configura
/// a altura do caminhão muito antes de preencher o perfil, então guardar os
/// caminhões lá faria o primeiro save tomar `permission-denied` — e um erro meu
/// naquele schema derrubaria junto o espelho do nome e do telefone, que já
/// funciona.
///
/// Sem Google o uid é anônimo e o espelho morre junto com ele, igual ao perfil
/// (item aberto desde a 2.4.53).
class TruckMirror {
  TruckMirror._();

  static final _col = FirebaseFirestore.instance.collection('trucks');

  /// Sobe a lista inteira. `set` sem merge: quem fala manda, e um caminhão
  /// apagado aqui tem que sumir de lá. Best-effort — nunca lança, nunca
  /// bloqueia tela, navegação não espera rede.
  static Future<void> salvar(List<TruckProfile> trucks, String? activeId) async {
    try {
      final uid = await AuthService.getUid();
      await _col.doc(uid).set({
        'trucks':    trucks.map((t) => t.toJson()).toList(),
        'activeId':  activeId ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      FieldLog.event('truck_mirror_save', {'n': trucks.length});
    } catch (e, st) {
      FieldLog.error('truck_mirror_save', e, st);
    }
  }

  /// Lista do banco, ou null se não existe / falhou (sem rede): o chamador
  /// segue com o que tem.
  ///
  /// Um caminhão ilegível derruba só ele, não a lista: perder tudo por um campo
  /// que mudou seria o mesmo erro que o `fromJson` tolerante já evita.
  static Future<({List<TruckProfile> trucks, String activeId})?> buscar() async {
    try {
      final uid  = await AuthService.getUid();
      final snap = await _col.doc(uid).get();
      final data = snap.data();
      if (data == null) return null;
      final trucks = <TruckProfile>[];
      for (final raw in (data['trucks'] as List? ?? const [])) {
        try {
          trucks.add(
              TruckProfile.fromJson(Map<String, dynamic>.from(raw as Map)));
        } catch (_) {
          // ignora o item, mantém os outros
        }
      }
      if (trucks.isEmpty) return null;
      return (trucks: trucks, activeId: (data['activeId'] as String?) ?? '');
    } catch (e, st) {
      FieldLog.error('truck_mirror_fetch', e, st);
      return null;
    }
  }
}
