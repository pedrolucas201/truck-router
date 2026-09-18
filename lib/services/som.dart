import 'dart:async';

import 'package:flutter/services.dart';

/// Marca no início de uma fala da navegação: "toca a buzina e depois fala".
/// Vai DENTRO do texto de propósito: assim buzina + fala entram juntas na fila
/// de voz (VoiceQueue) e nunca atropelam uma manobra que está sendo falada.
const kBuzina = '';

/// "fom fom" do S.O.S. (res/raw/buzina, tocado pela MainActivity no mesmo uso
/// de áudio da voz do guia). Termina quando o som termina; qualquer falha
/// termina na hora: a fala que vem depois nunca espera uma buzina que não toca.
class Som {
  Som._();
  static const _ch = MethodChannel('notrecho/som');

  static Future<void> buzina() async {
    try {
      await _ch.invokeMethod<bool>('buzina').timeout(const Duration(seconds: 3));
    } catch (_) {}
  }
}
