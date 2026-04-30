import 'dart:convert';
import 'dart:io';

import '../context/fluoh_environment.dart';

const defaultSourceName = 'flutteroh';
const defaultSourceUrl = 'https://github.com/FlutterOH/pub.git';
const defaultSourcePriority = 10;

class FluohConfigStore {
  const FluohConfigStore(this.environment);

  final FluohEnvironment environment;

  Future<FluohConfig> load() async {
    final file = environment.configFile;
    if (!await file.exists()) {
      return FluohConfig.withDefaultSource(environment);
    }

    final decoded = jsonDecode(await file.readAsString());
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
  const FluohConfig({
    this.activeSource,
    this.sources = const <String, SourceConfig>{},
  });

  factory FluohConfig.withDefaultSource(FluohEnvironment environment) {
    return FluohConfig(
      activeSource: defaultSourceName,
      sources: {
        defaultSourceName: SourceConfig(
          path: '${environment.homeDirectory.path}/sources/flutteroh-pub',
          url: defaultSourceUrl,
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
      activeSource: json['activeSource'] as String?,
      sources: sourceMap.map(
        (name, value) => MapEntry(
          name,
          SourceConfig.fromJson(_jsonObject(value, 'source "$name"')),
        ),
      ),
    );
  }

  final String? activeSource;
  final Map<String, SourceConfig> sources;

  FluohConfig addSource(String name, String path, {int priority = 100}) {
    final nextSources = {
      ...sources,
      name: SourceConfig(path: path, priority: priority),
    };
    return FluohConfig(
      activeSource: _nextActiveSource(name, nextSources),
      sources: nextSources,
    );
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
    return FluohConfig(
      activeSource: _nextActiveSource(name, nextSources),
      sources: nextSources,
    );
  }

  String _nextActiveSource(String addedName, Map<String, SourceConfig> next) {
    final active = activeSource;
    if (active == null) {
      return addedName;
    }
    if (active == defaultSourceName &&
        next.length == 2 &&
        next.containsKey(defaultSourceName)) {
      return addedName;
    }
    return active;
  }

  FluohConfig useSource(String name) {
    if (!sources.containsKey(name)) {
      throw ArgumentError('Unknown source "$name".');
    }
    return FluohConfig(activeSource: name, sources: sources);
  }

  SourceConfig activeSourceConfig() {
    final active = activeSource;
    if (active == null) {
      throw StateError('No active source. Run "fluoh source use <name>".');
    }

    final source = sources[active];
    if (source == null) {
      throw StateError('Active source "$active" is not configured.');
    }

    return source;
  }

  Map<String, Object?> toJson() {
    return {
      if (activeSource != null) 'activeSource': activeSource,
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
    return SourceConfig(
      path: path,
      url: url as String?,
      priority: json['priority'] as int? ?? defaultSourcePriority,
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
