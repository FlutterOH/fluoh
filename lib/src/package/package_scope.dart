import 'dart:convert';
import 'dart:io';

import '../schema/yaml_utils.dart';

/// Schema version for package support scope.
const packageScopeSchema = 1;

/// Kind value for package support scope.
const packageScopeKind = 'fluoh.packageScope';

const _supportValues = {
  'supported',
  'degraded',
  'preserved',
  'unsupported',
  'manualRequired',
  'notApplicable',
  'unknown',
};

const _functionalEvidenceLevels = {'functional', 'regression'};
const _implementationSupportValues = {'supported', 'degraded'};
const _evidenceSupportValues = {'supported', 'degraded', 'preserved'};

/// Returns the package support scope path relative to the repository root.
String packageScopeRelativePath(String packageName) {
  return 'doc/fluoh/$packageName/scope.yaml';
}

/// Returns the package support scope file.
File packageScopeFile(Directory repository, String packageName) {
  return File('${repository.path}/${packageScopeRelativePath(packageName)}');
}

/// Creates initial package support scope content.
String packageScopeTemplate({
  required String packageName,
  required String platform,
  List<PackageScopeSeed> seeds = const [],
}) {
  final targetPlatforms = {
    platform,
    for (final seed in seeds) seed.platform,
  }.where((value) => value.isNotEmpty).toList()..sort();
  final scopeBlock = seeds.isEmpty
      ? 'scope: []'
      : ['scope:', ..._seedScopeEntryLines(seeds)].join('\n');
  return '''
schema: $packageScopeSchema
kind: $packageScopeKind
package: $packageName
platform: $platform
targetPlatforms:
${targetPlatforms.map((value) => '  - ${_yamlScalar(value)}').join('\n')}

# This file is a support scope, not an auto-generated verdict.
# Fill P0 scope entries after reading the public Dart API, target platform
# behavior, existing implementations, examples, tests, and platform docs.
# Every P0 scope entry must include one row for each targetPlatforms entry.
$scopeBlock

# Example:
# scope:
#   - id: example_scope_entry
#     priority: p0
#     category: methodApi
#     publicApis:
#       - ExamplePlugin.exampleMethod
#     platforms:
#       $platform:
#         role: implementationTarget
#         decision:
#           support: unknown
#           confidence: low
#           reason: ''
#           sources: []
#         implementation:
#           status: planned
#           files: []
#           tasks: []
#         tests:
#           required: true
#           cases: []
#         evidence:
#           level: none
#       android:
#         role: preserveBaseline
#         decision:
#           support: preserved
#           confidence: low
#           reason: Existing upstream Android behavior must keep working.
#           sources: []
#         tests:
#           required: true
#           cases: []
#         evidence:
#           level: none
''';
}

/// One support-scope seed row extracted from the branch-local package spec.
class PackageScopeSeed {
  /// Creates a support-scope seed row.
  const PackageScopeSeed({
    required this.id,
    required this.priority,
    required this.platform,
    required this.role,
    required this.support,
    required this.reasonOrSource,
    required this.testCase,
  });

  /// Scope entry id.
  final String id;

  /// Scope priority such as `p0`.
  final String priority;

  /// Platform row to create.
  final String platform;

  /// Platform role.
  final String role;

  /// Support decision.
  final String support;

  /// Reviewed reason or source basis.
  final String reasonOrSource;

  /// Planned test case.
  final String testCase;
}

/// Extracts concrete support-scope seed rows from a package spec.
List<PackageScopeSeed> packageScopeSeedsFromSpecContent(String content) {
  final seeds = <PackageScopeSeed>[];
  var inSeedSection = false;
  for (final rawLine in const LineSplitter().convert(content)) {
    final line = rawLine.trim();
    if (line.startsWith('## ')) {
      if (line == '## Support Scope Seeds') {
        inSeedSection = true;
        continue;
      }
      if (inSeedSection) {
        break;
      }
    }
    if (!inSeedSection || !line.startsWith('|')) {
      continue;
    }
    final cells = _markdownTableCells(line);
    if (cells.length < 7 || _isMarkdownSeparatorRow(cells)) {
      continue;
    }
    final firstCell = cells.first.toLowerCase();
    if (firstCell == 'scope entry') {
      continue;
    }
    final id = _concreteSeedCell(cells[0]);
    final priority = _concreteSeedCell(cells[1])?.toLowerCase();
    final role = _concreteSeedCell(cells[3]);
    final support = _supportSeedValue(cells[4]);
    if (id == null || priority == null || role == null || support == null) {
      continue;
    }
    final reasonOrSource = _concreteSeedCell(cells[5]) ?? '';
    final testCase = _concreteSeedCell(cells[6]) ?? '';
    for (final platform in _seedPlatforms(cells[2])) {
      seeds.add(
        PackageScopeSeed(
          id: id,
          priority: priority,
          platform: platform,
          role: role,
          support: support,
          reasonOrSource: reasonOrSource,
          testCase: testCase,
        ),
      );
    }
  }
  return seeds;
}

List<String> _seedScopeEntryLines(List<PackageScopeSeed> seeds) {
  final grouped = <String, List<PackageScopeSeed>>{};
  for (final seed in seeds) {
    grouped.putIfAbsent(seed.id, () => []).add(seed);
  }
  final lines = <String>[];
  for (final entry in grouped.entries) {
    final seed = entry.value.first;
    lines
      ..add('  - id: ${_yamlScalar(entry.key)}')
      ..add('    priority: ${_yamlScalar(seed.priority)}')
      ..add('    category: packageContract')
      ..add('    publicApis: []')
      ..add('    platforms:');
    final rows = [...entry.value]
      ..sort((a, b) => a.platform.compareTo(b.platform));
    for (final row in rows) {
      lines.addAll(_seedPlatformLines(row));
    }
  }
  return lines;
}

List<String> _seedPlatformLines(PackageScopeSeed seed) {
  final lines = <String>[
    '      ${_yamlScalar(seed.platform)}:',
    '        role: ${_yamlScalar(seed.role)}',
    '        decision:',
    '          support: ${_yamlScalar(seed.support)}',
    '          confidence: low',
    '          reason: ${_yamlScalar(seed.reasonOrSource)}',
  ];
  if (_supportNeedsSources(seed.support) && seed.reasonOrSource.isNotEmpty) {
    lines
      ..add('          sources:')
      ..add('            - title: ${_yamlScalar(seed.reasonOrSource)}');
  } else {
    lines.add('          sources: []');
  }
  if (_implementationSupportValues.contains(seed.support)) {
    lines
      ..add('        implementation:')
      ..add('          status: planned')
      ..add('          files: []')
      ..add('          tasks: []');
  }
  lines
    ..add('        tests:')
    ..add('          required: true');
  if (seed.testCase.isEmpty) {
    lines.add('          cases: []');
  } else {
    lines
      ..add('          cases:')
      ..add('            - ${_yamlScalar(seed.testCase)}');
  }
  lines
    ..add('        evidence:')
    ..add('          level: none');
  return lines;
}

List<String> _markdownTableCells(String line) {
  var value = line.trim();
  if (value.startsWith('|')) {
    value = value.substring(1);
  }
  if (value.endsWith('|')) {
    value = value.substring(0, value.length - 1);
  }
  return [for (final cell in value.split('|')) cell.trim()];
}

bool _isMarkdownSeparatorRow(List<String> cells) {
  return cells.every((cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell.trim()));
}

String? _concreteSeedCell(String value) {
  final cell = value.trim();
  if (cell.isEmpty ||
      cell.contains('SPEC-TODO') ||
      (cell.startsWith('<') && cell.endsWith('>'))) {
    return null;
  }
  return cell.replaceAll(RegExp(r'^`|`$'), '').trim();
}

List<String> _seedPlatforms(String value) {
  final cell = _concreteSeedCell(value);
  if (cell == null) {
    return const [];
  }
  final platforms = {
    for (final part in cell.split(RegExp(r'[,/]+')))
      if (part.trim().isNotEmpty) part.trim(),
  }.toList()..sort();
  return platforms;
}

String? _supportSeedValue(String value) {
  final cell = _concreteSeedCell(value);
  if (cell == null || cell.contains('/')) {
    return null;
  }
  final lower = cell.toLowerCase();
  for (final support in _supportValues) {
    if (support.toLowerCase() == lower) {
      return support;
    }
  }
  return null;
}

bool _supportNeedsSources(String support) {
  return support == 'supported' ||
      support == 'degraded' ||
      support == 'preserved';
}

String _yamlScalar(String value) {
  return jsonEncode(value);
}

/// Reads and validates package support scope.
Future<PackageScopeStatus> inspectPackageScope({
  required Directory repository,
  required String packageName,
}) async {
  final file = packageScopeFile(repository, packageName);
  final relativePath = packageScopeRelativePath(packageName);
  if (!await file.exists()) {
    return PackageScopeStatus(
      path: relativePath,
      exists: false,
      packageName: packageName,
      platform: 'ohos',
      targetPlatforms: const ['ohos'],
      scopeEntryCount: 0,
      p0Count: 0,
      p0SupportedOrDegradedCount: 0,
      p0FunctionalEvidenceCount: 0,
      platformMatrix: const [],
      issues: [
        PackageScopeIssue(
          code: 'scope.missing',
          phase: 'scope',
          severity: 'actionRequired',
          message:
              'Missing package support scope. Initialize it before implementation work.',
        ),
      ],
    );
  }

  Map<String, Object?> yaml;
  try {
    yaml = parseYamlMap(await file.readAsString(), label: relativePath);
  } on FormatException catch (error) {
    return PackageScopeStatus(
      path: relativePath,
      exists: true,
      packageName: packageName,
      platform: 'ohos',
      targetPlatforms: const ['ohos'],
      scopeEntryCount: 0,
      p0Count: 0,
      p0SupportedOrDegradedCount: 0,
      p0FunctionalEvidenceCount: 0,
      platformMatrix: const [],
      issues: [
        PackageScopeIssue(
          code: 'scope.invalid_yaml',
          phase: 'scope',
          severity: 'blocked',
          message: error.message,
        ),
      ],
    );
  } on FileSystemException catch (error) {
    return PackageScopeStatus(
      path: relativePath,
      exists: true,
      packageName: packageName,
      platform: 'ohos',
      targetPlatforms: const ['ohos'],
      scopeEntryCount: 0,
      p0Count: 0,
      p0SupportedOrDegradedCount: 0,
      p0FunctionalEvidenceCount: 0,
      platformMatrix: const [],
      issues: [
        PackageScopeIssue(
          code: 'scope.read_failed',
          phase: 'scope',
          severity: 'blocked',
          message: error.message,
        ),
      ],
    );
  }

  return _PackageScopeInspector(
    path: relativePath,
    expectedPackage: packageName,
    yaml: yaml,
  ).inspect();
}

class _PackageScopeInspector {
  _PackageScopeInspector({
    required this.path,
    required this.expectedPackage,
    required this.yaml,
  });

  final String path;
  final String expectedPackage;
  final Map<String, Object?> yaml;
  final List<PackageScopeIssue> issues = [];

  PackageScopeStatus inspect() {
    final schema = yaml['schema'];
    if (schema != packageScopeSchema) {
      issues.add(
        PackageScopeIssue(
          code: 'scope.schema_invalid',
          phase: 'scope',
          severity: 'blocked',
          message: 'Expected schema $packageScopeSchema in $path.',
        ),
      );
    }
    if (yaml['kind'] != packageScopeKind) {
      issues.add(
        PackageScopeIssue(
          code: 'scope.kind_invalid',
          phase: 'scope',
          severity: 'blocked',
          message: 'Expected kind $packageScopeKind in $path.',
        ),
      );
    }
    final packageName = _string(yaml['package']) ?? expectedPackage;
    if (packageName != expectedPackage) {
      issues.add(
        PackageScopeIssue(
          code: 'scope.package_mismatch',
          phase: 'scope',
          severity: 'blocked',
          message:
              'Support scope package $packageName does not match $expectedPackage.',
        ),
      );
    }
    final platform = _string(yaml['platform']) ?? 'ohos';
    final declaredTargetPlatforms = <String>{
      platform,
      ..._stringList(yaml['targetPlatforms']),
    };
    final targetPlatforms = {...declaredTargetPlatforms};
    final rawScope = yaml['scope'];
    final scopeEntries = rawScope is List<Object?>
        ? rawScope
        : const <Object?>[];
    if (rawScope is! List<Object?>) {
      issues.add(
        PackageScopeIssue(
          code: 'scope.invalid',
          phase: 'planning',
          severity: 'blocked',
          message: 'Expected scope to be a YAML list.',
        ),
      );
    }

    var p0Count = 0;
    var p0SupportedOrDegradedCount = 0;
    var p0FunctionalEvidenceCount = 0;
    final platformMatrix = <Map<String, Object?>>[];

    for (var index = 0; index < scopeEntries.length; index += 1) {
      final rawEntry = scopeEntries[index];
      if (rawEntry is! Map<String, Object?>) {
        issues.add(
          PackageScopeIssue(
            code: 'scope.entry_invalid',
            phase: 'planning',
            severity: 'blocked',
            message: 'Scope entry $index must be a YAML object.',
          ),
        );
        continue;
      }
      final entry = _ScopeEntry(rawEntry, index);
      if (!entry.isP0) {
        continue;
      }
      p0Count += 1;
      final platformRows = entry.platformRows();
      targetPlatforms.addAll(
        platformRows
            .map((row) => row.platform)
            .where((value) => value.isNotEmpty),
      );
      platformMatrix.addAll([
        for (final row in platformRows)
          row.toJson(scopeEntryId: entry.id, scopeEntryIndex: index),
      ]);
      _inspectP0ScopeEntry(
        entry,
        platformRows,
        declaredTargetPlatforms: declaredTargetPlatforms,
      );
      if (entry.hasImplementationSupport(platformRows)) {
        p0SupportedOrDegradedCount += 1;
        if (entry.hasRequiredFunctionalEvidence(platformRows)) {
          p0FunctionalEvidenceCount += 1;
        }
      }
    }

    if (p0Count == 0) {
      issues.add(
        PackageScopeIssue(
          code: 'scope.p0_missing',
          phase: 'planning',
          severity: 'actionRequired',
          message:
              'No P0 scope entries are recorded. Confirm the minimum supported scope before implementation.',
        ),
      );
    }

    return PackageScopeStatus(
      path: path,
      exists: true,
      packageName: packageName,
      platform: platform,
      targetPlatforms: targetPlatforms.toList()..sort(),
      scopeEntryCount: scopeEntries.length,
      p0Count: p0Count,
      p0SupportedOrDegradedCount: p0SupportedOrDegradedCount,
      p0FunctionalEvidenceCount: p0FunctionalEvidenceCount,
      platformMatrix: platformMatrix,
      issues: issues,
    );
  }

  void _inspectP0ScopeEntry(
    _ScopeEntry entry,
    List<_ScopePlatformRow> platformRows, {
    required Set<String> declaredTargetPlatforms,
  }) {
    final id = entry.id;
    if (id == null) {
      issues.add(
        PackageScopeIssue(
          code: 'scope.p0_id_missing',
          phase: 'planning',
          severity: 'blocked',
          message: 'P0 scope entry ${entry.index} is missing id.',
        ),
      );
    }
    if (entry.platformsInvalid) {
      issues.add(
        PackageScopeIssue(
          code: 'scope.p0_platforms_invalid',
          phase: 'planning',
          severity: 'blocked',
          message:
              'P0 scope entry ${id ?? entry.index} has an invalid platforms matrix.',
          scopeEntry: id,
          field: 'platforms',
        ),
      );
      return;
    }
    if (platformRows.isEmpty) {
      issues.add(
        PackageScopeIssue(
          code: 'scope.p0_platforms_missing',
          phase: 'planning',
          severity: 'actionRequired',
          message:
              'P0 scope entry ${id ?? entry.index} needs at least one target platform row.',
          scopeEntry: id,
          field: 'platforms',
        ),
      );
      return;
    }
    final rowPlatforms = {
      for (final row in platformRows)
        if (row.platform.isNotEmpty) row.platform,
    };
    for (final targetPlatform in declaredTargetPlatforms) {
      if (targetPlatform.isEmpty || rowPlatforms.contains(targetPlatform)) {
        continue;
      }
      issues.add(
        PackageScopeIssue(
          code: 'scope.p0_platform_row_missing',
          phase: 'planning',
          severity: 'actionRequired',
          message:
              'P0 scope entry ${id ?? entry.index} needs a $targetPlatform platform row.',
          scopeEntry: id,
          platform: targetPlatform,
          field: 'platforms.$targetPlatform',
        ),
      );
    }
    for (final platformRow in platformRows) {
      _inspectP0Platform(entry, platformRow);
    }
  }

  void _inspectP0Platform(_ScopeEntry entry, _ScopePlatformRow platformRow) {
    final id = entry.id;
    final label = '${id ?? entry.index}/${platformRow.platform}';
    final support = platformRow.support;
    if (support == null || !_supportValues.contains(support)) {
      issues.add(
        PackageScopeIssue(
          code: 'scope.p0_support_missing',
          phase: 'research',
          severity: 'actionRequired',
          message: 'P0 scope entry $label needs a support decision.',
          scopeEntry: id,
          platform: platformRow.platform,
          field: platformRow.field('decision.support'),
        ),
      );
      return;
    }
    if (support == 'unknown') {
      issues.add(
        PackageScopeIssue(
          code: 'scope.p0_research_unknown',
          phase: 'research',
          severity: 'actionRequired',
          message: 'P0 scope entry $label is still unknown.',
          scopeEntry: id,
          platform: platformRow.platform,
          field: platformRow.field('decision.support'),
        ),
      );
      return;
    }
    if (support == 'unsupported' ||
        support == 'manualRequired' ||
        support == 'notApplicable') {
      if (platformRow.reason == null) {
        issues.add(
          PackageScopeIssue(
            code: 'scope.p0_decision_reason_missing',
            phase: 'research',
            severity: 'actionRequired',
            message: 'P0 scope entry $label needs a decision reason.',
            scopeEntry: id,
            platform: platformRow.platform,
            field: platformRow.field('decision.reason'),
          ),
        );
      }
      return;
    }
    if (platformRow.sources.isEmpty) {
      issues.add(
        PackageScopeIssue(
          code: 'scope.p0_research_sources_missing',
          phase: 'research',
          severity: 'actionRequired',
          message: 'P0 scope entry $label needs platform research sources.',
          scopeEntry: id,
          platform: platformRow.platform,
          field: platformRow.field('decision.sources'),
        ),
      );
    }
    if (platformRow.needsImplementationPlan &&
        platformRow.implementationStatus == null) {
      issues.add(
        PackageScopeIssue(
          code: 'scope.p0_implementation_plan_missing',
          phase: 'planning',
          severity: 'actionRequired',
          message: 'P0 scope entry $label needs an implementation plan status.',
          scopeEntry: id,
          platform: platformRow.platform,
          field: platformRow.field('implementation.status'),
        ),
      );
    }
    if (platformRow.testCases.isEmpty) {
      issues.add(
        PackageScopeIssue(
          code: 'scope.p0_test_cases_missing',
          phase: 'test-plan',
          severity: 'actionRequired',
          message: 'P0 scope entry $label needs test cases.',
          scopeEntry: id,
          platform: platformRow.platform,
          field: platformRow.field('tests.cases'),
        ),
      );
    }
    if (platformRow.needsFunctionalEvidence &&
        !platformRow.hasFunctionalEvidence) {
      issues.add(
        PackageScopeIssue(
          code: 'scope.p0_functional_evidence_missing',
          phase: 'functional-evidence',
          severity: 'actionRequired',
          message: 'P0 scope entry $label needs functional evidence.',
          scopeEntry: id,
          platform: platformRow.platform,
          field: platformRow.field('evidence.level'),
        ),
      );
    }
  }
}

/// Package support scope validation status.
class PackageScopeStatus {
  /// Creates a package scope status.
  const PackageScopeStatus({
    required this.path,
    required this.exists,
    required this.packageName,
    required this.platform,
    required this.targetPlatforms,
    required this.scopeEntryCount,
    required this.p0Count,
    required this.p0SupportedOrDegradedCount,
    required this.p0FunctionalEvidenceCount,
    required this.platformMatrix,
    required this.issues,
  });

  /// Support scope path relative to the repository root.
  final String path;

  /// Whether the support scope exists.
  final bool exists;

  /// Package declared by the support scope.
  final String packageName;

  /// Platform declared by the support scope.
  final String platform;

  /// Target platforms declared or inferred from the scope matrix.
  final List<String> targetPlatforms;

  /// Number of recorded scope entries.
  final int scopeEntryCount;

  /// Number of recorded P0 scope entries.
  final int p0Count;

  /// Number of P0 scope entries marked supported or degraded.
  final int p0SupportedOrDegradedCount;

  /// Number of supported/degraded P0 scope entries with functional evidence.
  final int p0FunctionalEvidenceCount;

  /// Per-scope-entry platform support matrix.
  final List<Map<String, Object?>> platformMatrix;

  /// Validation issues.
  final List<PackageScopeIssue> issues;

  /// Issues that block planning before implementation.
  List<PackageScopeIssue> get planningIssues {
    return [
      for (final issue in issues)
        if (issue.phase != 'functional-evidence') issue,
    ];
  }

  /// Issues that block functional delivery evidence.
  List<PackageScopeIssue> get functionalEvidenceIssues {
    return [
      for (final issue in issues)
        if (issue.phase == 'functional-evidence') issue,
    ];
  }

  /// Whether the support scope has enough planning to begin implementation.
  bool get planningReady => exists && planningIssues.isEmpty;

  /// Whether supported/degraded P0 scope entries have functional evidence.
  bool get functionalEvidenceReady =>
      planningReady && functionalEvidenceIssues.isEmpty;

  /// Whether the support scope is complete for support delivery.
  bool get complete => planningReady && functionalEvidenceReady;

  /// Serializes this status for JSON output.
  Map<String, Object?> toJson() {
    return {
      'path': path,
      'exists': exists,
      'package': packageName,
      'platform': platform,
      'targetPlatforms': targetPlatforms,
      'scopeEntryCount': scopeEntryCount,
      'p0Count': p0Count,
      'p0SupportedOrDegradedCount': p0SupportedOrDegradedCount,
      'p0FunctionalEvidenceCount': p0FunctionalEvidenceCount,
      'platformMatrix': platformMatrix,
      'planningReady': planningReady,
      'functionalEvidenceReady': functionalEvidenceReady,
      'complete': complete,
      'issues': [for (final issue in issues) issue.toJson()],
    };
  }
}

/// Package scope validation issue.
class PackageScopeIssue {
  /// Creates a package scope issue.
  const PackageScopeIssue({
    required this.code,
    required this.phase,
    required this.severity,
    required this.message,
    this.scopeEntry,
    this.platform,
    this.field,
  });

  /// Stable issue code.
  final String code;

  /// Support phase blocked by the issue.
  final String phase;

  /// Issue severity.
  final String severity;

  /// Human-readable issue message.
  final String message;

  /// Optional scope entry id.
  final String? scopeEntry;

  /// Optional platform name.
  final String? platform;

  /// Optional field path.
  final String? field;

  /// Serializes this issue for JSON output.
  Map<String, Object?> toJson() {
    return {
      'code': code,
      'phase': phase,
      'severity': severity,
      'message': message,
      if (scopeEntry != null) 'scopeEntry': scopeEntry,
      if (platform != null) 'platform': platform,
      if (field != null) 'field': field,
    };
  }
}

class _ScopeEntry {
  _ScopeEntry(this.yaml, this.index);

  final Map<String, Object?> yaml;
  final int index;

  String? get id => _string(yaml['id']);

  bool get isP0 => _string(yaml['priority'])?.toLowerCase() == 'p0';

  bool get platformsInvalid {
    final platforms = yaml['platforms'];
    if (platforms == null) {
      return false;
    }
    return platforms is! Map<String, Object?>;
  }

  List<_ScopePlatformRow> platformRows() {
    final platforms = _object(yaml['platforms']);
    if (platforms == null) {
      return const [];
    }
    return [
      for (final entry in platforms.entries)
        if (entry.value is Map<String, Object?>)
          _ScopePlatformRow(
            platform: entry.key,
            yaml: entry.value! as Map<String, Object?>,
          ),
    ];
  }

  bool hasImplementationSupport(List<_ScopePlatformRow> platformRows) {
    return platformRows.any(
      (row) => _implementationSupportValues.contains(row.support),
    );
  }

  bool hasRequiredFunctionalEvidence(List<_ScopePlatformRow> platformRows) {
    final requiredRows = platformRows.where(
      (row) => row.needsFunctionalEvidence,
    );
    return requiredRows.isNotEmpty &&
        requiredRows.every((row) => row.hasFunctionalEvidence);
  }
}

class _ScopePlatformRow {
  _ScopePlatformRow({required this.platform, required this.yaml});

  final String platform;
  final Map<String, Object?> yaml;

  String? get role => _string(yaml['role']);

  Map<String, Object?> get decision {
    return _object(yaml['decision']) ?? const <String, Object?>{};
  }

  String? get support {
    return _string(decision['support']);
  }

  String? get reason => _string(decision['reason']);

  List<Object?> get sources => _nonEmptyList(decision['sources']);

  bool get needsImplementationPlan {
    return _implementationSupportValues.contains(support);
  }

  bool get needsFunctionalEvidence {
    return _evidenceSupportValues.contains(support);
  }

  String? get implementationStatus {
    return _string(_object(yaml['implementation'])?['status']);
  }

  List<Object?> get testCases {
    return _nonEmptyList(_object(yaml['tests'])?['cases']);
  }

  bool get hasFunctionalEvidence {
    final level = _string(_object(yaml['evidence'])?['level']);
    return level != null && _functionalEvidenceLevels.contains(level);
  }

  String? get evidenceLevel => _string(_object(yaml['evidence'])?['level']);

  String field(String name) {
    return 'platforms.$platform.$name';
  }

  Map<String, Object?> toJson({
    required String? scopeEntryId,
    required int scopeEntryIndex,
  }) {
    return {
      'scopeEntry': scopeEntryId ?? scopeEntryIndex.toString(),
      'platform': platform,
      if (role != null) 'role': role,
      if (support != null) 'support': support,
      if (evidenceLevel != null) 'evidenceLevel': evidenceLevel,
      'needsImplementationPlan': needsImplementationPlan,
      'needsFunctionalEvidence': needsFunctionalEvidence,
      'hasFunctionalEvidence': hasFunctionalEvidence,
    };
  }
}

Map<String, Object?>? _object(Object? value) {
  return value is Map<String, Object?> ? value : null;
}

String? _string(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}

List<Object?> _nonEmptyList(Object? value) {
  if (value is! List<Object?>) {
    return const [];
  }
  return [
    for (final item in value)
      if (!_emptyItem(item)) item,
  ];
}

List<String> _stringList(Object? value) {
  if (value is! List<Object?>) {
    return const [];
  }
  return [
    for (final item in value)
      if (_string(item) case final item? when item.isNotEmpty) item,
  ];
}

bool _emptyItem(Object? item) {
  if (item == null) {
    return true;
  }
  if (item is String) {
    return item.trim().isEmpty;
  }
  if (item is Map && item.isEmpty) {
    return true;
  }
  if (item is List && item.isEmpty) {
    return true;
  }
  return false;
}
