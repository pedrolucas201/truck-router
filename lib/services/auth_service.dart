import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  /// Garante um usuário (anônimo) autenticado. Best-effort e silencioso: chamado
  /// no startup pra que QUALQUER caminho de navegação — inclusive o Histórico,
  /// que não passa por geocoding/routing (os gatilhos do login lazy) — já tenha
  /// auth. Sem isso, writes autenticados (field_logs, restrictions) tomam
  /// permission-denied silencioso.
  static Future<void> ensureSignedIn() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (_) {
      // Sem rede/sem auth agora: o login lazy (getUid/getHeaders) tenta de novo.
    }
  }

  static Future<String> getUid() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
    return auth.currentUser!.uid;
  }

  static Future<Map<String, String>> getHeaders() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
    final token = await auth.currentUser!.getIdToken();
    return {'Authorization': 'Bearer $token'};
  }
}
