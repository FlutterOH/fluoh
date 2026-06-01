/// Result for one project or package target in a workflow command.
///
/// `verify`, `build`, and `run` can operate on a single project, a selected
/// package, or every registered package. This object is the stable JSON unit
/// returned for each target.
class WorkflowTargetResult {
  const WorkflowTargetResult._({
    required this.targetKind,
    required this.targetName,
    required this.exitCode,
    required this.steps,
    this.preset,
    this.phase,
  });

  /// Creates a result for a registered package.
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

  /// Creates a result for the current project.
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

  /// Target kind used in JSON output, such as `project` or `package`.
  final String targetKind;

  /// Project name or package name for this workflow target.
  final String targetName;

  /// Aggregate exit code for all steps in this target.
  final int exitCode;

  /// Ordered command steps executed for this target.
  final List<WorkflowStepResult> steps;

  /// Optional run/build preset that selected the target or emulator.
  final String? preset;

  /// Optional phase name used to identify the current workflow branch.
  final String? phase;

  /// Whether every required step for this target passed.
  bool get passed => exitCode == 0;

  /// First diagnostic next command reported by any step, if available.
  String? get nextCommand {
    for (final step in steps) {
      final command = step.nextCommand;
      if (command != null) {
        return command;
      }
    }
    return null;
  }

  /// Converts this result to the command JSON contract.
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

/// Result for one command step inside a workflow target.
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

  /// Human-readable step name.
  final String name;

  /// Directory where [command] was executed.
  final String path;

  /// Shell-style command string shown to users and JSON consumers.
  final String command;

  /// Step status such as `passed`, `failed`, or `skipped`.
  final String status;

  /// Process exit code when the step ran a process.
  final int? exitCode;

  /// Short explanation for skipped or failed steps.
  final String? reason;

  /// Structured step-specific data.
  final Map<String, Object?> details;

  /// Diagnostics produced by this step.
  final List<WorkflowDiagnostic> diagnostics;

  /// First next command suggested by this step's diagnostics.
  String? get nextCommand {
    for (final diagnostic in diagnostics) {
      if (diagnostic.nextCommand != null) {
        return diagnostic.nextCommand;
      }
    }
    return null;
  }

  /// Converts this step to the command JSON contract.
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

/// Structured diagnostic emitted by workflow commands.
class WorkflowDiagnostic {
  const WorkflowDiagnostic({
    required this.code,
    required this.message,
    this.severity = 'error',
    this.details = const {},
    this.nextCommand,
  });

  /// Stable diagnostic code for automation.
  final String code;

  /// User-facing explanation of the diagnostic.
  final String message;

  /// Severity such as `error`, `warning`, or `info`.
  final String severity;

  /// Additional structured data for this diagnostic.
  final Map<String, Object?> details;

  /// Suggested command that can move the workflow forward.
  final String? nextCommand;

  /// Converts this diagnostic to the command JSON contract.
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
