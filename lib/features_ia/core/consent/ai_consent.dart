// What the user let the AI receive (T002, round 3). Owner: f3-consent.
// Each AI function asks once; the answer is kept per function and per destination (provider and host).
// A change of provider or host forgets every answer, and so does revoking one function in the settings.
import 'dart:convert';
import 'dart:io';

import 'package:monekin/features_ia/core/ai/ai_client.dart';
import 'package:monekin/features_ia/core/ai/ai_service_impl.dart';
import 'package:path_provider/path_provider.dart';

/// The functions that send something to the AI provider.
enum AiFeature { receipt, statement, notice, insights, recategorize }

/// The settings of the AI service in use, or the default preset when the real service is not installed (tests).
Future<AiProviderConfig> currentAiConfig() async {
  final service = AiService.instance;
  return service is AiServiceImpl
      ? service.loadConfig()
      : aiPresets[AiProviderId.gemini]!;
}

/// Provider and origin (scheme, host, port) a consent was given for.
String aiDestinationOf(AiProviderConfig config) {
  final uri = Uri.tryParse(config.baseUrl.trim());
  final origin = uri == null || uri.host.isEmpty
      ? ''
      : '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}:${uri.port}';
  return '${config.provider.name}|$origin';
}

class AiConsent {
  AiConsent({Future<File> Function()? file})
    : _file = file ?? _defaultFile,
      _memory = null;

  /// Keeps the answers in memory only (widget tests, where file I/O does not run in the fake clock).
  AiConsent.inMemory() : _file = _defaultFile, _memory = <String>[];

  /// The consent of the app. Tests replace it with [AiConsent.inMemory] or one that writes to a temporary file.
  static AiConsent instance = AiConsent();

  final Future<File> Function() _file;
  final List<String>? _memory;

  static Future<File> _defaultFile() async => File(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}ai_consent.json',
  );

  Future<({String destination, Set<AiFeature> features})> _read() async {
    const empty = (destination: '', features: <AiFeature>{});
    try {
      final String raw;
      final memory = _memory;
      if (memory != null) {
        if (memory.isEmpty) return empty;
        raw = memory.single;
      } else {
        final file = await _file();
        if (!await file.exists()) return empty;
        raw = await file.readAsString();
      }
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final names = {for (final feature in AiFeature.values) feature.name};
      return (
        destination: data['destination'] as String,
        features: {
          for (final name in (data['features'] as List).cast<String>())
            if (names.contains(name)) AiFeature.values.byName(name),
        },
      );
    } on Object {
      // Unreadable consent counts as none: the user is asked again.
      return empty;
    }
  }

  Future<void> _write(String destination, Set<AiFeature> features) async {
    final raw = jsonEncode({
      'destination': destination,
      'features': [for (final feature in features) feature.name]..sort(),
    });
    final memory = _memory;
    if (memory != null) {
      memory
        ..clear()
        ..add(raw);
      return;
    }
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(raw);
  }

  /// The functions allowed to send data to the destination of [config].
  Future<Set<AiFeature>> granted(AiProviderConfig config) async {
    final saved = await _read();
    return saved.destination == aiDestinationOf(config)
        ? saved.features
        : <AiFeature>{};
  }

  Future<bool> isGranted(AiFeature feature, AiProviderConfig config) async =>
      (await granted(config)).contains(feature);

  /// Allows [feature] for the destination of [config]. A consent given for another destination is dropped.
  Future<void> grant(AiFeature feature, AiProviderConfig config) async {
    final current = await granted(config);
    await _write(aiDestinationOf(config), {...current, feature});
  }

  Future<void> revoke(AiFeature feature, AiProviderConfig config) async {
    final current = await granted(config);
    await _write(aiDestinationOf(config), {...current}..remove(feature));
  }
}

/// The client of the saved settings for [feature]. Throws [AiException] with [AiErrorKind.notConfigured] when the
/// user has not accepted that function for the destination in use: nothing is sent without that.
Future<AiClient> aiClientFor(AiFeature feature) async {
  if (!await AiConsent.instance.isGranted(feature, await currentAiConfig())) {
    throw const AiException(
      AiErrorKind.notConfigured,
      'The user has not allowed this AI function',
    );
  }
  return AiService.instance.client();
}
