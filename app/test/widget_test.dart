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
    expect(find.text('FLOAT'), findsOneWidget);
    expect(find.text('Create your first note'), findsOneWidget);
  });

  testWidgets('saves a snippet without disposing the editor early', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const FloatApp());
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('NEW NOTE'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Portfolio');
    await tester.enterText(find.byType(TextField).at(1), 'https://example.com');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Portfolio'), findsOneWidget);
  });

  testWidgets('opens clipboard history in a modal', (tester) async {
    SharedPreferences.setMockInitialValues({
      'flutter.float.clipboard-history-enabled.v1': true,
      'flutter.float.clipboard-entries.v1':
          '[{"id":"clip-1","text":"Reusable answer","capturedAt":"2026-10-16T00:00:00.000"}]',
    });
    await tester.pumpWidget(const FloatApp());
    await tester.pump(const Duration(milliseconds: 150));

    await tester.tap(find.byTooltip('Latest pastes'));
    await tester.pumpAndSettle();

    expect(find.text('Reusable answer'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });
}
