import 'dart:io';

import 'manifest/pub_manifest.dart';

Future<void> writePubSourcePackageUpdate(
  Directory source, {
  required PubManifest manifest,
  required String releaseTag,
}) async {
  final packagesDirectory = Directory('${source.path}/packages');
  await packagesDirectory.create(recursive: true);
  await Directory(
    '${packagesDirectory.path}/manifests',
  ).create(recursive: true);

  final packagePath = manifest.upstreamPath ?? manifest.dependencyPath;
  final manifestFile = File(
    '${packagesDirectory.path}/manifests/${manifest.packageName}.yaml',
  );
  await manifestFile.writeAsString(
    [
      'schema: 1',
      'package:',
      '  name: ${manifest.packageName}',
      '  repositoryUrl: ${manifest.adapterUrl}',
      '  upstreamUrl: ${manifest.upstreamUrl}',
      if (packagePath != null) '  packagePath: $packagePath',
      'releases:',
      '  - version: ${manifest.upstreamVersion}',
      if (manifest.upstreamRef != null)
        '    upstreamRef: ${manifest.upstreamRef}',
      '    sdk:',
      '      versionSeries: ${sdkVersionSeriesFromSdkVersion(manifest.sdkVersion)}',
      '      versions:',
      '        - ${manifest.sdkVersion}',
      '    status: ${manifest.status ?? 'experimental'}',
      '    sourceBranch: ${manifest.branch}',
      '    release:',
      '      version: ${manifest.releaseVersion}',
      '      tag: $releaseTag',
      '    replacement:',
      '      type: git',
      '      url: ${manifest.dependencyUrl}',
      '      ref: $releaseTag',
      if (manifest.dependencyPath != null)
        '      path: ${manifest.dependencyPath}',
      '',
    ].join('\n'),
  );

  final registryFile = File('${packagesDirectory.path}/registry.yaml');
  if (!await registryFile.exists()) {
    await registryFile.writeAsString(
      [
        'schema: 1',
        'packages:',
        '  - name: ${manifest.packageName}',
        '    repositoryUrl: ${manifest.adapterUrl}',
        if (packagePath != null) '    packagePath: $packagePath',
        '',
      ].join('\n'),
    );
    return;
  }

  final registry = await registryFile.readAsString();
  if (RegExp(
    r'^\s*-\s+name:\s+' + RegExp.escape(manifest.packageName) + r'\s*$',
    multiLine: true,
  ).hasMatch(registry)) {
    return;
  }
  await registryFile.writeAsString(
    [
      registry.trimRight(),
      '  - name: ${manifest.packageName}',
      '    repositoryUrl: ${manifest.adapterUrl}',
      if (packagePath != null) '    packagePath: $packagePath',
      '',
    ].join('\n'),
  );
}
