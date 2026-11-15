import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'appearance.dart';
import 'weather/weather_api.dart';
import 'weather/weather_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(SoraWeatherApp(api: SoraWeatherApi(http.Client(), preferences)));
}

class SoraWeatherApp extends StatefulWidget {
  final SoraWeatherApi api;
  const SoraWeatherApp({super.key, required this.api});
  @override
  State<SoraWeatherApp> createState() => _SoraWeatherAppState();
}

class _SoraWeatherAppState extends State<SoraWeatherApp> {
  late final SoraAppearance appearance = SoraAppearance(widget.api.preferences);
  @override
  void dispose() {
    appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppearanceScope(
    appearance: appearance,
    child: ListenableBuilder(
      listenable: appearance,
      builder:
          (context, _) => MaterialApp(
            title: 'Sora Weather',
            debugShowCheckedModeBanner: false,
            theme: soraTheme(Brightness.light),
            darkTheme: soraTheme(Brightness.dark),
            themeMode: appearance.value,
            home: WeatherScreen(api: widget.api),
          ),
    ),
  );
}
