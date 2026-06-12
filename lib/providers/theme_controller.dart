import 'dart:async';
import 'package:flutter/material.dart';

class ThemeController extends ValueNotifier<ThemeMode> {
  Timer? _timer;

  ThemeController() : super(_compute()) {
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      value = _compute();
    });
  }

  bool get isNight => value == ThemeMode.dark;

  static ThemeMode _compute() {
    final h = DateTime.now().hour;
    return (h >= 18 || h < 6) ? ThemeMode.dark : ThemeMode.light;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
