import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SoraAppearance extends ValueNotifier<ThemeMode> {
  final SharedPreferences preferences;
  SoraAppearance(this.preferences) : super(_read(preferences));
  static ThemeMode _read(SharedPreferences preferences) => switch (preferences
      .getString('sora.theme')) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
  Future<void> setMode(ThemeMode mode) async {
    value = mode;
    await preferences.setString('sora.theme', mode.name);
  }
}

class AppearanceScope extends InheritedNotifier<SoraAppearance> {
  const AppearanceScope({
    super.key,
    required SoraAppearance appearance,
    required super.child,
  }) : super(notifier: appearance);
  static SoraAppearance of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()!.notifier!;
}

ThemeData soraTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF536AE5),
    brightness: brightness,
    surface: dark ? const Color(0xFF14223A) : const Color(0xFFF1F5FF),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'Inter',
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: ThemeData(brightness: brightness).textTheme.apply(
      fontFamily: 'Inter',
      bodyColor: dark ? const Color(0xFFF1F1FF) : const Color(0xFF263552),
      displayColor: dark ? const Color(0xFFF1F1FF) : const Color(0xFF263552),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? const Color(0xFF1D2A45) : const Color(0xFFF5F3FF),
      showDragHandle: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );
}
