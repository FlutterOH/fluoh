import 'pub_dependency_policy.dart';
import 'version_rules.dart';
import 'yaml_utils.dart';

class ProjectFluohConfig {
  const ProjectFluohConfig({
    required this.schemaVersion,
    this.sdkVersion,
    this.dependencyPolicy = const PubDependencyPolicy(),
  });

  factory ProjectFluohConfig.parse(String content) {
    final yaml = parseYamlMap(content, label: 'fluoh.yaml');
    ensureSupportedSchema(yaml);
    final sdk = yaml['sdk'];
    final sdkVersion = sdk is Map<String, Object?> && sdk['version'] != null
        ? '${sdk['version']}'
        : null;
    if (sdkVersion != null) {
      flutterVersionFromSdkVersion(sdkVersion);
    }
    return ProjectFluohConfig(
      schemaVersion: yaml['schema'] as int? ?? supportedFluohYamlSchema,
      sdkVersion: sdkVersion,
      dependencyPolicy: parsePubDependencyPolicy(yaml),
    );
  }

  final int schemaVersion;
  final String? sdkVersion;
  final PubDependencyPolicy dependencyPolicy;
}

String newProjectFluohConfigContent(String sdkVersion) {
  return [
    'schema: 1',
    '',
    'sdk:',
    '  version: $sdkVersion',
    '',
    'dependencyPolicy:',
    '  # pubspecSection controls where fluoh pub fix writes OHOS implementations:',
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
    return '${lines.join('\n')}\n';
  }

  final schemaIndex = _topLevelKeyIndex(lines, 'schema');
  final insertIndex = schemaIndex == -1 ? 0 : schemaIndex + 1;
  lines.insertAll(insertIndex, [
    if (schemaIndex != -1) '',
    'sdk:',
    '  version: $sdkVersion',
    '',
  ]);
  return '${lines.join('\n')}\n';
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
