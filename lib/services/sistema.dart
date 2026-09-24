import 'package:flutter/services.dart';

/// Coisas do aparelho que nenhum plugin instalado expõe: fabricante e a tela
/// de "início automático" da MIUI. Canal minúsculo na MainActivity, sem
/// dependência nova. Falhou = comportamento neutro (não é Xiaomi / não abriu).
class Sistema {
  static const _ch = MethodChannel('notrecho/sistema');

  static Future<String> fabricante() async {
    try {
      return (await _ch.invokeMethod<String>('fabricante') ?? '').toLowerCase();
    } catch (_) {
      return '';
    }
  }

  static Future<bool> ehXiaomi() async {
    final f = await fabricante();
    return f.contains('xiaomi') || f.contains('redmi') || f.contains('poco');
  }

  /// Abre a tela de início automático da MIUI. False = não existe neste aparelho.
  static Future<bool> abrirInicioAutomatico() async {
    try {
      return await _ch.invokeMethod<bool>('abrirAutostart') ?? false;
    } catch (_) {
      return false;
    }
  }
}
