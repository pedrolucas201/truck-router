import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/providers/theme_controller.dart';

/// Tema: Automático segue o relógio (o comportamento de sempre); Claro e
/// Escuro ignoram a hora.
void main() {
  final noite = DateTime(2026, 9, 26, 22);
  final dia = DateTime(2026, 9, 26, 10);

  test('automático: escuro das 18h às 6h', () {
    expect(ThemeController.temaPara(TemaEscolha.automatico, noite), ThemeMode.dark);
    expect(ThemeController.temaPara(TemaEscolha.automatico, dia), ThemeMode.light);
    expect(ThemeController.temaPara(TemaEscolha.automatico, DateTime(2026, 9, 26, 5, 59)), ThemeMode.dark);
    expect(ThemeController.temaPara(TemaEscolha.automatico, DateTime(2026, 9, 26, 6)), ThemeMode.light);
  });

  test('claro e escuro não dependem da hora', () {
    expect(ThemeController.temaPara(TemaEscolha.claro, noite), ThemeMode.light);
    expect(ThemeController.temaPara(TemaEscolha.escuro, dia), ThemeMode.dark);
  });
}
