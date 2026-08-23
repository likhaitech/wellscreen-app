import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('WellScreen app starts and moves to login screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const WellScreenApp());

    expect(find.text('WellScreen'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(
      find.text('Digital wellness monitoring for parents and children'),
      findsOneWidget,
    );

    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Parent / Guardian'), findsOneWidget);

    // The Create Account button is lower in the scrollable login screen.
    await tester.drag(find.byType(ListView), const Offset(0, -400));

    await tester.pumpAndSettle();

    expect(find.text('Create Account'), findsOneWidget);
  });
}
