import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/sos_request.dart';
import 'auth_service.dart';
import 'field_log.dart';

/// Por que o backend recusou. O app mostra UMA frase por chave; nada de
/// sistema vaza pro motorista.
enum SosFalha { perfil, google, contaNova, jaAberto, expirado, semContato, rede }

class SosException implements Exception {
  final SosFalha falha;
  final String? id; // ja_aberto traz o id do que já existe
  final DateTime? liberaEm; // conta_nova
  const SosException(this.falha, {this.id, this.liberaEm});
}

/// Raio em que um S.O.S. é anunciado (decisão de 14/09: 50 km).
/// ponytail: constante calibrada; muda com dado de campo.
const kSosRaioM = 50000.0;

/// Escrita: backend (gates). Leitura: Firestore direto (stream).
class SosService {
  SosService._();

  static final _col = FirebaseFirestore.instance.collection('sos');
  static const _kMeuId = 'sos_meu_id';

  /// Todos os ativos: UM range no servidor (expireAt, igual police_alerts) e
  /// status no cliente. A coleção é minúscula; raio é filtrado por quem lê.
  static Stream<List<SosRequest>> streamAtivos() => _col
      .where('expireAt', isGreaterThan: Timestamp.now())
      .snapshots()
      .map((snap) => snap.docs
          .map(SosRequest.fromFirestore)
          .where((s) => s.ativo)
          .toList())
      .handleError((Object e, StackTrace st) => FieldLog.error('sos_stream', e, st));

  static Stream<SosRequest?> streamUm(String id) => _col
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? SosRequest.fromFirestore(d) : null)
      .handleError((Object e, StackTrace st) => FieldLog.error('sos_stream_um', e, st));

  /// Contato do outro lado (só existe depois do aceite; regra só deixa o
  /// próprio uid ler o seu). {nome, telefone}.
  static Stream<Map<String, String>?> streamContato(String sosId) async* {
    final uid = await AuthService.getUid();
    yield* _col
        .doc(sosId)
        .collection('contatos')
        .doc(uid)
        .snapshots()
        .map((d) => d.exists
            ? {
                'nome': d.data()!['nome'] as String? ?? '',
                'telefone': d.data()!['telefone'] as String? ?? '',
              }
            : null)
        .handleError((Object e, StackTrace st) => FieldLog.error('sos_contato', e, st));
  }

  /// Id do meu S.O.S. aberto nesta instalação (guardado local; o backend é
  /// quem garante "um por uid").
  static Future<String?> meuId() async =>
      (await SharedPreferences.getInstance()).getString(_kMeuId);

  static Future<void> limparMeuId() => _setMeuId(null);

  static Future<void> _setMeuId(String? id) async {
    final p = await SharedPreferences.getInstance();
    id == null ? await p.remove(_kMeuId) : await p.setString(_kMeuId, id);
  }

  /// [caminhao] e [cor] vêm do perfil de caminhão ATIVO, não do perfil do
  /// motorista: o backend não tem como saber qual caminhão está selecionado
  /// (isso vive no aparelho), e quem roda mais de um anunciava o veículo
  /// errado na ficha. O servidor confere tamanho e usa o que vem daqui.
  static Future<String> abrir({
    required double lat,
    required double lng,
    required SosTipo tipo,
    required String texto,
    required String caminhao,
    required String cor,
  }) async {
    final resp = await _post('/sos', {
      'lat': lat, 'lng': lng, 'tipo': tipo.name, 'texto': texto,
      'caminhao': caminhao, 'cor': cor,
    });
    final id = resp['id'] as String;
    await _setMeuId(id);
    FieldLog.event('sos_open', {'tipo': tipo.name, 'id': id});
    return id;
  }

  /// Devolve {nome, telefone} de quem pediu.
  static Future<Map<String, String>> aceitar(String id, {double? distKm}) async {
    final resp = await _post('/sos/$id/aceitar', const {});
    FieldLog.event('sos_accept', {'id': id, 'distKm': distKm?.round()});
    return {
      'nome': resp['nome'] as String? ?? '',
      'telefone': resp['telefone'] as String? ?? '',
    };
  }

  // Dono e ajudante mexem direto (regra limita os campos).
  static Future<void> resolver(String id, {required bool teveAjuda}) async {
    await _col.doc(id).update({'status': 'resolvido'});
    await _setMeuId(null);
    FieldLog.event('sos_resolve', {'id': id, 'teveAjuda': teveAjuda});
  }

  static Future<void> renovar(String id) => _col.doc(id).update({
        'expireAt': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 2))),
      });

  static Future<void> desistir(String id) => _col.doc(id).update({
        'status': 'aberto',
        'ajudanteUid': FieldValue.delete(),
        'ajudanteNome': FieldValue.delete(),
        'aceitoEm': FieldValue.delete(),
      });

  static Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    http.Response resp;
    try {
      resp = await http
          .post(Uri.parse('$backendUrl$path'),
              headers: {'Content-Type': 'application/json', ...await AuthService.getHeaders()},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 12));
    } catch (e, st) {
      FieldLog.error('sos_post', e, st);
      throw const SosException(SosFalha.rede);
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      json = const {};
    }
    if (resp.statusCode >= 200 && resp.statusCode < 300) return json;
    final key = json['error'] as String? ?? '';
    FieldLog.event('sos_refused', {'path': path, 'status': resp.statusCode, 'error': key});
    switch (key) {
      case 'perfil':
        throw const SosException(SosFalha.perfil);
      case 'google':
        throw const SosException(SosFalha.google);
      case 'conta_nova':
        throw SosException(SosFalha.contaNova,
            liberaEm: DateTime.tryParse(json['liberaEm'] as String? ?? ''));
      case 'ja_aberto':
        final id = json['id'] as String?;
        if (id != null) await _setMeuId(id);
        throw SosException(SosFalha.jaAberto, id: id);
      case 'expirado':
      case 'atendendo':
      case 'resolvido':
      case 'nao_existe':
        throw const SosException(SosFalha.expirado);
      case 'sem_contato':
        throw const SosException(SosFalha.semContato);
      default:
        throw const SosException(SosFalha.rede);
    }
  }
}
