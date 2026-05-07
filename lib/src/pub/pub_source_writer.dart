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

  final packagePath = manifest.upstreamPath ?? manifest.dependencyPath ?? '.';
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
      '  packagePath: $packagePath',
      'releases:',
      '  - upstreamVersion: ${manifest.upstreamVersion}',
      if (manifest.upstreamRef != null)
        '    upstreamRef: ${manifest.upstreamRef}',
      '    sdk:',
      '      versionSeries: ${sdkVersionSeriesFromSdkVersion(manifest.sdkVersion)}',
      '      versions:',
      '        - ${manifest.sdkVersion}',
      '    status: ${manifest.status ?? 'experimental'}',
      '    fluohBranch: ${manifest.branch}',
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

  final repositoriesFile = File('${packagesDirectory.path}/repositories.yaml');
  if (!await repositoriesFile.exists()) {
    await repositoriesFile.writeAsString(
      [
        'schema: 1',
        'repositories:',
        '  - name: ${manifest.packageName}',
        '    url: ${manifest.adapterUrl}',
        '    packagePath: $packagePath',
        '',
      ].join('\n'),
    );
    return;
  }

  final repositories = await repositoriesFile.readAsString();
  if (RegExp(
    r'^\s*-\s+name:\s+' + RegExp.escape(manifest.packageName) + r'\s*$',
    multiLine: true,
  ).hasMatch(repositories)) {
    return;
  }
  final entry = [
    '  - name: ${manifest.packageName}',
    '    url: ${manifest.adapterUrl}',
    '    packagePath: $packagePath',
  ];
  final emptyRepositories = RegExp(
    r'^repositories:\s*\[\]\s*$',
    multiLine: true,
  );
  if (emptyRepositories.hasMatch(repositories)) {
    await repositoriesFile.writeAsString(
      repositories.replaceFirst(
        emptyRepositories,
        ['repositories:', ...entry].join('\n'),
      ),
    );
    return;
  }
  await repositoriesFile.writeAsString(
    [repositories.trimRight(), ...entry, ''].join('\n'),
  );
}
