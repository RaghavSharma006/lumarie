import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumairie/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('home opens profile and switches theme', (tester) async {
    SharedPreferences.setMockInitialValues({'demo': true, 'dark': false});
    await tester.pumpWidget(const LumairieApp());
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets);
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Local settings'), findsOneWidget);
    await tester.tap(find.text('Dark mode'));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsWidgets);
  });
}
