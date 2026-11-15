import 'weather_data.dart';

String dayKey(DateTime date) => date.toIso8601String().substring(0, 10);

class ForecastDay {
  final int index;
  final Map<String, dynamic> daily;
  final WeatherPayload weather;
  const ForecastDay(this.index, this.daily, this.weather);
  bool get isCurrent => index == 0;
  DateTime get date => localTime(
    (daily['time'] as num?)?.toInt() ??
        (weather.current['time'] as num?)?.toInt() ??
        0,
    weather.offset,
  );
  String get label {
    final now = DateTime.now().toUtc().add(Duration(seconds: weather.offset));
    if (dayKey(date) == dayKey(now)) return 'Today';
    if (dayKey(date) == dayKey(now.add(const Duration(days: 1)))) {
      return 'Tomorrow';
    }
    return const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ][date.weekday - 1];
  }

  String get shortDate =>
      '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][date.month - 1]} ${date.day}';
  double? get code =>
      isCurrent
          ? weather.value('weather_code')
          : reading(daily['weather_code']);
  double? get temperature =>
      isCurrent
          ? weather.value('temperature_2m')
          : reading(daily['temperature_2m_max']);
  double? get high => reading(daily['temperature_2m_max']);
  double? get low => reading(daily['temperature_2m_min']);
  double? get rain => reading(daily['precipitation_probability_max']);
  bool get night => isCurrent && weather.value('is_day') == 0;
  List<Map<String, dynamic>> get hours =>
      weather
          .rows('hourly')
          .where(
            (r) =>
                r['time'] is num &&
                dayKey(localTime((r['time'] as num).toInt(), weather.offset)) ==
                    dayKey(date),
          )
          .toList();
  List<Map<String, dynamic>> airHours(WeatherPayload? air) =>
      (air?.rows('hourly') ?? <Map<String, dynamic>>[])
          .where(
            (r) =>
                r['time'] is num &&
                dayKey(localTime((r['time'] as num).toInt(), weather.offset)) ==
                    dayKey(date),
          )
          .toList();
  double? peakAir(WeatherPayload? air, String key) {
    final values =
        airHours(air).map((r) => reading(r[key])).whereType<double>();
    return values.isEmpty ? null : values.reduce((a, b) => a > b ? a : b);
  }

  String get artwork {
    if (code != null &&
        ((code! >= 71 && code! <= 77) || code == 85 || code == 86)) {
      return 'snow';
    }
    if (code != null && code! >= 51) return 'rain';
    if (night) return 'night';
    if (code != null && code! >= 3) return 'cloudy';
    return 'clear';
  }
}

List<ForecastDay> forecastDays(WeatherPayload? weather) {
  if (weather == null) return [];
  final rows = weather.rows('daily').where((r) => r['time'] is num).toList();
  if (rows.isEmpty) return [ForecastDay(0, const {}, weather)];
  return [
    for (var i = 0; i < rows.length; i++) ForecastDay(i, rows[i], weather),
  ];
}
