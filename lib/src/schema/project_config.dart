import 'dependency_policy.dart';
import 'version_rules.dart';
import 'yaml_utils.dart';

/// Current project `fluoh.yaml` schema version.
const projectConfigSchema = 1;

/// Project manifest kind.
const projectConfigKind = 'project';

/// Parsed project-level `fluoh.yaml` configuration.
class ProjectFluohConfig {
  /// Creates a project configuration value.
  const ProjectFluohConfig({
    required this.schemaVersion,
    this.sdkVersion,
    this.dependencyPolicy = const DependencyPolicy(),
  });

  /// Parses project `fluoh.yaml` content.
  factory ProjectFluohConfig.parse(String content) {
    final yaml = parseYamlMap(content, label: 'fluoh.yaml');
    _ensureProjectConfigSchema(yaml);
    ensureAllowedKeys(yaml, 'fluoh.yaml', {
      'schema',
      'kind',
      'sdk',
      'dependencyPolicy',
    });
    final kind = requiredString(yaml, 'kind');
    if (kind != projectConfigKind) {
      throw FluohSchemaException('fluoh.yaml kind must be $projectConfigKind.');
    }
    final sdk = objectMap(yaml['sdk'], 'fluoh.yaml sdk');
    ensureAllowedKeys(sdk, 'fluoh.yaml sdk', {'version'});
    final sdkVersion = requiredString(sdk, 'version');
    flutterVersionFromSdkVersion(sdkVersion);
    return ProjectFluohConfig(
      schemaVersion: yaml['schema'] as int,
      sdkVersion: sdkVersion,
      dependencyPolicy: parseDependencyPolicy(yaml),
    );
  }

  /// Schema version declared by the project config.
  final int schemaVersion;

  /// Selected FlutterOH SDK version, when configured.
  final String? sdkVersion;

  /// Dependency rewrite policy for this project.
  final DependencyPolicy dependencyPolicy;
}

/// Creates a new project `fluoh.yaml` for [sdkVersion].
String newProjectFluohConfigContent(String sdkVersion) {
  return [
    'schema: $projectConfigSchema',
    'kind: $projectConfigKind',
    '',
    'sdk:',
    '  version: $sdkVersion',
    '',
    'dependencyPolicy:',
    '  # pubspecSection controls where fluoh deps fix writes OHOS implementations:',
    '  # - dependency_overrides: add dependency_overrides without changing dependencies.',
    '  # - dependencies: replace matching entries in dependencies directly.',
    '  pubspecSection: dependency_overrides',
    '  # versionChanges controls version differences after exact matches and compatible upgrades:',
    '  # - compatible: leave incompatible version changes and downgrades for manual review.',
    '  # - any: apply the recommended implementation anyway.',
    '  versionChanges: compatible',
    '',
  ].join('\n');
}

/// Inserts or updates `sdk.version` in project `fluoh.yaml` content.
String upsertProjectSdkVersion(String content, String sdkVersion) {
  final lines = content.split('\n');
  if (content.endsWith('\n')) {
    lines.removeLast();
  }

  final sdkIndex = _topLevelKeyIndex(lines, 'sdk');
  if (sdkIndex != -1) {
    if (_isTopLevelBlockSection(lines[sdkIndex], 'sdk')) {
      _upsertSdkVersion(lines, sdkIndex, sdkVersion);
    } else {
      lines[sdkIndex] = 'sdk:';
      lines.insert(sdkIndex + 1, '  version: $sdkVersion');
    }
    _ensureSchemaLine(lines);
    _ensureKindLine(lines);
    return '${lines.join('\n')}\n';
  }

  final schemaIndex = _topLevelKeyIndex(lines, 'schema');
  if (schemaIndex == -1) {
    lines.insertAll(0, [
      'schema: $projectConfigSchema',
      'kind: $projectConfigKind',
      '',
    ]);
  } else {
    _ensureKindLine(lines);
  }
  final kindIndex = _topLevelKeyIndex(lines, 'kind');
  final insertIndex =
      (kindIndex == -1 ? _topLevelKeyIndex(lines, 'schema') : kindIndex) + 1;
  lines.insertAll(insertIndex, ['', 'sdk:', '  version: $sdkVersion', '']);
  return '${lines.join('\n')}\n';
}

void _ensureSchemaLine(List<String> lines) {
  if (_topLevelKeyIndex(lines, 'schema') != -1) {
    return;
  }
  lines.insertAll(0, ['schema: $projectConfigSchema', '']);
}

void _ensureKindLine(List<String> lines) {
  final kindIndex = _topLevelKeyIndex(lines, 'kind');
  if (kindIndex != -1) {
    lines[kindIndex] = 'kind: $projectConfigKind';
    return;
  }
  final schemaIndex = _topLevelKeyIndex(lines, 'schema');
  if (schemaIndex == -1) {
    lines.insertAll(0, [
      'schema: $projectConfigSchema',
      'kind: $projectConfigKind',
      '',
    ]);
    return;
  }
  lines.insert(schemaIndex + 1, 'kind: $projectConfigKind');
}

void _upsertSdkVersion(List<String> lines, int sdkIndex, String sdkVersion) {
  final end = _topLevelSectionEnd(lines, sdkIndex);
  for (var i = sdkIndex + 1; i < end; i += 1) {
    final match = RegExp(
      r'^([ \t]+)version\s*:(?:\s*[^#]*)?(\s+#.*)?$',
    ).firstMatch(lines[i]);
    if (match == null) {
      continue;
    }
    lines[i] = '${match.group(1)}version: $sdkVersion${match.group(2) ?? ''}';
    return;
  }

  lines.insert(sdkIndex + 1, '  version: $sdkVersion');
}

int _topLevelKeyIndex(List<String> lines, String name) {
  return lines.indexWhere(
    (line) => RegExp('^${RegExp.escape(name)}:(?:\\s.*)?\$').hasMatch(line),
  );
}

bool _isTopLevelBlockSection(String line, String name) {
  return RegExp('^${RegExp.escape(name)}:\\s*(?:#.*)?\$').hasMatch(line);
}

int _topLevelSectionEnd(List<String> lines, int sectionIndex) {
  for (var i = sectionIndex + 1; i < lines.length; i += 1) {
    final line = lines[i];
    if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('\t')) {
      return i;
    }
  }
  return lines.length;
}

void _ensureProjectConfigSchema(Map<String, Object?> yaml) {
  final schema = yaml['schema'];
  if (schema == null) {
    throw const FluohSchemaException('fluoh.yaml missing "schema".');
  }
  if (schema is! int) {
    throw const FluohSchemaException('fluoh.yaml schema must be an integer.');
  }
  if (schema > projectConfigSchema) {
    throw FluohSchemaException(
      'fluoh.yaml schema $schema requires a newer fluoh.',
    );
  }
  if (schema < projectConfigSchema) {
    throw FluohSchemaException(
      'fluoh.yaml schema $schema is not supported for projects. Expected '
      'schema $projectConfigSchema.',
    );
  }
}
