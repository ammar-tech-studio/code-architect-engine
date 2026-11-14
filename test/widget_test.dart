import 'package:flutter_test/flutter_test.dart';
import 'package:code_architect_engine/main.dart';

void main() {
  testWidgets('CodeArchitectApp renders dashboard tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const CodeArchitectApp());

    expect(find.text('Code Architect Engine'), findsOneWidget);
    expect(find.text('الذاكرة'), findsOneWidget);
    expect(find.text('تكليف'), findsOneWidget);
    expect(find.text('السحابة'), findsOneWidget);
    expect(find.text('الإعدادات'), findsOneWidget);
  });
}
