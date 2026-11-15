import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sora_weather/appearance.dart';
import 'package:sora_weather/main.dart';
import 'package:sora_weather/weather/weather_api.dart';

void main() {
  test(
    'appearance persists and reloads light, dark and system modes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final appearance = SoraAppearance(preferences);
      expect(appearance.value, ThemeMode.system);
      for (final mode in ThemeMode.values) {
        await appearance.setMode(mode);
        expect(SoraAppearance(preferences).value, mode);
      }
      appearance.dispose();
    },
  );
  testWidgets('theme selector applies dark mode and preserves it on relaunch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('sora_weather/local_ai'),
          (_) async => <String, Object>{'supported': false},
        );
    final preferences = await SharedPreferences.getInstance();
    final api = SoraWeatherApi(
      MockClient((_) async => http.Response('{}', 503)),
      preferences,
    );
    await tester.pumpWidget(SoraWeatherApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Appearance and AI settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('theme-dark')));
    await tester.tap(find.byKey(const ValueKey('theme-dark')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(preferences.getString('sora.theme'), 'dark');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(SoraWeatherApp(api: api));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
