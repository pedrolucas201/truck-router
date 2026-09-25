import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Orçamento das ilustrações do onboarding (spec 2026-09-24): 2 MB somados.
/// O APK já tem 63 MB; cena a 1024 px em WebP q82 fica em ~60-90 KB cada.
void main() {
  test('ilustrações do onboarding cabem em 2 MB', () {
    final dir = Directory('assets/onboarding');
    final total = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.webp'))
        .fold<int>(0, (soma, f) => soma + f.lengthSync());
    expect(total, lessThanOrEqualTo(2 * 1024 * 1024), reason: 'total = $total bytes');
  });
}
