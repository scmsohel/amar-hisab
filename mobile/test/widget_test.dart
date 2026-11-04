import 'package:flutter_test/flutter_test.dart';
import 'package:amar_hisab_mobile/main.dart';

void main() {
  testWidgets('Amar Hisab app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const AmarHisabApp());
    expect(find.byType(AmarHisabApp), findsOneWidget);

    // Let the splash delay and initial route transition complete.
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pump(const Duration(milliseconds: 500));
  });
}
