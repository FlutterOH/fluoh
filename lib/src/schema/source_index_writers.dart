part of 'source_index.dart';

/// Generates canonical YAML for a Source root Manifest.
String sourceRootManifestContent(SourceRootManifestTemplate template) {
  for (final manifest in template.manifests) {
    validateDartPackageName(manifest.name, label: 'manifests[].name');
  }
  final sdkReleases = _sortedSdkReleases(template.sdkReleases);
  final manifests = _sortedManifestRoutes(template.manifests);
  final lines = [
    'schema: $sourceManifestSchema',
    'kind: source',
    'name: ${_yamlScalar(template.name)}',
    if (template.description != null)
      'description: ${_yamlScalar(template.description!)}',
    '',
    if (template.repositoryGitUrl != null) ...[
      'repository:',
      '  git:',
      '    url: ${_yamlScalar(template.repositoryGitUrl!)}',
      '',
    ],
  ];

  if (template.sdkRepository != null) {
    lines.addAll([
      'sdk:',
      '  git:',
      '    url: ${_yamlScalar(template.sdkRepository!)}',
      if (template.sdkReleases.isEmpty)
        '  versions: []'
      else ...[
        '  versions:',
        for (final release in sdkReleases)
          '    - ${_yamlScalar(release.version)}',
      ],
      '',
    ]);
  }

  if (manifests.isNotEmpty) {
    lines.add('manifests:');
    for (final manifest in manifests) {
      lines.add('  - name: ${_yamlScalar(manifest.name)}');
    }
    lines.add('');
  } else if (template.sdkRepository == null) {
    lines.addAll(['manifests: []', '']);
  }

  return lines.join('\n');
}

/// Generates canonical YAML for a package Manifest template.
String sourceManifestContent(SourceManifestTemplate template) {
  return sourceManifestToContent(
    SourceManifest(
      schemaVersion: sourceManifestSchema,
      repositoryGitUrl: template.repositoryGitUrl,
      upstreamGitUrl: template.upstreamGitUrl,
      package: SourceManifestPackage(
        name: template.package.name,
        path: template.package.path,
        sdks: {
          template.package.sdkLine: SourceManifestSdk(
            sdkLine: template.package.sdkLine,
            releases: [
              SourceManifestRelease(
                version: template.package.version,
                upstreamVersion: template.package.upstreamVersion,
                upstreamRef: template.package.upstreamRef,
                upstreamCommit: template.package.upstreamCommit,
                status: template.package.status,
              ),
            ],
          ),
        },
      ),
    ),
  );
}

/// Serializes a parsed package Manifest back to canonical YAML.
String sourceManifestToContent(SourceManifest manifest) {
  final package = manifest.package;
  validateDartPackageName(package.name, label: 'Source Manifest package.name');
  final packagePath = normalizeManifestPath(
    package.path,
    label: 'Source Manifest package.path',
  );
  final lines = [
    'schema: $sourceManifestSchema',
    'kind: manifest',
    '',
    'repository:',
    '  git:',
    '    url: ${_yamlScalar(manifest.repositoryGitUrl)}',
    '',
    'upstream:',
    '  git:',
    '    url: ${_yamlScalar(manifest.upstreamGitUrl)}',
    '',
    'package:',
    '  name: ${_yamlScalar(package.name)}',
    if (packagePath != '.') '  path: ${_yamlScalar(packagePath)}',
  ];

  lines.addAll([
    if (package.maintenance != null) ...[
      '  maintenance:',
      if (package.maintenance!.frozen) '    frozen: true',
      if (package.maintenance!.note != null)
        '    note: ${_yamlScalar(package.maintenance!.note!)}',
    ],
    if (package.advisory != null) ..._advisoryLines(package.advisory!),
    '  sdks:',
  ]);
  for (final sdk in _sortedManifestSdks(package.sdks.values)) {
    lines.addAll(['    "${sdk.sdkLine}":', '      releases:']);
    for (final release in _sortedManifestReleases(sdk.releases)) {
      validateReleaseVersion(release.version, label: 'release version');
      final upstreamVersion = _manifestPubVersion(
        release.upstreamVersion,
        label: 'release upstream.version',
      );
      final upstreamRef = release.upstreamRef == null
          ? null
          : normalizeGitRef(
              release.upstreamRef!,
              label: 'release upstream.ref',
            );
      final upstreamCommit = normalizeGitCommitHash(
        release.upstreamCommit,
        label: 'release upstream.commit',
      );
      if (!const {
        'compatible',
        'experimental',
        'broken',
      }.contains(release.status)) {
        throw const FluohSchemaException(
          'release status must be compatible, experimental, or broken.',
        );
      }
      lines.addAll([
        '        - version: ${_yamlScalar(release.version)}',
        '          upstream:',
        '            version: ${_yamlScalar(upstreamVersion)}',
        if (upstreamRef != null) '            ref: ${_yamlScalar(upstreamRef)}',
        '            commit: ${_yamlScalar(upstreamCommit)}',
        if (release.status != 'compatible')
          '          status: ${release.status}',
      ]);
    }
  }
  lines.add('');
  return lines.join('\n');
}
