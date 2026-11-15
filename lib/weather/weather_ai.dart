import 'dart:convert';
import '../data/ai/local_ai_platform.dart';
import 'weather_data.dart';

/// The model can select a grounded insight; it cannot author new forecast facts.
Future<String?> chooseLocalInsight(
  LocalAiPlatform platform,
  List<WeatherInsight> insights,
) async {
  final status = await platform.status();
  if (!status.supported || !status.installed || insights.length < 2) {
    return null;
  }
  final response = await platform.generate({
    'task': 'rank',
    'system':
        'Choose the most useful weather insight from the supplied facts. Prioritize unhealthy air, then rain. Return only its id using the JSON schema.',
    'prompt': jsonEncode(
      insights.map((i) => {'id': i.id, 'text': i.body}).toList(),
    ),
    'schema': jsonEncode({
      'type': 'object',
      'properties': {
        'id': {'type': 'string', 'enum': insights.map((i) => i.id).toList()},
      },
      'required': ['id'],
      'additionalProperties': false,
    }),
  });
  final decoded =
      jsonDecode(response['text'] as String) as Map<String, dynamic>;
  final id = decoded['id'];
  return insights.any((i) => i.id == id) ? id as String : null;
}
