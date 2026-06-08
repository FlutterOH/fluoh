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
    final recommendedCandidates = this.recommendedCandidates(missingPlatform);
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
      'recommendedCount': recommendedCandidates.length,
      'candidates': candidates
          .map(
            (candidate) => candidate.toJson(
              upstream: upstream,
              missingPlatform: missingPlatform,
            ),
          )
          .toList(),
      'queueCommand': recommendedCandidates.isEmpty
          ? null
          : packageDiscoveryQueueCommand(recommendedCandidates),
      'issues': issues.map((issue) => issue.toJson()).toList(),
    };
  }

  /// Candidates that should be used by the default adaptation queue.
  List<PackageDiscoveryCandidate> recommendedCandidates(
    String missingPlatform,
  ) {
    return candidates
        .where((candidate) => candidate.isRecommendedFor(missingPlatform))
        .toList(growable: false);
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
    required this.role,
    this.platformDefaultPackages = const {},
    this.coveredByImplementationRecommendations = const [],
    this.defaultRecommendationExclusionReason,
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

  /// Discovery role for AI package selection.
  final String role;

  /// Federated default_package declarations keyed by platform.
  final Map<String, String> platformDefaultPackages;

  /// App-facing packages whose implementation recommendation covers this
  /// existing platform package.
  final List<PackageImplementationCoverage>
  coveredByImplementationRecommendations;

  /// Reason this package should not enter the default adaptation queue even
  /// though it is a valid Flutter plugin missing the target platform.
  final String? defaultRecommendationExclusionReason;

  /// Whether this package declares [platform].
  bool declaresPlatform(String platform) => platforms.contains(platform);

  /// Whether this package is a default recommended adaptation target.
  bool isRecommendedFor(String missingPlatform) {
    return !declaresPlatform(missingPlatform) &&
        coveredByImplementationRecommendations.isEmpty &&
        defaultRecommendationExclusionReason == null;
  }

  /// Stable reason for this candidate's recommendation state.
  String recommendationReason(String missingPlatform) {
    if (declaresPlatform(missingPlatform)) {
      return 'flutter_plugin_platform_present';
    }
    if (coveredByImplementationRecommendations.isNotEmpty) {
      return 'covered_by_federated_app_facing_package';
    }
    final exclusionReason = defaultRecommendationExclusionReason;
    if (exclusionReason != null) {
      return exclusionReason;
    }
    return 'flutter_plugin_missing_platform';
  }

  /// Returns the implementation package recommendation for [missingPlatform].
  PackageImplementationRecommendation? implementationRecommendation(
    String missingPlatform,
  ) {
    if (declaresPlatform(missingPlatform) || platformDefaultPackages.isEmpty) {
      return null;
    }
    final implementationPackageName = '${name}_$missingPlatform';
    final implementationPackagePath = _implementationPackagePath(
      path,
      implementationPackageName,
    );
    return PackageImplementationRecommendation(
      platform: missingPlatform,
      appFacingPackage: name,
      appFacingPath: path,
      implementationPackageName: implementationPackageName,
      implementationPackagePath: implementationPackagePath,
      implementationDependencyPath: _relativePackagePath(
        from: path,
        to: implementationPackagePath,
      ),
      existingDefaultPackages: platformDefaultPackages,
    );
  }

  /// Converts this candidate to JSON.
  Map<String, Object?> toJson({
    required String upstream,
    required String missingPlatform,
  }) {
    final missingPlatforms = declaresPlatform(missingPlatform)
        ? const <String>[]
        : [missingPlatform];
    final recommendation = implementationRecommendation(missingPlatform);
    final recommended = isRecommendedFor(missingPlatform);
    return {
      'name': name,
      'version': version,
      if (sdkConstraint != null) 'sdkConstraint': sdkConstraint,
      'path': path,
      'platforms': platforms,
      'role': role,
      if (platformDefaultPackages.isNotEmpty)
        'platformDefaultPackages': platformDefaultPackages,
      'missingPlatforms': missingPlatforms,
      'recommended': recommended,
      'reason': recommendationReason(missingPlatform),
      if (coveredByImplementationRecommendations.isNotEmpty)
        'coveredByImplementationRecommendations':
            coveredByImplementationRecommendations
                .map((coverage) => coverage.toJson())
                .toList(),
      if (recommendation != null)
        'implementationRecommendation': recommendation.toJson(
          setupCommand: packageDiscoveryCreateCommand(
            upstream: upstream,
            candidate: this,
          ),
        ),
      'createCommand': packageDiscoveryCreateCommand(
        upstream: upstream,
        candidate: this,
      ),
    };
  }

  /// Returns a copy with federated implementation coverage.
  PackageDiscoveryCandidate copyWith({
    List<PackageImplementationCoverage>? coveredByImplementationRecommendations,
  }) {
    return PackageDiscoveryCandidate(
      name: name,
      version: version,
      path: path,
      sdkConstraint: sdkConstraint,
      platforms: platforms,
      role: role,
      platformDefaultPackages: platformDefaultPackages,
      coveredByImplementationRecommendations:
          coveredByImplementationRecommendations ??
          this.coveredByImplementationRecommendations,
      defaultRecommendationExclusionReason:
          defaultRecommendationExclusionReason,
    );
  }
}

/// Recommended federated implementation package for a discovery candidate.
class PackageImplementationRecommendation {
  /// Creates a package implementation recommendation.
  const PackageImplementationRecommendation({
    required this.platform,
    required this.appFacingPackage,
    required this.appFacingPath,
    required this.implementationPackageName,
    required this.implementationPackagePath,
    required this.implementationDependencyPath,
    required this.existingDefaultPackages,
  });

  /// Missing platform that should receive an implementation package.
  final String platform;

  /// App-facing package that declares federated default packages.
  final String appFacingPackage;

  /// App-facing package path inside the upstream repository.
  final String appFacingPath;

  /// Suggested implementation package name.
  final String implementationPackageName;

  /// Suggested implementation package path inside the upstream repository.
  final String implementationPackagePath;

  /// Relative dependency path from the app-facing package to the implementation.
  final String implementationDependencyPath;

  /// Existing default_package declarations keyed by platform.
  final Map<String, String> existingDefaultPackages;

  /// Converts this recommendation to JSON.
  Map<String, Object?> toJson({String? setupCommand}) {
    return {
      'kind': 'federated_platform_package',
      'reason': 'federated_plugin_missing_platform_package',
      'platform': platform,
      'setupCommand': ?setupCommand,
      'sourceRoute': {
        'packageName': appFacingPackage,
        'packagePath': appFacingPath,
      },
      'appFacingPackage': appFacingPackage,
      'appFacingPath': appFacingPath,
      'implementationPackageName': implementationPackageName,
      'implementationPackagePath': implementationPackagePath,
      'implementationDependency': {
        'package': implementationPackageName,
        'path': implementationDependencyPath,
      },
      'existingDefaultPackages': existingDefaultPackages,
      'requiredEdits': [
        {
          'target': 'implementationPackage',
          'action': 'create',
          'package': implementationPackageName,
          'path': implementationPackagePath,
        },
        {
          'target': 'appFacingPubspec',
          'action': 'add_default_package',
          'platform': platform,
          'defaultPackage': implementationPackageName,
        },
        {
          'target': 'appFacingPubspec',
          'action': 'add_dependency',
          'package': implementationPackageName,
          'path': implementationDependencyPath,
        },
      ],
    };
  }
}

/// Existing platform implementation package covered by an app-facing package.
class PackageImplementationCoverage {
  /// Creates implementation coverage metadata.
  const PackageImplementationCoverage({
    required this.kind,
    required this.appFacingPackage,
    required this.appFacingPath,
    required this.referencedPlatforms,
    this.candidatePlatforms = const [],
    required this.recommendedImplementationPackage,
    required this.recommendedImplementationPath,
  });

  /// Why this existing implementation package is covered.
  final String kind;

  /// App-facing package that currently references this implementation package.
  final String appFacingPackage;

  /// App-facing package path inside the upstream repository.
  final String appFacingPath;

  /// Platforms where the app-facing package uses this package as
  /// `default_package`.
  final List<String> referencedPlatforms;

  /// Platforms declared by the covered package when it is a federated-family
  /// sibling rather than a current `default_package` target.
  final List<String> candidatePlatforms;

  /// Platform implementation package recommended for the missing platform.
  final String recommendedImplementationPackage;

  /// Path recommended for the missing-platform implementation package.
  final String recommendedImplementationPath;

  /// Converts this coverage metadata to JSON.
  Map<String, Object?> toJson() {
    return {
      'kind': kind,
      'appFacingPackage': appFacingPackage,
      'appFacingPath': appFacingPath,
      if (referencedPlatforms.isNotEmpty)
        'referencedPlatforms': referencedPlatforms,
      if (candidatePlatforms.isNotEmpty)
        'candidatePlatforms': candidatePlatforms,
      'recommendedImplementationPackage': recommendedImplementationPackage,
      'recommendedImplementationPath': recommendedImplementationPath,
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

  var selectedCandidates = _withFederatedImplementationCoverage(
    candidates,
    missingPlatform: missingPlatform,
  );
  selectedCandidates.sort((a, b) {
    final pathCompare = a.path.compareTo(b.path);
    return pathCompare == 0 ? a.name.compareTo(b.name) : pathCompare;
  });
  return PackageDiscovery(
    pubspecCount: pubspecCount,
    pluginPackageCount: pluginPackageCount,
    candidates: selectedCandidates,
    issues: issues,
  );
}

List<PackageDiscoveryCandidate> _withFederatedImplementationCoverage(
  List<PackageDiscoveryCandidate> candidates, {
  required String missingPlatform,
}) {
  final coverageByPackageName = <String, List<PackageImplementationCoverage>>{};
  for (final candidate in candidates) {
    final recommendation = candidate.implementationRecommendation(
      missingPlatform,
    );
    if (recommendation == null) {
      continue;
    }
    final platformsByDefaultPackage = <String, List<String>>{};
    for (final entry in candidate.platformDefaultPackages.entries) {
      if (entry.value == candidate.name) {
        continue;
      }
      platformsByDefaultPackage
          .putIfAbsent(entry.value, () => <String>[])
          .add(entry.key);
    }
    for (final entry in platformsByDefaultPackage.entries) {
      final referencedPlatforms = entry.value..sort();
      coverageByPackageName
          .putIfAbsent(entry.key, () => [])
          .add(
            _implementationCoverage(
              kind: 'default_package',
              appFacing: candidate,
              recommendation: recommendation,
              referencedPlatforms: referencedPlatforms,
            ),
          );
    }
    for (final sibling in candidates) {
      if (!_isFederatedFamilySibling(appFacing: candidate, sibling: sibling)) {
        continue;
      }
      final existingCoverage = coverageByPackageName[sibling.name] ?? const [];
      if (existingCoverage.any(
        (coverage) => coverage.appFacingPackage == candidate.name,
      )) {
        continue;
      }
      final siblingPlatforms = [...sibling.platforms]..sort();
      coverageByPackageName
          .putIfAbsent(sibling.name, () => [])
          .add(
            _implementationCoverage(
              kind: 'federated_family_sibling',
              appFacing: candidate,
              recommendation: recommendation,
              candidatePlatforms: siblingPlatforms,
            ),
          );
    }
  }
  if (coverageByPackageName.isEmpty) {
    return candidates;
  }
  return [
    for (final candidate in candidates)
      candidate.copyWith(
        coveredByImplementationRecommendations:
            coverageByPackageName[candidate.name],
      ),
  ];
}

PackageImplementationCoverage _implementationCoverage({
  required String kind,
  required PackageDiscoveryCandidate appFacing,
  required PackageImplementationRecommendation recommendation,
  List<String> referencedPlatforms = const [],
  List<String> candidatePlatforms = const [],
}) {
  return PackageImplementationCoverage(
    kind: kind,
    appFacingPackage: appFacing.name,
    appFacingPath: appFacing.path,
    referencedPlatforms: List.unmodifiable(referencedPlatforms),
    candidatePlatforms: List.unmodifiable(candidatePlatforms),
    recommendedImplementationPackage: recommendation.implementationPackageName,
    recommendedImplementationPath: recommendation.implementationPackagePath,
  );
}

bool _isFederatedFamilySibling({
  required PackageDiscoveryCandidate appFacing,
  required PackageDiscoveryCandidate sibling,
}) {
  if (sibling.name == appFacing.name ||
      !sibling.name.startsWith('${appFacing.name}_')) {
    return false;
  }
  return _parentPackagePath(sibling.path) == _parentPackagePath(appFacing.path);
}

String _parentPackagePath(String path) {
  final normalized = _normalizePackagePath(path);
  if (normalized == '.') {
    return '.';
  }
  final slash = normalized.lastIndexOf('/');
  if (slash == -1) {
    return '.';
  }
  return normalized.substring(0, slash);
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

  final platforms = _pluginPlatformMetadata(plugin, relativePubspec, issues);
  if (platforms == null) {
    return null;
  }
  final role = _candidateRole(
    name: name,
    path: packagePath,
    platforms: platforms.names,
    platformDefaultPackages: platforms.defaultPackages,
  );
  return PackageDiscoveryCandidate(
    name: name,
    version: version,
    path: packagePath,
    sdkConstraint: _sdkConstraint(yaml, relativePubspec, issues),
    platforms: platforms.names,
    role: role,
    platformDefaultPackages: platforms.defaultPackages,
    defaultRecommendationExclusionReason: _defaultRecommendationExclusionReason(
      role,
    ),
  );
}

String _candidateRole({
  required String name,
  required String path,
  required List<String> platforms,
  required Map<String, String> platformDefaultPackages,
}) {
  if (_isTestFixturePath(path) || _isKnownTestHelperPackage(name)) {
    return 'test_fixture';
  }
  if (platformDefaultPackages.isNotEmpty) {
    return 'app_facing_package';
  }
  if (_isPlatformSpecificHelper(name: name, platforms: platforms)) {
    return 'platform_specific_helper';
  }
  return 'flutter_plugin';
}

String? _defaultRecommendationExclusionReason(String role) {
  return switch (role) {
    'test_fixture' => 'test_fixture',
    'platform_specific_helper' => 'platform_specific_helper_package',
    _ => null,
  };
}

bool _isTestFixturePath(String path) {
  final segments = _pathSegments(path).map((segment) => segment.toLowerCase());
  return segments.any(
    const {
      'platform_tests',
      'test',
      'tests',
      'testing',
      'test_plugin',
      'test_plugins',
    }.contains,
  );
}

bool _isKnownTestHelperPackage(String name) {
  return const {'espresso'}.contains(name);
}

bool _isPlatformSpecificHelper({
  required String name,
  required List<String> platforms,
}) {
  if (platforms.length != 1) {
    return false;
  }
  final platform = platforms.single;
  final normalizedName = name.toLowerCase();
  final tokens = switch (platform) {
    'android' => const ['android'],
    'ios' => const ['ios', 'apple', 'darwin', 'foundation', 'avfoundation'],
    'macos' => const ['macos', 'darwin', 'foundation', 'avfoundation'],
    'web' => const ['web', 'html'],
    'windows' => const ['windows', 'win32'],
    'linux' => const ['linux'],
    _ => const <String>[],
  };
  return tokens.any(
    (token) => _containsPackageNameToken(normalizedName, token),
  );
}

bool _containsPackageNameToken(String name, String token) {
  return name == token ||
      name.startsWith('${token}_') ||
      name.endsWith('_$token') ||
      name.contains('_${token}_');
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

_PluginPlatformMetadata? _pluginPlatformMetadata(
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
  final defaultPackages = <String, String>{};
  for (final name in names) {
    final platform = platforms[name];
    if (platform is Map<String, Object?>) {
      final defaultPackage = optionalString(platform, 'default_package');
      if (defaultPackage != null) {
        defaultPackages[name] = defaultPackage;
      }
    }
  }
  return _PluginPlatformMetadata(
    names: names,
    defaultPackages: Map.unmodifiable(defaultPackages),
  );
}

class _PluginPlatformMetadata {
  const _PluginPlatformMetadata({
    required this.names,
    required this.defaultPackages,
  });

  final List<String> names;
  final Map<String, String> defaultPackages;
}

String _implementationPackagePath(String appFacingPath, String packageName) {
  final normalized = _normalizePackagePath(appFacingPath);
  if (normalized == '.') {
    return packageName;
  }
  final slash = normalized.lastIndexOf('/');
  if (slash == -1) {
    return packageName;
  }
  return '${normalized.substring(0, slash)}/$packageName';
}

String _relativePackagePath({required String from, required String to}) {
  final fromSegments = _pathSegments(from);
  final toSegments = _pathSegments(to);
  var common = 0;
  while (common < fromSegments.length &&
      common < toSegments.length &&
      fromSegments[common] == toSegments[common]) {
    common += 1;
  }
  final parts = [
    for (var i = common; i < fromSegments.length; i += 1) '..',
    ...toSegments.skip(common),
  ];
  return parts.isEmpty ? '.' : parts.join('/');
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
  final segments = _pathSegments(path);
  if (segments.isEmpty) {
    return '.';
  }
  return segments.join('/');
}

List<String> _pathSegments(String path) {
  return path
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty && segment != '.')
      .toList(growable: false);
}

bool _shouldSkipCandidatePath(String path) {
  final segments = _pathSegments(path);
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
