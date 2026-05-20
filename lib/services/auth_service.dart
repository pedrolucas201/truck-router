import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  static Future<String> getUid() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
    return auth.currentUser!.uid;
  }
}
