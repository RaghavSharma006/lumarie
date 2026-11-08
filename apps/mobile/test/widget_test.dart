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

  testWidgets('real frame QR action stays visible with Demo Mode off',
      (tester) async {
    SharedPreferences.setMockInitialValues({'demo': false, 'dark': false});
    await tester.pumpWidget(const LumairieApp(initialPage: 5));
    await tester.pumpAndSettle();
    final scan = find.text('Scan frame QR code');
    expect(scan, findsOneWidget);
    expect(find.text('Open demo frame'), findsNothing);
    expect(
        tester.getBottomLeft(scan).dy,
        lessThan(
            tester.view.physicalSize.height / tester.view.devicePixelRatio));
  });
}
