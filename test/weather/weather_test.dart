import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sora_weather/main.dart';
import 'package:sora_weather/weather/weather_api.dart';
import 'package:sora_weather/weather/weather_data.dart';

const place = WeatherPlace('Kolkata', 'West Bengal, India', 22.57, 88.36);
Map<String, Object?> weatherJson() {
  final time = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  return {
    'utc_offset_seconds': 19800,
    'current': {
      'time': time,
      'temperature_2m': 27.3,
      'apparent_temperature': 29,
      'weather_code': 1,
      'wind_speed_10m': 8,
      'relative_humidity_2m': 65,
      'is_day': 1,
    },
    'hourly': {
      'time': [time, time + 3600, time + 7200],
      'temperature_2m': [27, 28, 26],
      'precipitation_probability': [10, 70, 80],
      'weather_code': [1, 61, 61],
    },
    'daily': {
      'time': [time, time + 86400],
      'temperature_2m_max': [29, 30],
      'temperature_2m_min': [21, 22],
      'weather_code': [1, 2],
    },
  };
}

Map<String, Object?> airJson({bool missing = false}) {
  final time = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  return {
    'utc_offset_seconds': 19800,
    'current': {
      'time': time,
      'us_aqi': missing ? null : 132,
      'pm2_5': missing ? null : 48.2,
      'pm10': 70,
      'ozone': 34,
      'nitrogen_dioxide': 12,
    },
    'hourly': {
      'time': [time, time + 3600],
      'us_aqi': [132, 128],
      'pm2_5': [48.2, 46.1],
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await inter.load();
    await icons.load();
  });
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  test(
    'weather and AQ requests carry PM2.5, coordinates and UNIX times',
    () async {
      final client = MockClient((r) async {
        expect(r.url.queryParameters['latitude'], '22.57');
        expect(r.url.queryParameters['timeformat'], 'unixtime');
        if (r.url.host.startsWith('air-quality')) {
          expect(r.url.queryParameters['current'], contains('pm2_5'));
          return http.Response(jsonEncode(airJson()), 200);
        }
        return http.Response(jsonEncode(weatherJson()), 200);
      });
      final result = await SoraWeatherApi(client, prefs).load(place);
      expect(result.pm25, 48.2);
      expect(result.aqi, 132);
      expect(result.weather!.value('temperature_2m'), 27.3);
      expect(result.air!.cached, false);
    },
  );
  test(
    'AQ failure preserves weather; offline fallback is marked cached',
    () async {
      var failAir = false;
      final client = MockClient((r) async {
        if (r.url.host.startsWith('air-quality')) {
          return http.Response(
            failAir ? '{}' : jsonEncode(airJson()),
            failAir ? 503 : 200,
          );
        }
        return http.Response(jsonEncode(weatherJson()), 200);
      });
      final api = SoraWeatherApi(client, prefs);
      await api.load(place);
      failAir = true;
      final result = await api.load(place);
      expect(result.air!.cached, true);
      expect(result.weather!.cached, false);
      expect(result.pm25, 48.2);
      expect(
        localInsights(result, DateTime.now()).any((i) => i.id == 'air'),
        false,
      );
      final other = await api.load(
        const WeatherPlace('Tokyo', 'Japan', 35.6, 139.6),
      );
      expect(other.air, isNull);
      expect(other.weather, isNotNull);
    },
  );
  test(
    'missing pollution is not zero; AQI boundaries and location time',
    () async {
      final api = SoraWeatherApi(
        MockClient(
          (r) async => http.Response(
            jsonEncode(
              r.url.host.startsWith('air-quality')
                  ? airJson(missing: true)
                  : weatherJson(),
            ),
            200,
          ),
        ),
        prefs,
      );
      final b = await api.load(place);
      expect(b.pm25, isNull);
      expect(b.aqi, isNull);
      expect(aqiCategory(null), 'Unavailable');
      expect(aqiCategory(50), 'Good');
      expect(aqiCategory(51), 'Moderate');
      expect(aqiCategory(151), 'Unhealthy');
      expect(aqiCategory(301), 'Hazardous');
      expect(hourLabel(localTime(0, 19800)), '05:30');
    },
  );
  test('city search preserves disambiguating region', () async {
    final api = SoraWeatherApi(
      MockClient((r) async {
        expect(r.url.host, 'geocoding-api.open-meteo.com');
        expect(r.url.queryParameters['name'], 'Kolkata');
        return http.Response(
          jsonEncode({
            'results': [
              {
                'name': 'Kolkata',
                'admin1': 'West Bengal',
                'country': 'India',
                'latitude': 22.57,
                'longitude': 88.36,
              },
            ],
          }),
          200,
        );
      }),
      prefs,
    );
    final result = await api.search(' Kolkata ');
    expect(result.single.region, 'West Bengal, India');
  });
  for (final width in [360.0, 1100.0]) {
    testWidgets('live dashboard renders at width $width and toggles units', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = MockClient(
        (r) async => http.Response(
          jsonEncode(
            r.url.host.startsWith('air-quality') ? airJson() : weatherJson(),
          ),
          200,
        ),
      );
      final api = SoraWeatherApi(client, prefs);
      await api.savePlace(place);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: key, child: SoraWeatherApp(api: api)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Kolkata'), findsOneWidget);
      expect(find.text('PM2.5  48.2 µg/m³'), findsOneWidget);
      expect(find.text('27°C'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (width == 1100 && const bool.fromEnvironment('SORA_PREVIEW')) {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/sora-weather-preview.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.byTooltip('Toggle Celsius and Fahrenheit'));
      await tester.pumpAndSettle();
      expect(find.text('81°F'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-650, 0));
      await tester.pumpAndSettle();
      expect(find.text('86°F'), findsOneWidget);
      expect(find.text('DAILY FORECAST'), findsWidgets);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Next day',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();
      expect(find.text('81°F'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('first launch starts with city search and no invented weather', (
    tester,
  ) async {
    final api = SoraWeatherApi(
      MockClient((_) async => http.Response('{}', 500)),
      prefs,
    );
    await tester.pumpWidget(SoraWeatherApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('Find my city'), findsOneWidget);
    expect(find.text('A sky worth\nstepping into.'), findsOneWidget);
    await tester.ensureVisible(find.text('Find my city'));
    await tester.tap(find.text('Find my city'));
    await tester.pumpAndSettle();
    expect(find.text('City or postal code'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
