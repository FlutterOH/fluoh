import 'dart:io';

import 'package_discovery.dart';
import 'manifest/package_manifest.dart';
import 'package_spec.dart';

part 'package_repository_doc_sections.dart';

/// Package-specific values used when generating `FLUOH.md` context.
class PackageRepositoryDocPackage {
  /// Creates a package context descriptor.
  const PackageRepositoryDocPackage({
    required this.name,
    required this.version,
    required this.packagePath,
    this.originKind = packageOriginPorted,
    this.sdkVersion,
    this.releaseVersion,
    this.repositoryUrl,
    this.implementationRecommendation,
  });

  /// Package name from the upstream pubspec.
  final String name;

  /// Upstream package version targeted by the support work.
  final String version;

  /// Package origin kind from `fluoh.yaml`.
  final String originKind;

  /// Package path inside the FlutterOH repository.
  final String packagePath;

  /// FlutterOH SDK version targeted by the support work.
  final String? sdkVersion;

  /// FlutterOH release metadata version for this package branch.
  final String? releaseVersion;

  /// FlutterOH package repository URL, when known.
  final String? repositoryUrl;

  /// Federated implementation package recommendation, when this package is an
  /// app-facing plugin that should gain a new platform implementation package.
  final PackageImplementationRecommendation? implementationRecommendation;

  /// Recommended package verification command.
  String get verifyCommand =>
      packagePath == '.' ? 'fluoh verify' : 'fluoh verify --package $name';

  /// Command that reports the next package implementation action.
  String get nextCommand => 'fluoh package next --package $name';

  /// Command that completes the fluoh package release by creating the tag.
  String get releaseCommand => packagePath == '.'
      ? 'fluoh package release'
      : 'fluoh package release --package $name';

  /// Release gate command that validates without creating tags.
  String get releaseCheckCommand => packagePath == '.'
      ? 'fluoh package check'
      : 'fluoh package check --package $name';

  /// Command that reports package release readiness.
  String get statusCommand => packagePath == '.'
      ? 'fluoh package status'
      : 'fluoh package status --package $name';

  /// Conventional example app path for this package.
  String get examplePath =>
      packagePath == '.' ? 'example' : '$packagePath/example';

  /// Branch-local package design/spec path.
  String get specPath => packageSpecRelativePath(name);
}

/// Builds package context descriptors from a package manifest.
List<PackageRepositoryDocPackage> packageRepositoryDocPackagesForManifest(
  PackageManifest manifest,
) {
  return [
    PackageRepositoryDocPackage(
      name: manifest.package.name,
      version: manifest.package.sourceVersion,
      packagePath: manifest.package.path,
      originKind: manifest.originKind,
      sdkVersion: manifest.sdkVersion,
      releaseVersion: manifest.package.releaseVersion,
      repositoryUrl: manifest.repositoryUrl,
    ),
  ];
}

/// Builds package context descriptors from a package manifest and the current
/// checkout.
Future<List<PackageRepositoryDocPackage>>
packageRepositoryDocPackagesForCurrentCheckout({
  required Directory repository,
  required PackageManifest manifest,
}) async {
  final packages = packageRepositoryDocPackagesForManifest(manifest);
  final discovery = await discoverPackageSupportCandidates(
    repository: repository,
    missingPlatform: 'ohos',
  );
  return [
    for (final package in packages)
      PackageRepositoryDocPackage(
        name: package.name,
        version: package.version,
        packagePath: package.packagePath,
        originKind: package.originKind,
        sdkVersion: package.sdkVersion,
        releaseVersion: package.releaseVersion,
        repositoryUrl: package.repositoryUrl,
        implementationRecommendation:
            _implementationRecommendationForDocPackage(
              discovery: discovery,
              package: package,
              missingPlatform: 'ohos',
            ),
      ),
  ];
}

PackageImplementationRecommendation?
_implementationRecommendationForDocPackage({
  required PackageDiscovery discovery,
  required PackageRepositoryDocPackage package,
  required String missingPlatform,
}) {
  for (final candidate in discovery.candidates) {
    if (candidate.name == package.name &&
        candidate.path == package.packagePath) {
      return candidate.implementationRecommendation(missingPlatform);
    }
  }
  return null;
}

/// Writes the generated `FLUOH.md` package context.
///
/// This is a fluoh-owned file. It is rewritten in full, while preserving an
/// existing bottom `FlutterOH Release History` section when present.
Future<void> writeOrReplacePackageContext({
  required Directory destination,
  required List<PackageRepositoryDocPackage> packages,
}) async {
  final file = File('${destination.path}/FLUOH.md');
  final existing = await file.exists() ? await file.readAsString() : null;
  await file.writeAsString(
    updatedPackageContextContent(packages: packages, existing: existing),
  );
}

/// Writes the fixed repository-index README for spec-created package repos.
Future<void> writePackageRepositoryIndexReadme({
  required Directory destination,
  required String repositoryName,
  required String packageName,
  required String packageBranch,
}) async {
  await File('${destination.path}/README.md').writeAsString(
    packageRepositoryIndexReadmeContent(
      repositoryName: repositoryName,
      packageName: packageName,
      packageBranch: packageBranch,
    ),
  );
}

/// Builds the fixed repository-index README for `main` in created package repos.
String packageRepositoryIndexReadmeContent({
  required String repositoryName,
  required String packageName,
  required String packageBranch,
}) {
  return '''
# $repositoryName

This repository hosts FlutterOH package branches.

## Package Branches

- `$packageBranch`: `$packageName`

The default branch contains repository metadata only. Package source, examples, tests, generated fluoh context, and release metadata live on package branches.
''';
}

/// Returns full `FLUOH.md` content with current package context regenerated.
String updatedPackageContextContent({
  required List<PackageRepositoryDocPackage> packages,
  required String? existing,
}) {
  final generated = packageContextContent(
    packages: packages,
    includeTitle: true,
  );
  final existingHistory = _existingReleaseHistorySection(existing);
  if (existingHistory == null) {
    return generated;
  }
  return _contentWithReleaseHistory(generated, existingHistory);
}

String? _existingReleaseHistorySection(String? content) {
  if (content == null) {
    return null;
  }
  final match = RegExp(
    r'^## FlutterOH Release History\s*$',
    multiLine: true,
  ).firstMatch(content);
  if (match == null) {
    return null;
  }
  final history = content.substring(match.start).trimRight();
  if (history.isEmpty) {
    return null;
  }
  return '$history\n';
}

String _contentWithReleaseHistory(String generated, String releaseHistory) {
  final match = RegExp(
    r'^## FlutterOH Release History\s*$',
    multiLine: true,
  ).firstMatch(generated);
  if (match == null) {
    final separator = generated.endsWith('\n') ? '\n' : '\n\n';
    return '$generated$separator$releaseHistory';
  }
  final prefix = generated.substring(0, match.start).trimRight();
  return '$prefix\n\n$releaseHistory';
}
