import 'package:firebase_auth/firebase_auth.dart';
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
  /// existe quando um usuário NOVO foi criado: um por cold start = a persistência
  /// do Firebase Auth não está restaurando o usuário nesse device.
  static Future<void> _ensureUser({String from = 'lazy'}) {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return Future.value();
    return _signIn ??= () async {
      try {
        final cred = await auth.signInAnonymously();
        FieldLog.event('auth_signin', {
          'from': from,
          'uid': cred.user?.uid.substring(0, 6) ?? 'none',
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
    } catch (_) {}
  }

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
