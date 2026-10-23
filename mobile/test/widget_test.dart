import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('Amar Hisab app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const AmarHisabApp());
    expect(find.byType(AmarHisabApp), findsOneWidget);
  });
}
