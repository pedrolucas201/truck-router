import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'field_log.dart';

class AuthService {
  /// UM sign-in por processo. Sem isto, `ensureSignedIn()` (boot, unawaited) e
  /// os `getUid()`/`getHeaders()` lazy podiam ver `currentUser == null` ao mesmo
  /// tempo e disparar dois `signInAnonymously()` — dois usuários anônimos na
  /// mesma abertura. Suspeita (não provada) do drive 2026-09-02: uid trocando a
  /// cada cold start e 16 curadorias recusadas por uid do doc ≠ uid do token.
  static Future<void>? _signIn;

  /// Sign-in anônimo idempotente. Loga a falha (sem rede/sem auth) porque quando
  /// isto quebra, TUDO que é autenticado quebra junto (routing, restrictions e o
  /// próprio field_logs) e sem sinal ficaríamos totalmente às cegas.
  ///
  /// [from] = quem pediu ('boot' | 'lazy'). Vai no evento `auth_signin`, que só
  /// existe quando um usuário NOVO foi criado. `prev` é o último uid que ESTA
  /// instalação já teve (guardado por nós, fora do Firebase): vazio = instalação
  /// limpa, normal; preenchido = o Firebase Auth perdeu um usuário que existia
  /// — foi o que a 2.4.53 fez em 7 de 8 boots (medido no Auth em 08/09), e o
  /// plugin restaura o usuário nativo de forma síncrona no initializeApp, então
  /// não é corrida do Dart: sem este campo não há como separar reinstalação de
  /// perda no SDK.
  static Future<void> _ensureUser({String from = 'lazy'}) {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return Future.value();
    return _signIn ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final prev  = prefs.getString(_kLastUid) ?? '';
        final cred  = await auth.signInAnonymously();
        final uid   = cred.user?.uid ?? '';
        if (uid.isNotEmpty) await prefs.setString(_kLastUid, uid);
        FieldLog.event('auth_signin', {
          'from': from,
          'uid':  _short(uid),
          'prev': _short(prev),
        });
      } catch (e, st) {
        _signIn = null; // deixa a próxima chamada tentar de novo
        FieldLog.error('auth_signin', e, st);
        rethrow;
      }
    }();
  }

  /// Garante um usuário (anônimo) autenticado. Best-effort e silencioso: chamado
  /// no startup pra que QUALQUER caminho de navegação — inclusive o Histórico,
  /// que não passa por geocoding/routing (os gatilhos do login lazy) — já tenha
  /// auth. Sem isso, writes autenticados (field_logs, restrictions) tomam
  /// permission-denied silencioso.
  static Future<void> ensureSignedIn() async {
    // Boot best-effort: o login lazy (getUid/getHeaders) tenta de novo. O log
    // já saiu de dentro do _ensureUser.
    try {
      await _ensureUser(from: 'boot');
      // Usuário restaurado pelo SDK também conta como "último visto": é ele que
      // o `prev` do próximo auth_signin acusa como perdido.
      final uid = currentUid;
      if (uid != null) {
        (await SharedPreferences.getInstance()).setString(_kLastUid, uid);
      }
    } catch (_) {}
  }

  static const _kLastUid = 'auth_last_uid';
  static String _short(String uid) =>
      uid.isEmpty ? 'none' : uid.substring(0, uid.length < 6 ? uid.length : 6);

  static Future<String> getUid() async {
    await _ensureUser();
    return FirebaseAuth.instance.currentUser!.uid;
  }

  /// Uid que já está em memória, ou null se o sign-in não completou. Síncrono e
  /// sem lançar de propósito: serve pra telemetria, que não pode esperar login
  /// nem derrubar o caminho de quem a chama.
  static String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  static Future<Map<String, String>> getHeaders() async {
    await _ensureUser();
    final token = await FirebaseAuth.instance.currentUser!.getIdToken();
    return {'Authorization': 'Bearer $token'};
  }
}
