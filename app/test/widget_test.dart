import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:float_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows the local snippet empty state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const FloatApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Float'), findsOneWidget);
    expect(find.text('Create your first snippet'), findsOneWidget);
  });

  testWidgets('saves a snippet without disposing the editor early', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const FloatApp());
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Portfolio');
    await tester.enterText(find.byType(TextField).at(1), 'https://example.com');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Portfolio'), findsOneWidget);
  });
}
