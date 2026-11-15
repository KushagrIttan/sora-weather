import 'package:flutter_test/flutter_test.dart';
import 'package:sora_weather/weather/forecast_day.dart';
import 'package:sora_weather/weather/weather_data.dart';

void main() {
  final start = DateTime.utc(2026, 11, 15).millisecondsSinceEpoch ~/ 1000;
  WeatherPayload payload() => WeatherPayload({
    'utc_offset_seconds': 19800,
    'current': {
      'time': start,
      'temperature_2m': 24,
      'weather_code': 0,
      'is_day': 0,
    },
    'daily': {
      'time': [start, start + 86400, start + 172800],
      'temperature_2m_max': [28, 30, 9],
      'temperature_2m_min': [20, 21, 1],
      'weather_code': [0, 61, 73],
      'precipitation_probability_max': [10, 85, 60],
    },
    'hourly': {
      'time': [start, start + 86400, start + 90000, start + 172800],
      'temperature_2m': [24, 25, 27, 8],
    },
  }, DateTime.now());
  test(
    'daily cards use current reading first and forecast highs after that',
    () {
      final days = forecastDays(payload());
      expect(days.length, 3);
      expect(days[0].temperature, 24);
      expect(days[1].temperature, 30);
      expect(days[1].low, 21);
      expect(days[1].rain, 85);
      expect(days[1].hours.map((r) => r['temperature_2m']), [25, 27]);
      expect(days[2].hours.single['temperature_2m'], 8);
    },
  );
  test(
    'day-specific art follows nighttime, rain, snow and cloud conditions',
    () {
      final days = forecastDays(payload());
      expect(days[0].artwork, 'night');
      expect(days[1].artwork, 'rain');
      expect(days[2].artwork, 'snow');
      expect(
        ForecastDay(1, {'time': start, 'weather_code': 3}, payload()).artwork,
        'cloudy',
      );
    },
  );
  test(
    'air forecast is aligned to each day and does not repeat past coverage',
    () {
      final air = WeatherPayload({
        'hourly': {
          'time': [start, start + 86400, start + 90000],
          'us_aqi': [100, 80, 90],
          'pm2_5': [30, 20, 25],
        },
      }, DateTime.now());
      final days = forecastDays(payload());
      expect(days[1].peakAir(air, 'us_aqi'), 90);
      expect(days[1].peakAir(air, 'pm2_5'), 25);
      expect(days[2].peakAir(air, 'us_aqi'), isNull);
      expect(days[2].peakAir(air, 'pm2_5'), isNull);
    },
  );
  test('missing daily arrays still allow a single current card', () {
    final weather = WeatherPayload({
      'current': {'time': start, 'temperature_2m': 24},
    }, DateTime.now());
    expect(forecastDays(weather).length, 1);
    expect(forecastDays(null), isEmpty);
  });
}
