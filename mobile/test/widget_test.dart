import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amar_hisab_mobile/main.dart';

void main() {
  testWidgets('Amar Hisab app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const AmarHisabApp());
    expect(find.byType(AmarHisabApp), findsOneWidget);

    // Dispose the splash screen before its delayed navigation fires.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}
