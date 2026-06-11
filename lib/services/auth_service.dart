import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
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
