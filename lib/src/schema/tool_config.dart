import 'dart:io';

import 'yaml_utils.dart';

const defaultSourceName = 'flutteroh';
const defaultSourceUrl = 'https://github.com/FlutterOH/pub.git';
const defaultSourcePriority = 10;
const officialSourcePriority = 0;
const defaultSourceUrlEnvironmentKey = 'FLUOH_DEFAULT_SOURCE_URL';
final _sourceNamePattern = RegExp(r'^[A-Za-z0-9_.-]+$');

class ToolConfig {
  const ToolConfig({this.sources = const <String, SourceConfig>{}});

  factory ToolConfig.fromJson(Map<String, Object?> json) {
    final sources = json['sources'];
    if (sources != null && sources is! Map<String, Object?>) {
      throw const FluohSchemaException('config sources must be an object.');
    }

    final sourceMap = sources as Map<String, Object?>? ?? const {};

    return ToolConfig(
      sources: sourceMap.map((name, value) {
        final error = sourceNameValidationError(name);
        if (error != null) {
          throw FluohSchemaException('Invalid source name "$name": $error');
        }
        return MapEntry(
          name,
          SourceConfig.fromJson(jsonObject(value, 'source "$name"')),
        );
      }),
    );
  }

  final Map<String, SourceConfig> sources;

  ToolConfig addSource(
    String name,
    String path, {
    int priority = defaultSourcePriority,
  }) {
    final nextSources = {
      ...sources,
      name: SourceConfig(path: path, priority: priority),
    };
    return ToolConfig(sources: nextSources);
  }

  ToolConfig addGitSource(
    String name,
    String url,
    String path, {
    int priority = defaultSourcePriority,
  }) {
    final nextSources = {
      ...sources,
      name: SourceConfig(path: path, url: url, priority: priority),
    };
    return ToolConfig(sources: nextSources);
  }

  ToolConfig removeSource(String name) {
    if (name == defaultSourceName) {
      throw ArgumentError('Cannot remove the official source.');
    }
    if (!sources.containsKey(name)) {
      throw ArgumentError('Unknown source "$name".');
    }
    final nextSources = {...sources}..remove(name);
    return ToolConfig(sources: nextSources);
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
      throw const FluohSchemaException(
        'source path must be a non-empty string.',
      );
    }
    final url = json['url'];
    if (url != null && url is! String) {
      throw const FluohSchemaException('source url must be a string.');
    }
    final priority = json['priority'];
    if (priority != null && priority is! int) {
      throw const FluohSchemaException('source priority must be an integer.');
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
