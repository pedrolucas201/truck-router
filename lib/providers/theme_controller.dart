import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Escolha do motorista. Automático = escuro das 18h às 6h (o comportamento
/// de sempre, e o padrão pra quem nunca mexeu).
enum TemaEscolha { automatico, claro, escuro }

/// Tema do app e do mapa. O [value] é o que está valendo agora; a [escolha]
/// é o que o motorista pediu no menu (salva no aparelho).
class ThemeController extends ValueNotifier<ThemeMode> {
  static const _kEscolha = 'tema_escolha';
  Timer? _timer;
  TemaEscolha _escolha = TemaEscolha.automatico;

  ThemeController() : super(temaPara(TemaEscolha.automatico, DateTime.now())) {
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _aplica());
    unawaited(_carrega());
  }

  TemaEscolha get escolha => _escolha;
  bool get isNight => value == ThemeMode.dark;

  /// Puro, pra teste: o tema que vale pra [escolha] na hora [agora].
  static ThemeMode temaPara(TemaEscolha escolha, DateTime agora) => switch (escolha) {
        TemaEscolha.claro => ThemeMode.light,
        TemaEscolha.escuro => ThemeMode.dark,
        TemaEscolha.automatico => (agora.hour >= 18 || agora.hour < 6) ? ThemeMode.dark : ThemeMode.light,
      };

  Future<void> _carrega() async {
    try {
      final p = await SharedPreferences.getInstance();
      final salvo = p.getString(_kEscolha);
      _escolha = TemaEscolha.values.firstWhere((e) => e.name == salvo, orElse: () => TemaEscolha.automatico);
      _aplica();
    } catch (_) {/* sem prefs: segue automático */}
  }

  Future<void> escolher(TemaEscolha e) async {
    _escolha = e;
    _aplica();
    notifyListeners(); // a escolha mudou mesmo se o tema vigente não mudou
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kEscolha, e.name);
    } catch (_) {}
  }

  void _aplica() => value = temaPara(_escolha, DateTime.now());

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
