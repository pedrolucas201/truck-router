import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => android;

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDpIHXipKEPIF7Gdl08HWReF8tIJ7LXHYY',
    appId: '1:730093721780:android:ff70554973740ecc515fe1',
    messagingSenderId: '730093721780',
    projectId: 'truck-router1',
    storageBucket: 'truck-router1.firebasestorage.app',
  );
}
