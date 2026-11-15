import 'dart:async';

import 'package:flutter/services.dart';

const qwenModelName = 'Qwen3 0.6B · INT4';

class LocalAiException implements Exception {
  final String message;
  const LocalAiException(this.message);
  @override
  String toString() => message;
}

class LocalModelStatus {
  final bool supported;
  final bool installed;
  final int modelBytes;
  final int partialBytes;
  final int freeBytes;

  const LocalModelStatus({
    this.supported = false,
    this.installed = false,
    this.modelBytes = 343490560,
    this.partialBytes = 0,
    this.freeBytes = 0,
  });

  factory LocalModelStatus.fromMap(Map<Object?, Object?> value) =>
      LocalModelStatus(
        supported: value['supported'] == true,
        installed: value['installed'] == true,
        modelBytes: (value['modelBytes'] as num?)?.toInt() ?? 343490560,
        partialBytes: (value['partialBytes'] as num?)?.toInt() ?? 0,
        freeBytes: (value['freeBytes'] as num?)?.toInt() ?? 0,
      );
}

abstract class LocalAiPlatform {
  Future<LocalModelStatus> status();
  Stream<Map<Object?, Object?>> get downloadProgress;
  Future<void> install();
  Future<void> remove();
  Future<void> cancel();
  Future<void> unload();
  Future<Map<Object?, Object?>> generate(Map<String, Object?> request);
}

class MethodChannelLocalAi implements LocalAiPlatform {
  static const _channel = MethodChannel('sora_weather/local_ai');
  static const _events = EventChannel('sora_weather/local_ai/progress');

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw const LocalAiException(
        'On-device AI is available in the Android build.',
      );
    } on PlatformException catch (error) {
      throw LocalAiException(
        error.message ?? 'The local model is unavailable.',
      );
    }
  }

  @override
  Future<LocalModelStatus> status() async {
    try {
      final value = await _call<Map<Object?, Object?>>('status');
      return LocalModelStatus.fromMap(value ?? {});
    } on LocalAiException {
      return const LocalModelStatus();
    }
  }

  @override
  Stream<Map<Object?, Object?>> get downloadProgress => _events
      .receiveBroadcastStream()
      .map((event) => Map<Object?, Object?>.from(event as Map));

  @override
  Future<void> install() => _call<void>('install');
  @override
  Future<void> remove() => _call<void>('remove');
  @override
  Future<void> cancel() => _call<void>('cancel');
  @override
  Future<void> unload() => _call<void>('unload');

  @override
  Future<Map<Object?, Object?>> generate(Map<String, Object?> request) async {
    try {
      return await _call<Map<Object?, Object?>>(
            'generate',
            request,
          ).timeout(const Duration(seconds: 50)) ??
          {};
    } on TimeoutException {
      unawaited(cancel().catchError((_) {}));
      throw const LocalAiException(
        'On-device AI timed out. Local picks are available.',
      );
    }
  }
}
