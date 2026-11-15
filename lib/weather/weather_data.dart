import 'dart:convert';

class WeatherPlace {
  final String name;
  final String region;
  final double latitude;
  final double longitude;
  const WeatherPlace(this.name, this.region, this.latitude, this.longitude);
  String get key => '$latitude,$longitude';
  Map<String, Object> toJson() => {
    'name': name,
    'region': region,
    'latitude': latitude,
    'longitude': longitude,
  };
  factory WeatherPlace.fromJson(Map<String, dynamic> j) => WeatherPlace(
    j['name'] as String,
    j['region'] as String? ?? '',
    (j['latitude'] as num).toDouble(),
    (j['longitude'] as num).toDouble(),
  );
}

double? reading(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;

class WeatherPayload {
  final Map<String, dynamic> json;
  final DateTime fetchedAt;
  final bool cached;
  const WeatherPayload(this.json, this.fetchedAt, {this.cached = false});
  Map<String, dynamic> get current =>
      (json['current'] as Map?)?.cast<String, dynamic>() ?? {};
  double? value(String key) => reading(current[key]);
  DateTime? get observedAt =>
      current['time'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
            (current['time'] as num).toInt() * 1000,
            isUtc: true,
          )
          : null;
  bool get stale =>
      cached ||
      observedAt == null ||
      DateTime.now().toUtc().difference(observedAt!) > const Duration(hours: 2);
  int get offset => (json['utc_offset_seconds'] as num?)?.toInt() ?? 0;
  List<Map<String, dynamic>> rows(String section) {
    final map = (json[section] as Map?)?.cast<String, dynamic>() ?? {};
    final times = map['time'] as List? ?? [];
    return List.generate(
      times.length,
      (i) => {
        for (final entry in map.entries)
          if (entry.value is List && (entry.value as List).length > i)
            entry.key: (entry.value as List)[i],
      },
    );
  }

  String encode() =>
      jsonEncode({'data': json, 'fetchedAt': fetchedAt.toIso8601String()});
  factory WeatherPayload.decode(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    return WeatherPayload(
      j['data'] as Map<String, dynamic>,
      DateTime.parse(j['fetchedAt'] as String),
      cached: true,
    );
  }
}

class WeatherBundle {
  final WeatherPlace place;
  final WeatherPayload? weather;
  final WeatherPayload? air;
  const WeatherBundle(this.place, {this.weather, this.air});
  double? get aqi => air?.value('us_aqi');
  double? get pm25 => air?.value('pm2_5');
}

String aqiCategory(double? aqi) {
  if (aqi == null || aqi < 0) return 'Unavailable';
  if (aqi <= 50) return 'Good';
  if (aqi <= 100) return 'Moderate';
  if (aqi <= 150) return 'Unhealthy for sensitive groups';
  if (aqi <= 200) return 'Unhealthy';
  if (aqi <= 300) return 'Very unhealthy';
  return 'Hazardous';
}

String conditionLabel(double? code) {
  if (code == null) return 'Conditions unavailable';
  final c = code.toInt();
  if (c == 0) return 'Clear skies';
  if (c <= 2) return 'A little cloudy';
  if (c == 3) return 'Cloudy skies';
  if (c == 45 || c == 48) return 'Misty skies';
  if (c >= 95) return 'Thunderstorms';
  if ((c >= 71 && c <= 77) || c == 85 || c == 86) return 'Snowfall';
  return 'Rainy skies';
}

class WeatherInsight {
  final String id;
  final String title;
  final String body;
  const WeatherInsight(this.id, this.title, this.body);
}

List<WeatherInsight> localInsights(WeatherBundle bundle, DateTime now) {
  final result = <WeatherInsight>[];
  final air = bundle.air;
  if (air != null && !air.stale && bundle.aqi != null) {
    final aqi = bundle.aqi!;
    result.add(
      WeatherInsight(
        'air',
        'A little air awareness',
        aqi > 100
            ? 'US AQI is ${aqi.round()} (${aqiCategory(aqi)}). Consider reducing strenuous outdoor activity, especially if you are sensitive to air pollution.'
            : 'US AQI is ${aqi.round()} (${aqiCategory(aqi)}). Check the hourly trend when planning time outside.',
      ),
    );
  }
  final weather = bundle.weather;
  if (weather != null && !weather.stale) {
    final upcoming = weather
        .rows('hourly')
        .where(
          (r) =>
              r['time'] is num &&
              (r['time'] as num) >= now.millisecondsSinceEpoch / 1000,
        )
        .take(12);
    final rain = upcoming.where(
      (r) => (reading(r['precipitation_probability']) ?? 0) >= 50,
    );
    if (rain.isNotEmpty) {
      final time = localTime(
        (rain.first['time'] as num).toInt(),
        weather.offset,
      );
      result.add(
        WeatherInsight(
          'rain',
          'An umbrella kind of day',
          'Rain probability reaches ${reading(rain.first['precipitation_probability'])!.round()}% around ${hourLabel(time)}. Pack an umbrella for your next outing.',
        ),
      );
    }
    final feels = weather.value('apparent_temperature');
    if (feels != null) {
      result.add(
        WeatherInsight(
          'comfort',
          'Dress for the feeling',
          'It feels like ${feels.round()}°C outside. ${feels < 18
              ? 'A cozy extra layer could be welcome.'
              : feels >= 30
              ? 'Light clothing may feel more comfortable.'
              : 'Pick something comfortable for your day.'}',
        ),
      );
    }
  }
  if (result.isEmpty) {
    result.add(
      const WeatherInsight(
        'waiting',
        'A moment for fresh data',
        'Connect and refresh to get insights from current weather and air-quality data. Cached readings are available below when saved.',
      ),
    );
  }
  return result;
}

DateTime localTime(int epoch, int offset) =>
    DateTime.fromMillisecondsSinceEpoch((epoch + offset) * 1000, isUtc: true);
String hourLabel(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
