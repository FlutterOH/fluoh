import 'dart:io';

import 'package:args/command_runner.dart';

import '../../schema/schema.dart';

export '../../schema/schema.dart'
    show
        PubManifest,
        PubManifestPackage,
        PubRepositoryManifest,
        PubRepositoryManifestPackage,
        defaultUpstreamBranch,
        dependencyUrlForImplementationRepository,
        flutterOhosBranchForSdk,
        initialPubReleaseVersion,
        pubManifestSchema,
        pubReleaseTagForPackage,
        sdkLineFromSdkVersion,
        sdkVersionSeriesFromSdkVersion;

Future<void> writePubManifest({
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
  String releaseVersion = initialPubReleaseVersion,
  String status = 'experimental',
}) async {
  final manifest = createPubRepositoryManifest(
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
  await writePubManifestFile(destination, manifest);
}

Future<void> writePubManifestFile(
  Directory destination,
  PubManifest manifest,
) async {
  await File(
    '${destination.path}/fluoh.yaml',
  ).writeAsString(pubRepositoryManifestContent(manifest));
}

Future<void> addPubManifestPackage({
  required Directory destination,
  required PubspecPackage package,
  required String packagePath,
  String releaseVersion = initialPubReleaseVersion,
  String status = 'experimental',
}) async {
  try {
    final manifest = await readPubManifest(destination);
    await writePubManifestFile(
      destination,
      addPubRepositoryManifestPackage(
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

Future<void> updatePubManifestUpstream({
  required Directory destination,
  required Map<String, String> packageVersions,
}) async {
  try {
    final manifest = await readPubManifest(destination);
    await writePubManifestFile(
      destination,
      updatePubRepositoryManifestUpstream(
        manifest: manifest,
        packageVersions: packageVersions,
      ),
    );
  } on FormatException catch (error) {
    throw UsageException(error.message, '');
  }
}

Future<PubManifest> readPubManifest(Directory repository) async {
  final manifest = File('${repository.path}/fluoh.yaml');
  if (!await manifest.exists()) {
    throw UsageException('Missing fluoh.yaml.', '');
  }
  try {
    return PubRepositoryManifest.parse(await manifest.readAsString());
  } on FormatException catch (error) {
    throw UsageException(error.message, '');
  }
}
