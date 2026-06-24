import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';

void main() {
  testWidgets('WellScreen app starts and moves to login screen', (
      WidgetTester tester,
      ) async {
    await tester.pumpWidget(const WellScreenApp());

    expect(find.text('WellScreen'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to WellScreen'), findsOneWidget);
  });
}