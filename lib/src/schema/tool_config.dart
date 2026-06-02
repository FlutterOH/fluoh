import 'dart:io';

import 'yaml_utils.dart';

/// Built-in Source name used for the official FlutterOH source.
const defaultSourceName = 'flutteroh';

/// Default official Source Git URL.
const defaultSourceUrl = 'https://github.com/FlutterOH/source.git';

/// Default priority assigned to user-added Sources.
const defaultSourcePriority = 10;

/// Priority assigned to the official Source.
const officialSourcePriority = 0;

/// Environment variable that overrides the official Source URL in tests.
const defaultSourceUrlEnvironmentKey = 'FLUOH_DEFAULT_SOURCE_URL';
final _sourceNamePattern = RegExp(r'^[A-Za-z0-9_.-]+$');

/// Persisted tool configuration.
class ToolConfig {
  /// Creates a tool configuration value.
  const ToolConfig({this.sources = const <String, SourceConfig>{}});

  /// Parses tool configuration from JSON.
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

  /// Configured Sources keyed by Source name.
  final Map<String, SourceConfig> sources;

  /// Returns a copy with a local Source added or replaced.
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

  /// Returns a copy with a Git-backed Source added or replaced.
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

  /// Returns a copy with [name] removed.
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

  /// Converts this config to persisted JSON.
  Map<String, Object?> toJson() {
    return {
      'sources': sources.map((name, source) => MapEntry(name, source.toJson())),
    };
  }
}

/// Configuration for one Source snapshot.
class SourceConfig {
  /// Creates Source configuration.
  const SourceConfig({
    required this.path,
    this.url,
    this.priority = defaultSourcePriority,
  });

  /// Parses Source configuration from JSON.
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

  /// Local snapshot path for this Source.
  final String path;

  /// Optional Git URL used to synchronize this Source.
  final String? url;

  /// Merge priority; lower values win on conflicts.
  final int priority;

  /// Local snapshot directory.
  Directory get directory => Directory(path);

  /// User-facing URL or local path for this Source.
  String get displayValue => url ?? path;

  /// Converts this Source to persisted JSON.
  Map<String, Object?> toJson() => {
    'path': path,
    if (url != null) 'url': url,
    'priority': priority,
  };
}

/// Returns a validation error for [name], or `null` when valid.
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
