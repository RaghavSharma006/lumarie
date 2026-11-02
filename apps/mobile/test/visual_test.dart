import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumairie/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> loadFonts() async {
    final text = FontLoader('LumairieSans')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('assets/fonts/MaterialIcons-Regular.otf'));
    await Future.wait([text.load(), icons.load()]);
  }

  testWidgets('home light visual', (tester) async {
    await loadFonts();
    SharedPreferences.setMockInitialValues({'demo': true, 'dark': false});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const LumairieApp());
    await tester.pumpAndSettle();
    await expectLater(find.byType(Scaffold).first,
        matchesGoldenFile('goldens/home_light.png'));
  });

  testWidgets('home dark visual', (tester) async {
    await loadFonts();
    SharedPreferences.setMockInitialValues({'demo': true, 'dark': true});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const LumairieApp());
    await tester.pumpAndSettle();
    await expectLater(find.byType(Scaffold).first,
        matchesGoldenFile('goldens/home_dark.png'));
  });

  for (final dark in [false, true]) {
    for (var page = 1; page <= 7; page++) {
      testWidgets('screen $page ${dark ? 'dark' : 'light'} visual',
          (tester) async {
        await loadFonts();
        SharedPreferences.setMockInitialValues({'demo': true, 'dark': dark});
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(LumairieApp(initialPage: page));
        await tester.pumpAndSettle();
        await expectLater(
            find.byType(Scaffold).first,
            matchesGoldenFile(
                'goldens/screen_${page}_${dark ? 'dark' : 'light'}.png'));
      });
    }
  }
}
