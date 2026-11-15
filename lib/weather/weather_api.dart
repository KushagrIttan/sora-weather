import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'weather_data.dart';

/// Independent endpoints and caches: a failed AQ request never hides weather.
class SoraWeatherApi {
  final http.Client client;
  final SharedPreferences preferences;
  SoraWeatherApi(this.client, this.preferences);

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final response = await client.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const FormatException('Weather provider unavailable');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['error'] == true) {
      throw const FormatException('Invalid provider response');
    }
    return json;
  }

  Future<List<WeatherPlace>> search(String query) async {
    if (query.trim().length < 2) return [];
    final json = await _get(
      Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': query.trim(),
        'count': '6',
        'language': 'en',
        'format': 'json',
      }),
    );
    return (json['results'] as List? ?? [])
        .map(
          (r) => WeatherPlace(
            r['name'] as String,
            [r['admin1'], r['country']].whereType<String>().toSet().join(', '),
            (r['latitude'] as num).toDouble(),
            (r['longitude'] as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<WeatherBundle> load(WeatherPlace place) async {
    final common = {
      'latitude': '${place.latitude}',
      'longitude': '${place.longitude}',
      'timezone': 'auto',
      'timeformat': 'unixtime',
    };
    final results = await Future.wait([
      _loadPart(
        'weather',
        place,
        Uri.https('api.open-meteo.com', '/v1/forecast', {
          ...common,
          'current':
              'temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day',
          'hourly': 'temperature_2m,weather_code,precipitation_probability',
          'daily':
              'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max,uv_index_max',
          'forecast_days': '7',
        }),
      ),
      _loadPart(
        'air',
        place,
        Uri.https('air-quality-api.open-meteo.com', '/v1/air-quality', {
          ...common,
          'current': 'us_aqi,pm2_5,pm10,nitrogen_dioxide,ozone',
          'hourly': 'us_aqi,pm2_5',
          'forecast_days': '2',
        }),
      ),
    ]);
    return WeatherBundle(place, weather: results[0], air: results[1]);
  }

  Future<WeatherPayload?> _loadPart(
    String kind,
    WeatherPlace place,
    Uri uri,
  ) async {
    final key = 'sora.$kind.${place.key}';
    try {
      final json = await _get(uri);
      final current = json['current'];
      if (current is! Map || current['time'] is! num) {
        throw const FormatException('Missing current data');
      }
      final payload = WeatherPayload(json, DateTime.now().toUtc());
      try {
        await preferences.setString(key, payload.encode());
      } catch (_) {
        /* Fresh data remains usable if storage is full. */
      }
      return payload;
    } catch (_) {
      try {
        final saved = preferences.getString(key);
        return saved == null ? null : WeatherPayload.decode(saved);
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> savePlace(WeatherPlace place) async {
    await preferences.setString('sora.place', jsonEncode(place.toJson()));
  }

  WeatherPlace? savedPlace() {
    try {
      final value = preferences.getString('sora.place');
      return value == null
          ? null
          : WeatherPlace.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
