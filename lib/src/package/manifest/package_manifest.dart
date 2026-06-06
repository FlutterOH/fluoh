import 'dart:io';

import 'package:args/command_runner.dart';

import '../../schema/schema.dart';

export '../../schema/schema.dart'
    show
        PackageManifest,
        PackageManifestPackage,
        defaultUpstreamBranch,
        dependencyUrlForImplementationRepository,
        flutterOhosBranchForSdk,
        flutterOhosPackageBranchForSdk,
        initialPackageReleaseVersion,
        packageManifestKind,
        packageManifestSchema,
        packageReleaseTagForPackage,
        sdkLineFromSdkVersion,
        sdkVersionSeriesFromSdkVersion,
        updatePackageManifestRelease;

/// Writes a new package repository `fluoh.yaml` manifest.
Future<void> writePackageManifest({
  required Directory destination,
  required PubspecPackage package,
  required String upstream,
  required String packagePath,
  required String sdkVersion,
  required String branch,
  required String repositoryUrl,
  required String upstreamCommit,
  String? upstreamRef,
  String upstreamBranch = defaultUpstreamBranch,
  String releaseVersion = initialPackageReleaseVersion,
  String status = 'experimental',
}) async {
  final manifest = createPackageManifest(
    package: package,
    upstream: upstream,
    packagePath: packagePath,
    sdkVersion: sdkVersion,
    branch: branch,
    repositoryUrl: repositoryUrl,
    upstreamRef: upstreamRef,
    upstreamCommit: upstreamCommit,
    upstreamBranch: upstreamBranch,
    releaseVersion: releaseVersion,
    status: status,
  );
  await writePackageManifestFile(destination, manifest);
}

/// Writes canonical manifest content to `fluoh.yaml` in [destination].
Future<void> writePackageManifestFile(
  Directory destination,
  PackageManifest manifest,
) async {
  await File(
    '${destination.path}/fluoh.yaml',
  ).writeAsString(packageManifestContent(manifest));
}

/// Updates upstream package versions in an existing manifest file.
///
/// Schema validation errors are converted to [UsageException] for CLI callers.
Future<void> updatePackageManifestUpstream({
  required Directory destination,
  required Map<String, String> packageVersions,
  String? upstreamRef,
  String? upstreamCommit,
  bool clearUpstreamRef = false,
}) async {
  try {
    final manifest = await readPackageManifest(destination);
    await writePackageManifestFile(
      destination,
      updatePackageManifestUpstreamVersions(
        manifest: manifest,
        packageVersions: packageVersions,
        upstreamRef: upstreamRef,
        upstreamCommit: upstreamCommit,
        clearUpstreamRef: clearUpstreamRef,
      ),
    );
  } on FormatException catch (error) {
    throw UsageException(error.message, '');
  }
}

/// Reads and validates `fluoh.yaml` from a package repository.
Future<PackageManifest> readPackageManifest(Directory repository) async {
  final manifest = File('${repository.path}/fluoh.yaml');
  if (!await manifest.exists()) {
    throw UsageException('Missing fluoh.yaml.', '');
  }
  try {
    return PackageManifest.parse(await manifest.readAsString());
  } on FormatException catch (error) {
    throw UsageException(error.message, '');
  }
}
