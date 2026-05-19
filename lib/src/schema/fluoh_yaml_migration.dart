import 'yaml_utils.dart';
import 'version_rules.dart';

enum FluohYamlOwner { project, pubRepository, sourceRoot, sourceManifest }

class FluohYamlMigrationResult {
  const FluohYamlMigrationResult({
    required this.yaml,
    required this.migrated,
    this.changes = const <String>[],
  });

  final Map<String, Object?> yaml;
  final bool migrated;
  final List<String> changes;
}

FluohYamlMigrationResult migrateFluohYamlMap(
  Map<String, Object?> yaml, {
  required FluohYamlOwner owner,
  String label = 'fluoh.yaml',
  String? releaseTag,
}) {
  return switch (owner) {
    FluohYamlOwner.project => _migrateProjectYaml(yaml, label),
    FluohYamlOwner.pubRepository => _migratePubRepositoryYaml(
      yaml,
      label,
      releaseTag: releaseTag,
    ),
    FluohYamlOwner.sourceRoot => _migrateSourceRootYaml(yaml, label),
    FluohYamlOwner.sourceManifest => _migrateSourceManifestYaml(yaml, label),
  };
}

FluohYamlMigrationResult migrateFluohYamlContent(
  String content, {
  required FluohYamlOwner owner,
  String label = 'fluoh.yaml',
  String? releaseTag,
}) {
  return migrateFluohYamlMap(
    parseYamlMap(content, label: label),
    owner: owner,
    label: label,
    releaseTag: releaseTag,
  );
}

FluohYamlMigrationResult _migrateProjectYaml(
  Map<String, Object?> yaml,
  String label,
) {
  final next = _deepCopyMap(yaml);
  final changes = <String>[];
  final schema = next['schema'];
  if (schema == null && _looksLikeLegacyProjectYaml(next)) {
    next['schema'] = supportedFluohYamlSchema;
    changes.add('Added project schema.');
  } else {
    _ensureReadableSchema(next, label);
  }
  if (next['sdk'] is String) {
    next['sdk'] = {'version': next['sdk']};
    changes.add('Converted project sdk scalar to sdk.version.');
  }
  return FluohYamlMigrationResult(
    yaml: next,
    migrated: changes.isNotEmpty,
    changes: changes,
  );
}

FluohYamlMigrationResult _migratePubRepositoryYaml(
  Map<String, Object?> yaml,
  String label, {
  String? releaseTag,
}) {
  _ensureReadableSchema(yaml, label);
  final next = _deepCopyMap(yaml);
  final changes = <String>[];
  final sdkVersion = _stringValue(_objectValue(next['sdk'])?['version']);

  if (_migrateGitBlock(next, 'repository', refKey: 'ref')) {
    changes.add('Converted repository URL/ref to repository.git.');
  }
  if (_migrateGitBlock(next, 'upstream', refKey: 'defaultBranch')) {
    changes.add('Converted upstream URL/defaultBranch to upstream.git.');
  }

  final packages = next['packages'];
  if (packages is Map<String, Object?>) {
    for (final entry in packages.entries.toList(growable: false)) {
      final value = entry.value;
      if (value is! Map<String, Object?>) {
        continue;
      }
      final changed = _migratePubRepositoryPackage(
        value,
        packageName: entry.key,
        sdkVersion: sdkVersion,
        releaseTag: releaseTag,
        label: '$label packages.${entry.key}',
      );
      if (changed) {
        packages[entry.key] = value;
        changes.add('Converted package ${entry.key} release metadata.');
      }
    }
  }

  return FluohYamlMigrationResult(
    yaml: next,
    migrated: changes.isNotEmpty,
    changes: changes,
  );
}

FluohYamlMigrationResult _migrateSourceRootYaml(
  Map<String, Object?> yaml,
  String label,
) {
  _ensureReadableSchema(yaml, label);
  final next = _deepCopyMap(yaml);
  final changes = <String>[];
  final hasCurrentRepository =
      next['repository'] is Map<String, Object?> &&
      (next['repository']! as Map<String, Object?>)['git']
          is Map<String, Object?>;
  final repositoryUrl = _stringValue(next['repositoryUrl']);
  final repository = next['repository'];
  final hasPackageFields =
      next.containsKey('upstream') ||
      next.containsKey('packages') ||
      next.containsKey('package');
  if (hasPackageFields) {
    return FluohYamlMigrationResult(yaml: next, migrated: false);
  }

  if (next['kind'] == null &&
      (repositoryUrl != null || hasCurrentRepository || repository is String)) {
    next['kind'] = 'source';
    changes.add('Added source kind.');
  }
  if (repositoryUrl != null) {
    next.remove('repositoryUrl');
    next['repository'] = {
      'git': {'url': repositoryUrl},
    };
    changes.add('Converted repositoryUrl to repository.git.url.');
  } else if (repository is String) {
    next['repository'] = {
      'git': {'url': repository},
    };
    changes.add('Converted source repository scalar to repository.git.url.');
  } else if (repository is Map<String, Object?> &&
      repository['git'] is! Map<String, Object?> &&
      _stringValue(repository['url']) != null) {
    next['repository'] = {
      'git': {'url': _stringValue(repository['url'])},
    };
    changes.add('Converted source repository URL to repository.git.');
  }

  return FluohYamlMigrationResult(
    yaml: next,
    migrated: changes.isNotEmpty,
    changes: changes,
  );
}

FluohYamlMigrationResult _migrateSourceManifestYaml(
  Map<String, Object?> yaml,
  String label,
) {
  _ensureReadableSchema(yaml, label);
  final next = _deepCopyMap(yaml);
  final changes = <String>[];

  if (next['kind'] == null && _looksLikeCurrentSourceManifest(next)) {
    next['kind'] = 'manifest';
    changes.add('Added manifest kind.');
  }

  final package = next['package'];
  final releases = next['releases'];
  if (package is Map<String, Object?> && releases is List<Object?>) {
    final name = _stringValue(package['name']);
    final packageGit = _objectValue(package['git']);
    final upstream = _objectValue(next['upstream']);
    final upstreamGit = _objectValue(upstream?['git']);
    if (name != null && packageGit != null && upstreamGit != null) {
      final sdkReleases = <String, List<Map<String, Object?>>>{};
      for (final release in releases) {
        if (release is! Map<String, Object?>) {
          continue;
        }
        final sdk = _objectValue(release['sdk']);
        final upstreamRelease = _objectValue(release['upstream']);
        final packageRelease = _objectValue(release['package']);
        final sdkLine = _stringValue(sdk?['versionSeries']);
        final upstreamVersion = _stringValue(upstreamRelease?['version']);
        final version = _stringValue(packageRelease?['version']);
        if (sdkLine == null || upstreamVersion == null || version == null) {
          continue;
        }
        sdkReleases.putIfAbsent(sdkLine, () => <Map<String, Object?>>[]).add({
          'version': version,
          'upstreamVersion': upstreamVersion,
          if (_stringValue(release['status']) != null)
            'status': _stringValue(release['status']),
        });
      }
      next
        ..remove('package')
        ..remove('releases')
        ..['kind'] = 'manifest'
        ..['name'] = name
        ..['repository'] = {
          'git': {
            'url': packageGit['url'],
            if (_stringValue(packageGit['path']) != null)
              'path': _stringValue(packageGit['path']),
          },
        }
        ..['upstream'] = {
          'git': {
            'url': upstreamGit['url'],
            if (_stringValue(upstreamGit['branch']) != null)
              'branch': _stringValue(upstreamGit['branch']),
            if (_stringValue(upstreamGit['path']) != null)
              'path': _stringValue(upstreamGit['path']),
          },
        }
        ..['packages'] = {
          name: {
            'sdks': {
              for (final entry in sdkReleases.entries)
                entry.key: {'releases': entry.value},
            },
          },
        };
      changes.add('Converted legacy package release list to manifest sdks.');
    }
  }

  return FluohYamlMigrationResult(
    yaml: next,
    migrated: changes.isNotEmpty,
    changes: changes,
  );
}

bool _migrateGitBlock(
  Map<String, Object?> yaml,
  String key, {
  required String refKey,
}) {
  final value = yaml[key];
  if (value is! Map<String, Object?> || value['git'] is Map<String, Object?>) {
    return false;
  }
  final url = _stringValue(value['url']);
  if (url == null) {
    return false;
  }
  final git = <String, Object?>{
    'url': url,
    if (_stringValue(value[refKey]) != null)
      'branch': _stringValue(value[refKey]),
    if (_stringValue(value['branch']) != null)
      'branch': _stringValue(value['branch']),
    if (_stringValue(value['path']) != null)
      'path': _stringValue(value['path']),
  };
  yaml[key] = {'git': git};
  return true;
}

bool _migratePubRepositoryPackage(
  Map<String, Object?> package, {
  required String packageName,
  required String? sdkVersion,
  required String? releaseTag,
  required String label,
}) {
  var changed = false;
  final path = _stringValue(package['path']);
  if (path != null) {
    package.remove('path');
    package['repository'] = {'path': path};
    changed = true;
  }

  final packageUpstream = _objectValue(package['upstream']);
  final upstreamVersion = _stringValue(packageUpstream?['version']);
  if (upstreamVersion != null) {
    package['upstreamVersion'] = upstreamVersion;
    final upstreamPath = _stringValue(packageUpstream?['path']);
    if (upstreamPath != null) {
      package['upstream'] = {'path': upstreamPath};
    } else {
      package.remove('upstream');
    }
    changed = true;
  }

  final releases = package['releases'];
  if (releases is List<Object?> && releases.isNotEmpty) {
    final release = _selectPubRepositoryRelease(
      releases,
      packageName: packageName,
      sdkVersion: sdkVersion,
      releaseTag: releaseTag,
      label: label,
    );
    final upstream = _objectValue(release?['upstream']);
    final packageRelease = _objectValue(release?['release']);
    final version = _stringValue(packageRelease?['version']);
    final releaseUpstreamVersion = _stringValue(upstream?['version']);
    if (version != null) {
      package['version'] = version;
    }
    if (releaseUpstreamVersion != null) {
      package['upstreamVersion'] = releaseUpstreamVersion;
    }
    final status =
        _stringValue(packageRelease?['status']) ??
        _stringValue(release?['status']);
    if (status != null) {
      package['status'] = status;
    }
    package.remove('releases');
    changed = true;
  }

  final release = _objectValue(package['release']);
  if (release != null) {
    final version = _stringValue(release['version']);
    if (version != null) {
      package['version'] = version;
    }
    final status = _stringValue(release['status']);
    if (status != null) {
      package['status'] = status;
    }
    package.remove('release');
    changed = true;
  }

  return changed;
}

Map<String, Object?>? _selectPubRepositoryRelease(
  List<Object?> values, {
  required String packageName,
  required String? sdkVersion,
  required String? releaseTag,
  required String label,
}) {
  final releases = [
    for (final value in values)
      if (value is Map<String, Object?>) value,
  ];
  if (releases.isEmpty) {
    return null;
  }
  if (releaseTag == null) {
    if (releases.length == 1) {
      return releases.single;
    }
    throw FluohSchemaException(
      '$label releases cannot be migrated without a release tag.',
    );
  }
  if (sdkVersion == null) {
    throw FluohSchemaException(
      '$label releases cannot be matched to $releaseTag without sdk.version.',
    );
  }
  for (final release in releases) {
    final upstreamVersion = _stringValue(
      _objectValue(release['upstream'])?['version'],
    );
    final version = _stringValue(_objectValue(release['release'])?['version']);
    if (upstreamVersion == null || version == null) {
      continue;
    }
    final candidates = {
      pubReleaseTagForPackage(
        packageName: packageName,
        upstreamVersion: upstreamVersion,
        sdkVersion: sdkVersion,
        releaseVersion: version,
      ),
      legacyPubReleaseTagForPackage(
        packageName: packageName,
        upstreamVersion: upstreamVersion,
        sdkVersion: sdkVersion,
        releaseVersion: version,
      ),
    };
    if (candidates.contains(releaseTag)) {
      return release;
    }
  }
  throw FluohSchemaException(
    '$label releases do not contain release tag $releaseTag.',
  );
}

void _ensureReadableSchema(Map<String, Object?> yaml, String label) {
  final schema = yaml['schema'];
  if (schema == null) {
    throw FluohSchemaException('$label missing "schema".');
  }
  if (schema is! int) {
    throw FluohSchemaException('$label schema must be an integer.');
  }
  if (schema > supportedFluohYamlSchema) {
    throw FluohSchemaException(
      '$label schema $schema requires a newer fluoh. Current fluoh supports '
      'schema $supportedFluohYamlSchema.',
    );
  }
  if (schema < supportedFluohYamlSchema) {
    throw FluohSchemaException(
      '$label schema $schema is not supported. Expected schema '
      '$supportedFluohYamlSchema.',
    );
  }
}

bool _looksLikeLegacyProjectYaml(Map<String, Object?> yaml) {
  return !yaml.containsKey('kind') &&
      !yaml.containsKey('repository') &&
      !yaml.containsKey('upstream') &&
      !yaml.containsKey('packages') &&
      !yaml.containsKey('package') &&
      (yaml.containsKey('sdk') || yaml.containsKey('dependencyPolicy'));
}

bool _looksLikeCurrentSourceManifest(Map<String, Object?> yaml) {
  return yaml['repository'] is Map<String, Object?> &&
      yaml['upstream'] is Map<String, Object?> &&
      yaml['packages'] is Map<String, Object?>;
}

Map<String, Object?> _deepCopyMap(Map<String, Object?> value) {
  return {
    for (final entry in value.entries) entry.key: _deepCopyValue(entry.value),
  };
}

Object? _deepCopyValue(Object? value) {
  if (value is Map<String, Object?>) {
    return _deepCopyMap(value);
  }
  if (value is List<Object?>) {
    return [for (final item in value) _deepCopyValue(item)];
  }
  return value;
}

Map<String, Object?>? _objectValue(Object? value) {
  return value is Map<String, Object?> ? value : null;
}

String? _stringValue(Object? value) {
  if (value == null || '$value'.isEmpty) {
    return null;
  }
  return '$value';
}
