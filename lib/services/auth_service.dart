import 'package:firebase_auth/firebase_auth.dart';
import 'field_log.dart';

class AuthService {
  /// Sign-in anônimo idempotente. Loga a falha (sem rede/sem auth) porque quando
  /// isto quebra, TUDO que é autenticado quebra junto (routing, restrictions e o
  /// próprio field_logs) e sem sinal ficaríamos totalmente às cegas.
  static Future<void> _ensureUser() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return;
    try {
      await auth.signInAnonymously();
    } catch (e, st) {
      FieldLog.error('auth_signin', e, st);
      rethrow;
    }
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
      await _ensureUser();
    } catch (_) {}
  }

  static Future<String> getUid() async {
    await _ensureUser();
    return FirebaseAuth.instance.currentUser!.uid;
  }

  static Future<Map<String, String>> getHeaders() async {
    await _ensureUser();
    final token = await FirebaseAuth.instance.currentUser!.getIdToken();
    return {'Authorization': 'Bearer $token'};
  }
}
