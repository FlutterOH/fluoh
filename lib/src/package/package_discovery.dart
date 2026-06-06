import 'dart:io';

import '../schema/yaml_utils.dart';

/// Read-only package discovery result for an upstream repository.
class PackageDiscovery {
  /// Creates a package discovery result.
  const PackageDiscovery({
    required this.pubspecCount,
    required this.pluginPackageCount,
    required this.candidates,
    required this.issues,
  });

  /// Number of non-skipped pubspec files inspected.
  final int pubspecCount;

  /// Number of valid Flutter plugin package pubspecs found.
  final int pluginPackageCount;

  /// Packages matching the discovery filter.
  final List<PackageDiscoveryCandidate> candidates;

  /// Non-fatal issues found while inspecting pubspec files.
  final List<PackageDiscoveryIssue> issues;

  /// Converts this discovery result to JSON.
  Map<String, Object?> toJson({
    required String upstream,
    required String missingPlatform,
    required bool includeExistingPlatform,
  }) {
    return {
      'upstream': {'urlOrPath': upstream},
      'filter': {
        'kind': 'flutter-plugin',
        'missingPlatform': missingPlatform,
        'includeExistingPlatform': includeExistingPlatform,
      },
      'pubspecCount': pubspecCount,
      'pluginPackageCount': pluginPackageCount,
      'candidateCount': candidates.length,
      'candidates': candidates
          .map(
            (candidate) => candidate.toJson(
              upstream: upstream,
              missingPlatform: missingPlatform,
            ),
          )
          .toList(),
      'queueCommand': candidates.isEmpty
          ? null
          : packageDiscoveryQueueCommand(candidates),
      'issues': issues.map((issue) => issue.toJson()).toList(),
    };
  }
}

/// Candidate package selected by package discovery.
class PackageDiscoveryCandidate {
  /// Creates a package discovery candidate.
  const PackageDiscoveryCandidate({
    required this.name,
    required this.version,
    required this.path,
    required this.platforms,
    this.sdkConstraint,
  });

  /// Package name.
  final String name;

  /// Package version.
  final String version;

  /// Package path inside the upstream repository.
  final String path;

  /// Dart SDK constraint from `environment.sdk`, when present.
  final String? sdkConstraint;

  /// Flutter plugin platforms declared by the package.
  final List<String> platforms;

  /// Whether this package declares [platform].
  bool declaresPlatform(String platform) => platforms.contains(platform);

  /// Converts this candidate to JSON.
  Map<String, Object?> toJson({
    required String upstream,
    required String missingPlatform,
  }) {
    final missingPlatforms = declaresPlatform(missingPlatform)
        ? const <String>[]
        : [missingPlatform];
    return {
      'name': name,
      'version': version,
      if (sdkConstraint != null) 'sdkConstraint': sdkConstraint,
      'path': path,
      'platforms': platforms,
      'missingPlatforms': missingPlatforms,
      'recommended': missingPlatforms.isNotEmpty,
      'reason': missingPlatforms.isEmpty
          ? 'flutter_plugin_platform_present'
          : 'flutter_plugin_missing_platform',
      'createCommand': packageDiscoveryCreateCommand(
        upstream: upstream,
        candidate: this,
      ),
    };
  }
}

/// Non-fatal discovery issue.
class PackageDiscoveryIssue {
  /// Creates a discovery issue.
  const PackageDiscoveryIssue({
    required this.path,
    required this.code,
    required this.message,
  });

  /// Pubspec path relative to the repository root.
  final String path;

  /// Stable issue code.
  final String code;

  /// Human-readable issue message.
  final String message;

  /// Converts this issue to JSON.
  Map<String, Object?> toJson() {
    return {'path': path, 'code': code, 'message': message};
  }
}

/// Discovers Flutter plugin packages that are candidates for OHOS adaptation.
Future<PackageDiscovery> discoverPackageAdaptationCandidates({
  required Directory repository,
  String missingPlatform = 'ohos',
  bool includeExistingPlatform = false,
}) async {
  final candidates = <PackageDiscoveryCandidate>[];
  final issues = <PackageDiscoveryIssue>[];
  var pubspecCount = 0;
  var pluginPackageCount = 0;

  if (!await repository.exists()) {
    return PackageDiscovery(
      pubspecCount: pubspecCount,
      pluginPackageCount: pluginPackageCount,
      candidates: candidates,
      issues: issues,
    );
  }

  final pending = <Directory>[repository];
  while (pending.isNotEmpty) {
    final directory = pending.removeLast();
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is Directory) {
        final path = _relativeCandidatePath(repository, entity);
        if (!_shouldSkipCandidatePath(path)) {
          pending.add(entity);
        }
        continue;
      }
      if (entity is! File || !_isPubspecFile(entity)) {
        continue;
      }
      final packagePath = _relativeCandidatePath(repository, entity.parent);
      if (_shouldSkipCandidatePath(packagePath)) {
        continue;
      }
      pubspecCount += 1;
      final candidate = await _readDiscoveryCandidate(
        entity,
        packagePath: packagePath,
        issues: issues,
      );
      if (candidate == null) {
        continue;
      }
      pluginPackageCount += 1;
      if (!candidate.declaresPlatform(missingPlatform) ||
          includeExistingPlatform) {
        candidates.add(candidate);
      }
    }
  }

  candidates.sort((a, b) {
    final pathCompare = a.path.compareTo(b.path);
    return pathCompare == 0 ? a.name.compareTo(b.name) : pathCompare;
  });
  return PackageDiscovery(
    pubspecCount: pubspecCount,
    pluginPackageCount: pluginPackageCount,
    candidates: candidates,
    issues: issues,
  );
}

/// Builds the suggested package create command for a discovered candidate.
String packageDiscoveryCreateCommand({
  required String upstream,
  required PackageDiscoveryCandidate candidate,
}) {
  final parts = [
    'fluoh',
    'package',
    'create',
    upstream,
    '--repository-name',
    candidate.name,
  ];
  if (candidate.path != '.') {
    parts.addAll(['--package-path', candidate.path]);
  }
  return parts.map(_shellQuote).join(' ');
}

/// Builds the package queue command for discovered candidate paths.
String packageDiscoveryQueueCommand(
  List<PackageDiscoveryCandidate> candidates,
) {
  final parts = [
    'fluoh',
    'package',
    'queue',
    ...candidates.map((candidate) => candidate.path),
    '--json',
  ];
  return parts.map(_shellQuote).join(' ');
}

String _shellQuote(String value) {
  if (value.isEmpty) {
    return "''";
  }
  if (!RegExp(r'''[\s'"\\$`]''').hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", r"'\''")}'";
}

Future<PackageDiscoveryCandidate?> _readDiscoveryCandidate(
  File pubspec, {
  required String packagePath,
  required List<PackageDiscoveryIssue> issues,
}) async {
  final relativePubspec = packagePath == '.'
      ? 'pubspec.yaml'
      : '$packagePath/pubspec.yaml';
  final Map<String, Object?> yaml;
  try {
    yaml = parseYamlMap(await pubspec.readAsString(), label: relativePubspec);
  } on FormatException catch (error) {
    issues.add(
      PackageDiscoveryIssue(
        path: relativePubspec,
        code: 'pubspec.parse_failed',
        message: error.message,
      ),
    );
    return null;
  }

  final flutter = yaml['flutter'];
  if (flutter is! Map<String, Object?>) {
    return null;
  }
  final plugin = flutter['plugin'];
  if (plugin is! Map<String, Object?>) {
    return null;
  }

  final name = yaml['name'];
  final version = yaml['version'];
  if (name is! String ||
      name.isEmpty ||
      version is! String ||
      version.isEmpty) {
    issues.add(
      PackageDiscoveryIssue(
        path: relativePubspec,
        code: 'pubspec.package_identity_missing',
        message: 'Flutter plugin pubspec must contain name and version.',
      ),
    );
    return null;
  }

  final platforms = _pluginPlatforms(plugin, relativePubspec, issues);
  if (platforms == null) {
    return null;
  }
  return PackageDiscoveryCandidate(
    name: name,
    version: version,
    path: packagePath,
    sdkConstraint: _sdkConstraint(yaml, relativePubspec, issues),
    platforms: platforms,
  );
}

String? _sdkConstraint(
  Map<String, Object?> yaml,
  String relativePubspec,
  List<PackageDiscoveryIssue> issues,
) {
  final environment = yaml['environment'];
  if (environment == null) {
    return null;
  }
  if (environment is! Map<String, Object?>) {
    issues.add(
      PackageDiscoveryIssue(
        path: relativePubspec,
        code: 'pubspec.environment_malformed',
        message: 'environment must be a YAML object.',
      ),
    );
    return null;
  }
  return optionalString(environment, 'sdk');
}

List<String>? _pluginPlatforms(
  Map<String, Object?> plugin,
  String relativePubspec,
  List<PackageDiscoveryIssue> issues,
) {
  final platforms = plugin['platforms'];
  if (platforms == null) {
    return null;
  }
  if (platforms is! Map<String, Object?>) {
    issues.add(
      PackageDiscoveryIssue(
        path: relativePubspec,
        code: 'flutter_plugin_platforms_malformed',
        message: 'flutter.plugin.platforms must be a YAML object.',
      ),
    );
    return null;
  }
  final names = platforms.keys.toList()..sort();
  return names;
}

bool _isPubspecFile(File file) {
  final normalized = file.path.replaceAll('\\', '/');
  return normalized.endsWith('/pubspec.yaml');
}

String _relativeCandidatePath(Directory repository, Directory directory) {
  final root = repository.absolute.path;
  final path = directory.absolute.path;
  if (path == root) {
    return '.';
  }
  if (path.startsWith('$root${Platform.pathSeparator}')) {
    return _normalizePackagePath(path.substring(root.length + 1));
  }
  return _normalizePackagePath(path);
}

String _normalizePackagePath(String path) {
  final segments = path
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty && segment != '.')
      .toList(growable: false);
  if (segments.isEmpty) {
    return '.';
  }
  return segments.join('/');
}

bool _shouldSkipCandidatePath(String path) {
  final segments = path
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty && segment != '.');
  return segments.any(
    (segment) => const {
      '.dart_tool',
      '.git',
      '.idea',
      'build',
      'example',
      'examples',
      'node_modules',
    }.contains(segment),
  );
}
