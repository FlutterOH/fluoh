import 'dart:io';

import '../schema/yaml_utils.dart' show parseYamlMap;
import '../task/task_workspace.dart';

/// Schema version for visual page-readiness evidence.
const visualPageReadinessSchema = 1;

/// Kind value for visual page-readiness evidence.
const visualPageReadinessKind = 'fluoh.visualPageReadiness';

const _readyStatuses = {'passed', 'notApplicable'};
const _blockedStatuses = {'blocked', 'failed'};

/// Returns the visual page-readiness path relative to the repository root.
String visualPageReadinessRelativePath(String packageName) {
  return '.fluoh/tasks/<task-id>/evidence/visual-readiness.yaml';
}

/// Returns a starter visual page-readiness evidence document.
String visualPageReadinessTemplate(String packageName) {
  return '''
schema: $visualPageReadinessSchema
kind: $visualPageReadinessKind
package: $packageName
platform: ohos
status: passed
screenshots:
  - .fluoh/tasks/<task-id>/evidence/screenshots/$packageName-ohos-post-launch.jpeg
uiStateEvidence: []
result: Screenshot shows the functional demo page, not a blank, splash-only, or template shell.
''';
}

/// Reads and validates visual page-readiness evidence.
Future<VisualPageReadinessStatus> inspectVisualPageReadiness({
  required Directory repository,
  required String packageName,
  required bool isRequired,
}) async {
  final task = await TaskWorkspace.project(repository).current();
  final relativePath = task == null
      ? visualPageReadinessRelativePath(packageName)
      : '${task.relativePath(repository)}/evidence/visual-readiness.yaml';
  final file = task == null
      ? File('${repository.path}/$relativePath')
      : File('${task.evidenceDirectory.path}/visual-readiness.yaml');
  if (!await file.exists()) {
    return VisualPageReadinessStatus(
      path: relativePath,
      isRequired: isRequired,
      exists: false,
      issues: isRequired
          ? const [
              {
                'code': 'visual_page_readiness.missing',
                'severity': 'actionRequired',
                'message':
                    'Missing visual page-readiness evidence after a passed mobile run.',
              },
            ]
          : const [],
    );
  }

  Map<String, Object?> yaml;
  try {
    yaml = parseYamlMap(await file.readAsString(), label: relativePath);
  } on FormatException catch (error) {
    return VisualPageReadinessStatus(
      path: relativePath,
      isRequired: isRequired,
      exists: true,
      issues: [
        {
          'code': 'visual_page_readiness.invalid_yaml',
          'severity': 'blocked',
          'message': error.message,
        },
      ],
    );
  } on FileSystemException catch (error) {
    return VisualPageReadinessStatus(
      path: relativePath,
      isRequired: isRequired,
      exists: true,
      issues: [
        {
          'code': 'visual_page_readiness.read_failed',
          'severity': 'blocked',
          'message': error.message,
        },
      ],
    );
  }

  final issues = <Map<String, Object?>>[];
  final schema = yaml['schema'];
  if (schema != visualPageReadinessSchema) {
    issues.add({
      'code': 'visual_page_readiness.schema_invalid',
      'severity': 'blocked',
      'message': 'Expected schema $visualPageReadinessSchema in $relativePath.',
    });
  }
  if (yaml['kind'] != visualPageReadinessKind) {
    issues.add({
      'code': 'visual_page_readiness.kind_invalid',
      'severity': 'blocked',
      'message': 'Expected kind $visualPageReadinessKind in $relativePath.',
    });
  }
  final recordedPackage = _string(yaml['package']);
  if (recordedPackage != null && recordedPackage != packageName) {
    issues.add({
      'code': 'visual_page_readiness.package_mismatch',
      'severity': 'blocked',
      'message':
          'Visual page-readiness package $recordedPackage does not match $packageName.',
    });
  }
  final status = _string(yaml['status']);
  if (status == null) {
    issues.add({
      'code': 'visual_page_readiness.status_missing',
      'severity': 'actionRequired',
      'message': 'Record status as passed, blocked, failed, or notApplicable.',
    });
  } else if (!_readyStatuses.contains(status) &&
      !_blockedStatuses.contains(status)) {
    issues.add({
      'code': 'visual_page_readiness.status_invalid',
      'severity': 'blocked',
      'message': 'Unsupported visual page-readiness status $status.',
    });
  } else if (_blockedStatuses.contains(status)) {
    issues.add({
      'code': 'visual_page_readiness.blocked',
      'severity': 'blocked',
      'message':
          'Visual page-readiness is blocked; repair the example page before delivery.',
    });
  }

  final screenshots = _stringList(yaml['screenshots']);
  final uiStateEvidence = _stringList(yaml['uiStateEvidence']);
  final result =
      _string(yaml['result']) ??
      _string(yaml['summary']) ??
      _string(yaml['reason']);
  if (status == 'passed' && screenshots.isEmpty && uiStateEvidence.isEmpty) {
    issues.add({
      'code': 'visual_page_readiness.evidence_missing',
      'severity': 'actionRequired',
      'message':
          'Passed visual page-readiness needs at least one screenshot or UI-state evidence path.',
    });
  }
  if (status == 'notApplicable' && result == null) {
    issues.add({
      'code': 'visual_page_readiness.reason_missing',
      'severity': 'actionRequired',
      'message': 'notApplicable visual page-readiness needs a reason.',
    });
  }

  return VisualPageReadinessStatus(
    path: relativePath,
    isRequired: isRequired,
    exists: true,
    status: status,
    packageName: recordedPackage,
    platform: _string(yaml['platform']),
    result: result,
    screenshots: screenshots,
    uiStateEvidence: uiStateEvidence,
    issues: issues,
  );
}

/// Validation status for visual page-readiness evidence.
class VisualPageReadinessStatus {
  /// Creates a visual page-readiness status.
  const VisualPageReadinessStatus({
    required this.path,
    required this.isRequired,
    required this.exists,
    this.status,
    this.packageName,
    this.platform,
    this.result,
    this.screenshots = const [],
    this.uiStateEvidence = const [],
    this.issues = const [],
  });

  /// Evidence path relative to the repository root.
  final String path;

  /// Whether the current workflow requires this evidence.
  final bool isRequired;

  /// Whether the evidence file exists.
  final bool exists;

  /// Recorded readiness status.
  final String? status;

  /// Recorded package name.
  final String? packageName;

  /// Recorded platform name.
  final String? platform;

  /// Human-readable inspection result.
  final String? result;

  /// Screenshot paths that were reviewed.
  final List<String> screenshots;

  /// UI-state evidence paths that were reviewed.
  final List<String> uiStateEvidence;

  /// Validation issues.
  final List<Map<String, Object?>> issues;

  /// Whether required visual page-readiness evidence is satisfied.
  bool get ready =>
      !isRequired ||
      (exists &&
          status != null &&
          _readyStatuses.contains(status) &&
          issues.isEmpty);

  /// Serializes this status for JSON output.
  Map<String, Object?> toJson() {
    return {
      'path': path,
      'required': isRequired,
      'exists': exists,
      'ready': ready,
      if (status != null) 'status': status,
      if (packageName != null) 'package': packageName,
      if (platform != null) 'platform': platform,
      if (result != null) 'result': result,
      if (screenshots.isNotEmpty) 'screenshots': screenshots,
      if (uiStateEvidence.isNotEmpty) 'uiStateEvidence': uiStateEvidence,
      'issues': issues,
    };
  }
}

String? _string(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}

List<String> _stringList(Object? value) {
  if (value is! List<Object?>) {
    return const [];
  }
  return [
    for (final item in value)
      if (_string(item) != null) _string(item)!,
  ];
}
