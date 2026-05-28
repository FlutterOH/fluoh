class WorkflowTargetResult {
  const WorkflowTargetResult._({
    required this.targetKind,
    required this.targetName,
    required this.exitCode,
    required this.steps,
    this.preset,
    this.phase,
  });

  const WorkflowTargetResult.package({
    required String packageName,
    required int exitCode,
    required List<WorkflowStepResult> steps,
    String? preset,
    String? phase,
  }) : this._(
         targetKind: 'package',
         targetName: packageName,
         exitCode: exitCode,
         steps: steps,
         preset: preset,
         phase: phase,
       );

  const WorkflowTargetResult.project({
    required String projectName,
    required int exitCode,
    required List<WorkflowStepResult> steps,
    String? preset,
    String? phase,
  }) : this._(
         targetKind: 'project',
         targetName: projectName,
         exitCode: exitCode,
         steps: steps,
         preset: preset,
         phase: phase,
       );

  final String targetKind;
  final String targetName;
  final int exitCode;
  final List<WorkflowStepResult> steps;
  final String? preset;
  final String? phase;

  bool get passed => exitCode == 0;

  String? get nextCommand {
    for (final step in steps) {
      final command = step.nextCommand;
      if (command != null) {
        return command;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return {
      'target': {'kind': targetKind, 'name': targetName},
      if (preset != null) 'preset': preset,
      if (phase != null) 'phase': phase,
      'passed': passed,
      'exitCode': exitCode,
      if (nextCommand != null) 'nextCommand': nextCommand,
      'steps': steps.map((step) => step.toJson()).toList(),
    };
  }
}

class WorkflowStepResult {
  const WorkflowStepResult({
    required this.name,
    required this.path,
    required this.command,
    required this.status,
    this.exitCode,
    this.reason,
    this.details = const {},
    this.diagnostics = const [],
  });

  final String name;
  final String path;
  final String command;
  final String status;
  final int? exitCode;
  final String? reason;
  final Map<String, Object?> details;
  final List<WorkflowDiagnostic> diagnostics;

  String? get nextCommand {
    for (final diagnostic in diagnostics) {
      if (diagnostic.nextCommand != null) {
        return diagnostic.nextCommand;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'path': path,
      'command': command,
      'status': status,
      if (exitCode != null) 'exitCode': exitCode,
      if (reason != null) 'reason': reason,
      if (nextCommand != null) 'nextCommand': nextCommand,
      if (details.isNotEmpty) 'details': details,
      if (diagnostics.isNotEmpty)
        'diagnostics': diagnostics.map((item) => item.toJson()).toList(),
    };
  }
}

class WorkflowDiagnostic {
  const WorkflowDiagnostic({
    required this.code,
    required this.message,
    this.severity = 'error',
    this.details = const {},
    this.nextCommand,
  });

  final String code;
  final String message;
  final String severity;
  final Map<String, Object?> details;
  final String? nextCommand;

  Map<String, Object?> toJson() {
    return {
      'code': code,
      'severity': severity,
      'message': message,
      if (nextCommand != null) 'nextCommand': nextCommand,
      if (details.isNotEmpty) 'details': details,
    };
  }
}
