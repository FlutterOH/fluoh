import 'dart:convert';
import 'dart:io';

import '../context/fluoh_environment.dart';

const defaultSourceName = 'flutteroh';
const defaultSourceUrl = 'https://github.com/FlutterOH/pub.git';
const defaultSourcePriority = 10;
const defaultSourceUrlEnvironmentKey = 'FLUOH_DEFAULT_SOURCE_URL';
final _sourceNamePattern = RegExp(r'^[A-Za-z0-9_.-]+$');

class FluohConfigStore {
  const FluohConfigStore(this.environment);

  final FluohEnvironment environment;

  Future<FluohConfig> load() async {
    final file = environment.configFile;
    if (!await file.exists()) {
      final config = FluohConfig.withDefaultSource(environment);
      await save(config);
      return config;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException catch (error) {
      throw FormatException('fluoh config could not be read: ${error.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('fluoh config must be a JSON object.');
    }
    return FluohConfig.fromJson(decoded);
  }

  Future<void> save(FluohConfig config) async {
    await environment.homeDirectory.create(recursive: true);
    await environment.configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
  }
}

class FluohConfig {
  const FluohConfig({this.sources = const <String, SourceConfig>{}});

  factory FluohConfig.withDefaultSource(FluohEnvironment environment) {
    return FluohConfig(
      sources: {
        defaultSourceName: SourceConfig(
          path: '${environment.homeDirectory.path}/sources/flutteroh-pub',
          url:
              environment.processEnvironment[defaultSourceUrlEnvironmentKey] ??
              defaultSourceUrl,
          priority: defaultSourcePriority,
        ),
      },
    );
  }

  factory FluohConfig.fromJson(Map<String, Object?> json) {
    final sources = json['sources'];
    if (sources != null && sources is! Map<String, Object?>) {
      throw const FormatException('config sources must be an object.');
    }

    final sourceMap = sources as Map<String, Object?>? ?? const {};

    return FluohConfig(
      sources: sourceMap.map((name, value) {
        final error = sourceNameValidationError(name);
        if (error != null) {
          throw FormatException('Invalid source name "$name": $error');
        }
        return MapEntry(
          name,
          SourceConfig.fromJson(_jsonObject(value, 'source "$name"')),
        );
      }),
    );
  }

  final Map<String, SourceConfig> sources;

  FluohConfig addSource(String name, String path, {int priority = 100}) {
    final nextSources = {
      ...sources,
      name: SourceConfig(path: path, priority: priority),
    };
    return FluohConfig(sources: nextSources);
  }

  FluohConfig addGitSource(
    String name,
    String url,
    String path, {
    int priority = 100,
  }) {
    final nextSources = {
      ...sources,
      name: SourceConfig(path: path, url: url, priority: priority),
    };
    return FluohConfig(sources: nextSources);
  }

  FluohConfig removeSource(String name) {
    if (name == defaultSourceName) {
      throw ArgumentError('Cannot remove the official source.');
    }
    if (!sources.containsKey(name)) {
      throw ArgumentError('Unknown source "$name".');
    }
    final nextSources = {...sources}..remove(name);
    return FluohConfig(sources: nextSources);
  }

  Map<String, Object?> toJson() {
    return {
      'sources': sources.map((name, source) => MapEntry(name, source.toJson())),
    };
  }
}

class SourceConfig {
  const SourceConfig({
    required this.path,
    this.url,
    this.priority = defaultSourcePriority,
  });

  factory SourceConfig.fromJson(Map<String, Object?> json) {
    final path = json['path'];
    if (path is! String || path.isEmpty) {
      throw const FormatException('source path must be a non-empty string.');
    }
    final url = json['url'];
    if (url != null && url is! String) {
      throw const FormatException('source url must be a string.');
    }
    final priority = json['priority'];
    if (priority != null && priority is! int) {
      throw const FormatException('source priority must be an integer.');
    }
    return SourceConfig(
      path: path,
      url: url as String?,
      priority: priority as int? ?? defaultSourcePriority,
    );
  }

  final String path;
  final String? url;
  final int priority;

  Directory get directory => Directory(path);

  String get displayValue => url ?? path;

  Map<String, Object?> toJson() => {
    'path': path,
    if (url != null) 'url': url,
    'priority': priority,
  };
}

Map<String, Object?> _jsonObject(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FormatException('Expected $label to be a JSON object.');
  }
  return value;
}

String? sourceNameValidationError(String name) {
  if (name.isEmpty) {
    return 'source name must not be empty.';
  }
  if (name == '.' || name == '..') {
    return 'source name must not be "." or "..".';
  }
  if (!_sourceNamePattern.hasMatch(name)) {
    return 'source name must contain only letters, numbers, "_", ".", or "-".';
  }
  return null;
}
