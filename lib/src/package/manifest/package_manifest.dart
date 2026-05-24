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
        initialPackageReleaseVersion,
        packageManifestSchema,
        packageReleaseTagForPackage,
        sdkLineFromSdkVersion,
        sdkVersionSeriesFromSdkVersion;

Future<void> writePackageManifest({
  required Directory destination,
  required PubspecPackage package,
  required String upstream,
  required String packagePath,
  required String sdkVersion,
  required String branch,
  required String repositoryUrl,
  String? name,
  String? dependencyPath,
  String? upstreamPath,
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
    name: name,
    repositoryPath: dependencyPath,
    upstreamPath: upstreamPath,
    upstreamBranch: upstreamBranch,
    releaseVersion: releaseVersion,
    status: status,
  );
  await writePackageManifestFile(destination, manifest);
}

Future<void> writePackageManifestFile(
  Directory destination,
  PackageManifest manifest,
) async {
  await File(
    '${destination.path}/fluoh.yaml',
  ).writeAsString(packageManifestContent(manifest));
}

Future<void> addPackageManifestPackage({
  required Directory destination,
  required PubspecPackage package,
  required String packagePath,
  String releaseVersion = initialPackageReleaseVersion,
  String status = 'experimental',
}) async {
  try {
    final manifest = await readPackageManifest(destination);
    await writePackageManifestFile(
      destination,
      addPackageToManifest(
        manifest: manifest,
        package: package,
        packagePath: packagePath,
        releaseVersion: releaseVersion,
        status: status,
      ),
    );
  } on FormatException catch (error) {
    throw UsageException(error.message, '');
  }
}

Future<void> updatePackageManifestUpstream({
  required Directory destination,
  required Map<String, String> packageVersions,
}) async {
  try {
    final manifest = await readPackageManifest(destination);
    await writePackageManifestFile(
      destination,
      updatePackageManifestUpstreamVersions(
        manifest: manifest,
        packageVersions: packageVersions,
      ),
    );
  } on FormatException catch (error) {
    throw UsageException(error.message, '');
  }
}

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
