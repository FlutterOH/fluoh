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

  final packagePath = manifest.dependencyPath ?? '.';
  final upstreamPath = manifest.upstreamPath ?? '.';
  final sourceManifestFile = File(
    '${packagesDirectory.path}/manifests/${manifest.packageName}.yaml',
  );
  await sourceManifestFile.writeAsString(
    [
      'schema: 1',
      'package:',
      '  name: ${manifest.packageName}',
      '  git:',
      '    url: ${manifest.adapterUrl}',
      if (packagePath != '.') '    path: $packagePath',
      'upstream:',
      '  git:',
      '    url: ${manifest.upstreamUrl}',
      if (upstreamPath != '.') '    path: $upstreamPath',
      'releases:',
      '  - upstream:',
      '      version: ${manifest.upstreamVersion}',
      if (manifest.upstreamRef != null) ...[
        '      git:',
        '        ref: ${manifest.upstreamRef}',
      ],
      '    package:',
      '      version: ${manifest.releaseVersion}',
      '      git:',
      '        ref: ${manifest.branch}',
      '    sdk:',
      '      versionSeries: ${sdkVersionSeriesFromSdkVersion(manifest.sdkVersion)}',
      '      versions:',
      '        - ${manifest.sdkVersion}',
      '    status: ${manifest.status ?? 'experimental'}',
      '    replacement:',
      '      git:',
      '        url: ${manifest.dependencyUrl}',
      '        ref: $releaseTag',
      if (manifest.dependencyPath != null)
        '        path: ${manifest.dependencyPath}',
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
        '    path: $packagePath',
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
    '    path: $packagePath',
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
