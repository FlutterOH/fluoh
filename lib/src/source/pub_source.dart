import 'dart:convert';
import 'dart:io';

import '../sdk/sdk_release.dart';

class PubSource {
  const PubSource.directory(this.root);

  final Directory root;

  Future<SdkIndex> loadSdkIndex() async {
    return SdkIndex.fromJson(await _readGeneratedJson('sdk-index.json'));
  }

  Future<PackageIndex> loadPackageIndex() async {
    return PackageIndex.fromJson(
      await _readGeneratedJson('package-index.json'),
    );
  }

  Future<CompatibilityMatrix> loadCompatibilityMatrix() async {
    return CompatibilityMatrix.fromJson(
      await _readGeneratedJson('compatibility-matrix.json'),
    );
  }

  Future<Map<String, Object?>> _readGeneratedJson(String fileName) async {
    final file = File('${root.path}/generated/$fileName');
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, Object?>) {
      throw FormatException('$fileName must contain a JSON object.');
    }
    return decoded;
  }
}

class PackageIndex {
  const PackageIndex({required this.schemaVersion, required this.packages});

  factory PackageIndex.fromJson(Map<String, Object?> json) {
    final packages = json['packages'];
    if (packages is! Map<String, Object?>) {
      throw const FormatException('Package index packages must be an object.');
    }

    return PackageIndex(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      packages: packages.map(
        (name, value) => MapEntry(
          name,
          PackageEntry.fromJson(_jsonObject(value, 'package "$name"')),
        ),
      ),
    );
  }

  final int schemaVersion;
  final Map<String, PackageEntry> packages;
}

class PackageEntry {
  const PackageEntry({required this.upstream, required this.adapters});

  factory PackageEntry.fromJson(Map<String, Object?> json) {
    final adapters = json['adapters'];
    if (adapters is! List) {
      throw const FormatException('Package adapters must be a list.');
    }

    return PackageEntry(
      upstream: _requiredString(json, 'upstream'),
      adapters: adapters
          .map(
            (value) =>
                PackageAdapter.fromJson(_jsonObject(value, 'package adapter')),
          )
          .toList(growable: false),
    );
  }

  final String upstream;
  final List<PackageAdapter> adapters;
}

class PackageAdapter {
  const PackageAdapter({
    required this.sdkLine,
    required this.upstreamVersion,
    required this.repository,
    required this.tag,
    this.path,
    this.sourceName,
    this.sourcePriority = 0,
  });

  factory PackageAdapter.fromJson(Map<String, Object?> json) {
    return PackageAdapter(
      sdkLine: _requiredString(json, 'sdkLine'),
      upstreamVersion: _requiredString(json, 'upstreamVersion'),
      repository: _requiredString(json, 'repository'),
      tag: _requiredString(json, 'tag'),
      path: json['path'] as String?,
    );
  }

  final String sdkLine;
  final String upstreamVersion;
  final String repository;
  final String tag;
  final String? path;
  final String? sourceName;
  final int sourcePriority;

  PackageAdapter withSource(String name, int priority) {
    return PackageAdapter(
      sdkLine: sdkLine,
      upstreamVersion: upstreamVersion,
      repository: repository,
      tag: tag,
      path: path,
      sourceName: name,
      sourcePriority: priority,
    );
  }
}

class CompatibilityMatrix {
  const CompatibilityMatrix({
    required this.schemaVersion,
    required this.sdkLines,
  });

  factory CompatibilityMatrix.fromJson(Map<String, Object?> json) {
    final sdkLines = json['sdkLines'];
    if (sdkLines is! Map<String, Object?>) {
      throw const FormatException('Compatibility SDK lines must be an object.');
    }

    return CompatibilityMatrix(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      sdkLines: sdkLines.map(
        (line, value) => MapEntry(
          line,
          CompatibilityLine.fromJson(_jsonObject(value, 'SDK line "$line"')),
        ),
      ),
    );
  }

  final int schemaVersion;
  final Map<String, CompatibilityLine> sdkLines;
}

class CompatibilityLine {
  const CompatibilityLine({
    required this.native,
    required this.adapted,
    required this.blocked,
  });

  factory CompatibilityLine.fromJson(Map<String, Object?> json) {
    return CompatibilityLine(
      native: _stringList(json, 'native'),
      adapted: _stringList(json, 'adapted'),
      blocked: _stringList(json, 'blocked'),
    );
  }

  final List<String> native;
  final List<String> adapted;
  final List<String> blocked;
}

Map<String, Object?> _jsonObject(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FormatException('Expected $label to be a JSON object.');
  }
  return value;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected "$key" to be a non-empty string.');
  }
  return value;
}

List<String> _stringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return const [];
  }
  if (value is! List) {
    throw FormatException('Expected "$key" to be a list of strings.');
  }
  return value.cast<String>().toList(growable: false);
}
