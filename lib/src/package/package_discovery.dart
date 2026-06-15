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
    required this.adaptationProfile,
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

  /// Capability and risk profile that helps AI seed adaptation tests.
  final PackageAdaptationProfile adaptationProfile;

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
      'adaptationProfile': adaptationProfile.toJson(),
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
      adaptationProfile: adaptationProfile,
      platformDefaultPackages: platformDefaultPackages,
      coveredByImplementationRecommendations:
          coveredByImplementationRecommendations ??
          this.coveredByImplementationRecommendations,
      defaultRecommendationExclusionReason:
          defaultRecommendationExclusionReason,
    );
  }
}

/// Capability and risk profile for a discovered package adaptation target.
class PackageAdaptationProfile {
  /// Creates a package adaptation profile.
  const PackageAdaptationProfile({
    required this.complexity,
    required this.categories,
    required this.riskReasons,
    required this.requiredEvidence,
    required this.suggestedCoverage,
    required this.officialDocsRequired,
    required this.officialDocTopics,
    this.blockerPolicy,
  });

  /// Expected adaptation complexity: `low`, `medium`, `high`, or `external`.
  final String complexity;

  /// Capability categories inferred from package metadata.
  final List<String> categories;

  /// Stable reasons why the adaptation needs special attention.
  final List<String> riskReasons;

  /// Evidence types that should be collected before release readiness.
  final List<String> requiredEvidence;

  /// Coverage rows that can seed interaction scenarios or package tests.
  final List<PackageSuggestedCoverage> suggestedCoverage;

  /// Whether official OHOS/platform documentation should be reviewed.
  final bool officialDocsRequired;

  /// Official documentation topics the adaptation should cite or disposition.
  final List<String> officialDocTopics;

  /// External blocker policy when a vendor SDK or service may be unavailable.
  final Map<String, String>? blockerPolicy;

  /// Converts this profile to JSON.
  Map<String, Object?> toJson() {
    return {
      'complexity': complexity,
      'categories': categories,
      if (riskReasons.isNotEmpty) 'riskReasons': riskReasons,
      'requiredEvidence': requiredEvidence,
      if (suggestedCoverage.isNotEmpty)
        'suggestedCoverage': suggestedCoverage
            .map((coverage) => coverage.toJson())
            .toList(),
      'officialDocsRequired': officialDocsRequired,
      if (officialDocTopics.isNotEmpty) 'officialDocTopics': officialDocTopics,
      if (blockerPolicy != null) 'blockerPolicy': blockerPolicy,
    };
  }
}

/// Suggested functional coverage for an inferred package capability.
class PackageSuggestedCoverage {
  /// Creates a suggested coverage row.
  const PackageSuggestedCoverage({
    required this.category,
    required this.item,
    required this.paths,
    required this.evidence,
  });

  /// Capability category compatible with scenario coverage metadata.
  final String category;

  /// Concrete behavior or API group to cover.
  final String item;

  /// Success, error, denied, unavailable, or lifecycle paths to cover.
  final List<String> paths;

  /// Tool-readable evidence expected from the adaptation.
  final String evidence;

  /// Converts this suggestion to JSON.
  Map<String, Object?> toJson() {
    return {
      'category': category,
      'item': item,
      'paths': paths,
      'evidence': evidence,
    };
  }
}

/// Infers a package adaptation profile from package metadata.
PackageAdaptationProfile inferPackageAdaptationProfile({
  required String name,
  String path = '.',
  String? description,
  Set<String> dependencyNames = const {},
}) {
  return _adaptationProfile(
    name: name,
    path: path,
    description: description,
    dependencyNames: dependencyNames,
  );
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
    adaptationProfile: _adaptationProfile(
      name: name,
      path: packagePath,
      description: optionalString(yaml, 'description'),
      dependencyNames: _dependencyNames(yaml),
    ),
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

PackageAdaptationProfile _adaptationProfile({
  required String name,
  required String path,
  required String? description,
  required Set<String> dependencyNames,
}) {
  final haystack = [
    name,
    path,
    ?description,
    ...dependencyNames,
  ].join(' ').toLowerCase();
  bool has(String token) => haystack.contains(token);

  final categories = <String>{};
  void add(String category) => categories.add(category);

  if (has('path_provider')) add('filesystem-path');
  if (has('shared_preferences') || has('preferences')) {
    add('key-value-storage');
  }
  if (has('url_launcher') || has('launcher')) add('external-intent');
  if (has('package_info')) add('package-metadata');
  if (has('device_info')) add('device-info');
  if (has('secure_storage') || has('secure storage')) add('secure-storage');
  if (has('file_picker') || has('file selector')) add('file-picker');
  if (has('connectivity')) add('network-state');
  if (has('share_plus') || has('share sheet')) add('share-sheet');
  if (has('permission_handler') || has('permission')) {
    add('runtime-permission');
  }
  if (has('webview')) add('webview');
  if (has('video_player') || has('audioplayers') || has('just_audio')) {
    add('media-playback');
  }
  if (has('image_picker') || has('camera') || has('photo')) {
    add('media-capture');
  }
  if (has('sqflite') || has('sqlite')) add('database');
  if (has('notification')) add('notification');
  if (has('wakelock')) add('screen-state');
  if (has('app_links') || has('deep link') || has('universal link')) {
    add('deep-link');
  }
  if (has('geolocator') || has('geocoding') || has('location')) {
    add('location');
  }
  if (has('firebase')) {
    add('firebase-service');
    add('external-service');
  }
  if (has('messaging') || has('push')) add('push-messaging');
  if (has('google_sign_in') || has('sign_in') || has('auth')) {
    add('auth');
  }
  if (has('google_maps') || has('map')) {
    add('map-view');
    if (has('google_maps')) add('external-service');
  }
  if (has('mobile_scanner') || has('barcode') || has('qr')) {
    add('camera-scanner');
  }
  if (has('local_auth') || has('biometric')) add('biometric-auth');
  if (has('in_app_purchase') || has('billing')) {
    add('store-billing');
    add('external-service');
  }
  if (has('sensor')) add('sensor-stream');
  if (has('printing') || has('printer')) add('printing');
  if (has('toast')) add('toast');
  if (has('record') || has('microphone')) add('audio-recording');

  if (categories.any(
    const {
      'media-capture',
      'camera-scanner',
      'notification',
      'location',
      'audio-recording',
      'biometric-auth',
    }.contains,
  )) {
    add('runtime-permission');
  }

  if (categories.isEmpty) {
    add('platform-channel');
  }

  final riskReasons = <String>{};
  final requiredEvidence = <String>{
    'package-tests',
    'example-page-readiness',
    'platform-build-run',
  };
  final suggestedCoverage = <PackageSuggestedCoverage>[];

  void addCoverage({
    required String category,
    required String item,
    required List<String> paths,
    required String evidence,
  }) {
    suggestedCoverage.add(
      PackageSuggestedCoverage(
        category: category,
        item: item,
        paths: paths,
        evidence: evidence,
      ),
    );
  }

  for (final category in categories) {
    switch (category) {
      case 'filesystem-path':
        requiredEvidence.add('path-exists-and-is-writable');
        addCoverage(
          category: category,
          item: 'temporary documents cache and support paths',
          paths: const ['success', 'unavailable'],
          evidence:
              'assert returned paths exist or return upstream-compatible unavailable errors',
        );
      case 'key-value-storage':
        requiredEvidence.add('read-write-delete-persistence');
        addCoverage(
          category: category,
          item: 'primitive value persistence',
          paths: const ['write-read', 'remove', 'clear'],
          evidence:
              'assert values survive plugin reinitialization and are removed when requested',
        );
      case 'external-intent':
        riskReasons.add('external-app-or-scheme-availability');
        requiredEvidence.add('external-launch-success-and-unavailable-path');
        addCoverage(
          category: category,
          item: 'launchable and unavailable URI schemes',
          paths: const ['success', 'unavailable', 'error'],
          evidence:
              'assert launch result, error shape, or explicit unsupported state',
        );
      case 'package-metadata':
        addCoverage(
          category: category,
          item: 'package identity and version fields',
          paths: const ['success'],
          evidence:
              'assert package name, version, build number, and installer fields where supported',
        );
      case 'device-info':
        requiredEvidence.add('device-info-field-coverage');
        addCoverage(
          category: category,
          item: 'device and OS metadata',
          paths: const ['success', 'field-unavailable'],
          evidence:
              'assert stable required fields and explicit null or unsupported values for unavailable fields',
        );
      case 'secure-storage':
        riskReasons.add('secure-key-store-and-persistence');
        requiredEvidence.add('secure-read-write-delete-persistence');
        addCoverage(
          category: category,
          item: 'secure value lifecycle',
          paths: const ['write-read', 'delete', 'reinstall-or-restart'],
          evidence: 'assert encrypted storage behavior and deletion semantics',
        );
      case 'file-picker':
        riskReasons.add('system-picker-ui');
        requiredEvidence.add('picker-success-cancel-error');
        addCoverage(
          category: category,
          item: 'native file picker result',
          paths: const ['single', 'multiple', 'cancel', 'type-filter'],
          evidence:
              'assert picked file metadata, cancel result, and unsupported filter handling',
        );
      case 'network-state':
        requiredEvidence.add('state-stream-update');
        addCoverage(
          category: category,
          item: 'current network state and change stream',
          paths: const ['initial-state', 'state-change', 'unavailable'],
          evidence:
              'assert current result and at least one emitted stream update or explicit environment blocker',
        );
      case 'share-sheet':
        riskReasons.add('external-system-ui');
        requiredEvidence.add('share-result-or-unavailable-path');
        addCoverage(
          category: category,
          item: 'platform share action',
          paths: const ['text', 'file', 'cancel-or-unavailable'],
          evidence:
              'assert share command result, platform UI launch, or upstream-compatible unavailable result',
        );
      case 'runtime-permission':
        riskReasons.add('runtime-permission-matrix');
        requiredEvidence.add('permission-grant-deny');
        addCoverage(
          category: category,
          item: 'runtime permission request result',
          paths: const ['grant', 'deny', 'permanently-denied', 'unsupported'],
          evidence:
              'assert permission state and behavior after grant and denied/error paths',
        );
      case 'webview':
        riskReasons.add('embedded-native-view');
        requiredEvidence.add('webview-navigation-js-lifecycle');
        addCoverage(
          category: category,
          item: 'webview navigation and JavaScript bridge',
          paths: const ['load', 'navigation-delegate', 'javascript', 'error'],
          evidence:
              'assert page load, callback logs, JavaScript result, and load error handling',
        );
      case 'media-playback':
        riskReasons.add('media-codec-texture-lifecycle');
        requiredEvidence.add('media-playback-lifecycle');
        addCoverage(
          category: category,
          item: 'media playback controller',
          paths: const ['initialize', 'play-pause', 'seek', 'dispose', 'error'],
          evidence:
              'assert controller state, duration or position, playback transitions, and error shape',
        );
      case 'media-capture':
        riskReasons.add('hardware-or-system-picker');
        requiredEvidence.add('capture-picker-success-cancel-error');
        addCoverage(
          category: category,
          item: 'camera or gallery capture result',
          paths: const [
            'capture-or-pick',
            'cancel',
            'permission-denied',
            'error',
          ],
          evidence:
              'assert returned media metadata or upstream-compatible null/error result',
        );
      case 'database':
        requiredEvidence.add('database-crud-transaction');
        addCoverage(
          category: category,
          item: 'database lifecycle and CRUD',
          paths: const [
            'open',
            'insert-query-update-delete',
            'transaction',
            'close',
          ],
          evidence:
              'assert persisted rows, transaction behavior, and close/reopen lifecycle',
        );
      case 'notification':
        riskReasons.add('notification-permission-and-background');
        requiredEvidence.add('notification-show-schedule-tap');
        addCoverage(
          category: category,
          item: 'local notification display and callback',
          paths: const ['show', 'schedule', 'tap', 'permission-denied'],
          evidence:
              'assert notification command result, callback/log evidence, and denied path',
        );
      case 'screen-state':
        requiredEvidence.add('screen-awake-toggle');
        addCoverage(
          category: category,
          item: 'wakelock enable disable state',
          paths: const ['enable', 'disable'],
          evidence: 'assert plugin state or platform flag after toggling',
        );
      case 'deep-link':
        riskReasons.add('platform-routing-configuration');
        requiredEvidence.add('deep-link-cold-warm-start');
        addCoverage(
          category: category,
          item: 'incoming app link',
          paths: const ['cold-start', 'warm-start', 'unmatched-link'],
          evidence:
              'assert delivered URI from platform launch or exact unsupported environment blocker',
        );
      case 'location':
        riskReasons.add('location-permission-and-service-state');
        requiredEvidence.add('location-grant-deny-service-disabled');
        addCoverage(
          category: category,
          item: 'current position and service state',
          paths: const [
            'grant-position',
            'deny',
            'service-disabled',
            'timeout',
          ],
          evidence:
              'assert position result, permission denied error, disabled service error, or timeout handling',
        );
      case 'firebase-service':
      case 'external-service':
        riskReasons.add('external-service-sdk');
        requiredEvidence.add('sdk-availability-and-credential-blocker');
        addCoverage(
          category: category,
          item: 'vendor SDK initialization or explicit blocker',
          paths: const [
            'sdk-available',
            'sdk-unavailable',
            'credential-missing',
          ],
          evidence:
              'record SDK availability, credential requirements, and upstream-compatible initialization result',
        );
      case 'push-messaging':
        riskReasons.add('push-provider-service');
        requiredEvidence.add('push-token-foreground-background');
        addCoverage(
          category: category,
          item: 'push token and message delivery',
          paths: const [
            'token',
            'foreground',
            'background',
            'permission-denied',
          ],
          evidence: 'assert token/callback evidence or exact provider blocker',
        );
      case 'auth':
        riskReasons.add('account-provider-or-credential-service');
        requiredEvidence.add('auth-success-cancel-error');
        addCoverage(
          category: category,
          item: 'sign-in flow',
          paths: const ['success', 'cancel', 'credential-error'],
          evidence:
              'assert account result, cancel result, or provider unavailable blocker',
        );
      case 'map-view':
        riskReasons.add('map-sdk-and-embedded-view');
        requiredEvidence.add('map-render-camera-marker');
        addCoverage(
          category: category,
          item: 'map render and camera movement',
          paths: const ['render', 'camera-update', 'marker', 'sdk-unavailable'],
          evidence:
              'assert map readiness callback, visible state, or SDK blocker',
        );
      case 'camera-scanner':
        riskReasons.add('camera-and-frame-processing');
        requiredEvidence.add('scanner-detect-permission-error');
        addCoverage(
          category: category,
          item: 'camera scanner result',
          paths: const ['detect', 'permission-denied', 'camera-unavailable'],
          evidence: 'assert decoded result or exact camera/permission blocker',
        );
      case 'biometric-auth':
        riskReasons.add('biometric-hardware-and-enrollment');
        requiredEvidence.add('biometric-success-cancel-error');
        addCoverage(
          category: category,
          item: 'biometric authentication',
          paths: const [
            'success',
            'cancel',
            'not-enrolled',
            'hardware-unavailable',
          ],
          evidence: 'assert auth result or exact hardware/enrollment blocker',
        );
      case 'store-billing':
        riskReasons.add('store-provider-and-sandbox-account');
        requiredEvidence.add('billing-query-purchase-error');
        addCoverage(
          category: category,
          item: 'store billing',
          paths: const [
            'query-products',
            'purchase',
            'restore',
            'provider-unavailable',
          ],
          evidence:
              'assert product or purchase result or store provider blocker',
        );
      case 'sensor-stream':
        requiredEvidence.add('sensor-stream-values');
        addCoverage(
          category: category,
          item: 'sensor event stream',
          paths: const ['initial-listen', 'event', 'unavailable'],
          evidence: 'assert emitted values or unsupported sensor state',
        );
      case 'printing':
        riskReasons.add('external-print-service');
        requiredEvidence.add('print-layout-preview-error');
        addCoverage(
          category: category,
          item: 'print or PDF layout action',
          paths: const ['layout', 'print', 'service-unavailable'],
          evidence:
              'assert layout callback, platform print handoff, or unavailable result',
        );
      case 'toast':
        addCoverage(
          category: category,
          item: 'toast display request',
          paths: const ['show', 'cancel-or-unavailable'],
          evidence: 'assert platform request result or app log marker',
        );
      case 'audio-recording':
        riskReasons.add('microphone-permission-and-codec');
        requiredEvidence.add('record-start-stop-permission-error');
        addCoverage(
          category: category,
          item: 'audio recording lifecycle',
          paths: const [
            'start',
            'stop',
            'permission-denied',
            'codec-unavailable',
          ],
          evidence:
              'assert output metadata, state transitions, and denied/error paths',
        );
      case 'platform-channel':
        requiredEvidence.add('public-api-success-and-error-paths');
        addCoverage(
          category: category,
          item: 'public platform channel API',
          paths: const ['success', 'error', 'unsupported'],
          evidence:
              'assert public API result, error shape, and unsupported platform behavior',
        );
    }
  }

  final sortedCategories = categories.toList()..sort();
  final sortedRiskReasons = riskReasons.toList()..sort();
  final officialDocTopics = _officialDocTopicsForCategories(categories);
  final sortedRequiredEvidence = requiredEvidence.toList()..sort();
  if (officialDocTopics.isNotEmpty) {
    sortedRequiredEvidence.add('official-platform-docs-reviewed');
    sortedRequiredEvidence.sort();
  }
  final complexity = _profileComplexity(
    categories: categories,
    riskReasons: riskReasons,
  );

  return PackageAdaptationProfile(
    complexity: complexity,
    categories: List.unmodifiable(sortedCategories),
    riskReasons: List.unmodifiable(sortedRiskReasons),
    requiredEvidence: List.unmodifiable(sortedRequiredEvidence),
    suggestedCoverage: List.unmodifiable(suggestedCoverage),
    officialDocsRequired: officialDocTopics.isNotEmpty,
    officialDocTopics: List.unmodifiable(officialDocTopics),
    blockerPolicy: riskReasons.contains('external-service-sdk')
        ? const {
            'decision': 'needsMaintainerDecisionWhenSdkUnavailable',
            'evidence':
                'Record vendor SDK availability, credentials, service account requirements, and compatible fallback or unsupported result.',
          }
        : null,
  );
}

List<String> _officialDocTopicsForCategories(Set<String> categories) {
  final topics = <String>{
    'OpenHarmony Flutter platform plugin and Platform Channel integration',
  };
  for (final category in categories) {
    final topic = switch (category) {
      'runtime-permission' =>
        'OpenHarmony permission declaration and runtime authorization',
      'media-capture' || 'camera-scanner' =>
        'OpenHarmony camera, media picker, and media library APIs',
      'file-picker' || 'filesystem-path' =>
        'OpenHarmony file picker, sandbox, and application file directories',
      'location' => 'OpenHarmony location service and permission APIs',
      'notification' =>
        'OpenHarmony notification service, permissions, and callbacks',
      'webview' => 'OpenHarmony Web component lifecycle and JavaScript bridge',
      'media-playback' =>
        'OpenHarmony media playback, texture, and lifecycle APIs',
      'audio-recording' => 'OpenHarmony microphone and audio recording APIs',
      'network-state' => 'OpenHarmony network state and connectivity APIs',
      'share-sheet' || 'external-intent' || 'deep-link' =>
        'OpenHarmony Want, URI, sharing, and application routing APIs',
      'secure-storage' => 'OpenHarmony keystore and secure storage APIs',
      'device-info' || 'package-metadata' =>
        'OpenHarmony device, bundle, and application metadata APIs',
      'database' => 'OpenHarmony data persistence and SQLite APIs',
      'screen-state' => 'OpenHarmony display and screen awake APIs',
      'firebase-service' ||
      'external-service' ||
      'push-messaging' ||
      'auth' ||
      'map-view' ||
      'store-billing' =>
        'Official vendor SDK documentation and OpenHarmony availability policy',
      'biometric-auth' => 'OpenHarmony user authentication and biometric APIs',
      'sensor-stream' => 'OpenHarmony sensor subscription APIs',
      'printing' => 'OpenHarmony print or document rendering service APIs',
      'key-value-storage' =>
        'OpenHarmony preferences or key-value storage APIs',
      'toast' => 'OpenHarmony prompt or toast UI APIs',
      'platform-channel' =>
        'OpenHarmony Flutter platform plugin and Platform Channel integration',
      _ => null,
    };
    if (topic != null) {
      topics.add(topic);
    }
  }
  return (topics.toList()..sort()).toList(growable: false);
}

String _profileComplexity({
  required Set<String> categories,
  required Set<String> riskReasons,
}) {
  if (riskReasons.contains('external-service-sdk') ||
      categories.contains('store-billing')) {
    return 'external';
  }
  if (categories.any(
    const {
      'runtime-permission',
      'webview',
      'media-capture',
      'media-playback',
      'notification',
      'location',
      'map-view',
      'camera-scanner',
      'biometric-auth',
      'push-messaging',
      'audio-recording',
    }.contains,
  )) {
    return 'high';
  }
  if (categories.any(
    const {
      'external-intent',
      'secure-storage',
      'file-picker',
      'share-sheet',
      'deep-link',
      'network-state',
      'printing',
      'sensor-stream',
    }.contains,
  )) {
    return 'medium';
  }
  return 'low';
}

Set<String> _dependencyNames(Map<String, Object?> yaml) {
  final names = <String>{};
  for (final key in const [
    'dependencies',
    'dev_dependencies',
    'dependency_overrides',
  ]) {
    final dependencies = yaml[key];
    if (dependencies is Map<String, Object?>) {
      names.addAll(dependencies.keys);
    }
  }
  return names;
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
