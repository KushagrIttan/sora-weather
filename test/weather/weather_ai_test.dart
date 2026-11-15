import 'package:flutter_test/flutter_test.dart';
import 'package:sora_weather/data/ai/local_ai_platform.dart';
import 'package:sora_weather/weather/weather_ai.dart';
import 'package:sora_weather/weather/weather_data.dart';

class FakeWeatherModel implements LocalAiPlatform {
  bool installed = true;
  String response = '{"id":"air"}';
  int calls = 0;
  @override
  Future<LocalModelStatus> status() async =>
      LocalModelStatus(supported: true, installed: installed);
  @override
  Future<Map<Object?, Object?>> generate(Map<String, Object?> request) async {
    calls++;
    expect(request['task'], 'rank');
    expect(request['prompt'], contains('Rain at 16:00'));
    expect(request['schema'], contains('additionalProperties'));
    return {'text': response};
  }

  @override
  Stream<Map<Object?, Object?>> get downloadProgress => const Stream.empty();
  @override
  Future<void> cancel() async {}
  @override
  Future<void> install() async {}
  @override
  Future<void> remove() async {}
  @override
  Future<void> unload() async {}
}

void main() {
  const insights = [
    WeatherInsight('air', 'Air', 'US AQI 120'),
    WeatherInsight('rain', 'Rain', 'Rain at 16:00'),
  ];
  test('model selects only an existing grounded insight', () async {
    final model = FakeWeatherModel();
    expect(await chooseLocalInsight(model, insights), 'air');
    model.response = '{"id":"invented_forecast"}';
    expect(await chooseLocalInsight(model, insights), isNull);
  });
  test('missing model avoids inference and retains rule fallback', () async {
    final model = FakeWeatherModel()..installed = false;
    expect(await chooseLocalInsight(model, insights), isNull);
    expect(model.calls, 0);
  });
}
