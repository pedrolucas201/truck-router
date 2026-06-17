import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truck_router/widgets/delayed_appearance.dart';

void main() {
  testWidgets('mostra o filho só depois do delay', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DelayedAppearance(
        delay: Duration(milliseconds: 150),
        child: Text('pronto'),
      ),
    ));

    expect(find.text('pronto'), findsNothing); // 0 ms
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('pronto'), findsNothing); // 100 ms
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('pronto'), findsOneWidget); // 160 ms
  });
}
