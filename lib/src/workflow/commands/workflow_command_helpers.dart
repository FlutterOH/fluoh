part of 'workflow_commands.dart';

bool _isDesktopRunPlatform(String platform) {
  return platformWorkflowPolicy(platform).isDesktopRunPlatform;
}

int _lastExitCode(List<WorkflowStepResult> steps) {
  return steps.last.exitCode ?? 1;
}

const _buildRunPlatforms = workflowPlatformNames;

const _drivePlatforms = ['all', 'ohos', 'android', 'ios'];

String _platformArgument(
  ArgResults results,
  UsageError usageException, {
  required List<String> allowed,
  required String label,
}) {
  final arguments = results.rest;
  if (arguments.length != 1) {
    usageException('Expected one $label platform: ${allowed.join(', ')}.');
  }
  final value = arguments.single.trim().toLowerCase();
  if (!allowed.contains(value)) {
    usageException(
      'Unsupported $label platform "$value". Expected one of: ${allowed.join(', ')}.',
    );
  }
  return value;
}

String? _trimmedOption(ArgResults results, String name) {
  final value = results.option(name)?.trim();
  return value == null || value.isEmpty ? null : value;
}

TerminalOutput _outputFor(bool json, TerminalOutput output) {
  return json ? TerminalOutput(stdout: (_) {}, stderr: (_) {}) : output;
}

int _firstFailure(List<WorkflowTargetResult> results) {
  return results
      .map((result) => result.exitCode)
      .firstWhere((exitCode) => exitCode != 0, orElse: () => 0);
}

String _passedMessage(String label, int count) {
  return count == 1 ? '$label passed' : '$label passed for $count runs';
}

Future<_GitStatusSnapshot?> _gitStatusSnapshot(Directory repository) async {
  final inside = await runGit(
    ['rev-parse', '--is-inside-work-tree'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (inside.exitCode != 0 ||
      inside.stdout.toString().trim().toLowerCase() != 'true') {
    return null;
  }
  final status = await runGit(
    ['status', '--porcelain', '--untracked-files=all'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (status.exitCode != 0) {
    return null;
  }
  return _GitStatusSnapshot(_statusLines(status.stdout.toString()));
}

Future<_WorkflowWorkingTreeChanges> _workingTreeChangesAfterWorkflow(
  Directory repository,
  _GitStatusSnapshot? before,
) async {
  if (before == null) {
    return _WorkflowWorkingTreeChanges.unavailable();
  }
  final after = await _gitStatusSnapshot(repository);
  if (after == null) {
    return _WorkflowWorkingTreeChanges.unavailable();
  }
  final beforeSet = before.lines.toSet();
  final newLines = after.lines
      .where((line) => !beforeSet.contains(line))
      .toList(growable: false);
  final generatedFiles = newLines
      .map(_statusPath)
      .where(_isGeneratedWorkflowPath)
      .toList(growable: false);
  return _WorkflowWorkingTreeChanges(
    available: true,
    beforeDirty: before.lines.isNotEmpty,
    afterDirty: after.lines.isNotEmpty,
    statusShort: after.lines,
    newStatusShort: newLines,
    generatedFiles: generatedFiles,
  );
}

List<String> _statusLines(String output) {
  return output
      .split('\n')
      .map((line) => line.trimRight())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

String _statusPath(String statusLine) {
  if (statusLine.length <= 3) {
    return statusLine.trim();
  }
  final path = statusLine.substring(3).trim();
  final renameSeparator = path.indexOf(' -> ');
  return renameSeparator == -1
      ? path
      : path.substring(renameSeparator + ' -> '.length);
}

bool _isGeneratedWorkflowPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.contains('/generated_') ||
      normalized.endsWith('/generated_plugins.cmake') ||
      normalized.endsWith('/GeneratedPluginRegistrant.dart') ||
      normalized.endsWith('/GeneratedPluginRegistrant.h') ||
      normalized.endsWith('/GeneratedPluginRegistrant.m') ||
      normalized.endsWith('/GeneratedPluginRegistrant.mm') ||
      normalized.endsWith('/GeneratedPluginRegistrant.swift') ||
      normalized.endsWith('/Generated.xcconfig') ||
      normalized.endsWith('/flutter_export_environment.sh') ||
      normalized.contains('/Flutter/ephemeral/') ||
      normalized == '.dart_tool' ||
      normalized.startsWith('.dart_tool/') ||
      normalized.contains('/.dart_tool/');
}

class _GitStatusSnapshot {
  const _GitStatusSnapshot(this.lines);

  final List<String> lines;
}

class _WorkflowWorkingTreeChanges {
  const _WorkflowWorkingTreeChanges({
    required this.available,
    required this.beforeDirty,
    required this.afterDirty,
    required this.statusShort,
    required this.newStatusShort,
    required this.generatedFiles,
  });

  factory _WorkflowWorkingTreeChanges.unavailable() {
    return const _WorkflowWorkingTreeChanges(
      available: false,
      beforeDirty: false,
      afterDirty: false,
      statusShort: [],
      newStatusShort: [],
      generatedFiles: [],
    );
  }

  final bool available;
  final bool beforeDirty;
  final bool afterDirty;
  final List<String> statusShort;
  final List<String> newStatusShort;
  final List<String> generatedFiles;

  bool get changedDuringCommand => newStatusShort.isNotEmpty;

  bool get generatedFilesChanged => generatedFiles.isNotEmpty;

  bool get shouldWarn => available && changedDuringCommand;

  Map<String, Object?> toJson() {
    return {
      'dirtyAfterVerify': available ? afterDirty : null,
      'workingTreeChanges': {
        'available': available,
        'beforeDirty': beforeDirty,
        'afterDirty': afterDirty,
        'changedDuringCommand': changedDuringCommand,
        'generatedFilesChanged': generatedFilesChanged,
        'statusShort': statusShort,
        'newStatusShort': newStatusShort,
        'generatedFiles': generatedFiles,
        if (afterDirty) 'nextCommand': 'git status --short',
      },
    };
  }
}

Future<TraceWriteResult> _printWorkflowJson({
  required bool json,
  required OutputWriter stdout,
  required FluohEnvironment environment,
  required String command,
  required List<String> arguments,
  required List<WorkflowTargetResult> results,
  required TraceOptions traceOptions,
  Map<String, Object?> extraFields = const {},
}) async {
  final exitCode = _firstFailure(results);
  final resultFields = {
    'targets': results.map((result) => result.toJson()).toList(),
    ...extraFields,
  };
  final traceResult = await writeCommandTrace(
    options: traceOptions,
    environment: environment,
    command: command,
    arguments: arguments,
    ok: exitCode == 0,
    exitCode: exitCode,
    result: resultFields,
    feedbackCandidates: _feedbackCandidates(results),
  );
  if (!json) {
    return traceResult;
  }
  writeMachineOutput(
    stdout,
    command: command,
    ok: exitCode == 0,
    exitCode: exitCode,
    fields: {
      ...resultFields,
      if (traceResult.reference != null)
        'trace': traceResult.reference!.toJson(),
      if (traceResult.error != null) 'traceError': traceResult.error,
    },
  );
  return traceResult;
}

void _writeTraceStatus(TerminalOutput output, TraceWriteResult result) {
  final reference = result.reference;
  if (reference != null) {
    output.detail('Trace saved to ${reference.manifest.path}');
  } else if (result.error != null) {
    output.warning(result.error!);
  }
}

List<Map<String, Object?>> _feedbackCandidates(
  List<WorkflowTargetResult> results,
) {
  final candidates = <Map<String, Object?>>[];
  var nextId = 1;
  for (final target in results) {
    for (final step in target.steps) {
      for (final diagnostic in step.diagnostics) {
        final reason = _feedbackReason(diagnostic);
        if (reason == null) {
          continue;
        }
        candidates.add({
          'id': 'F${nextId.toString().padLeft(3, '0')}',
          'owner': 'fluoh-cli',
          'category': 'diagnostic-gap',
          'severity': 'warning',
          'reason': reason,
          'summary': _feedbackSummary(reason, diagnostic),
          'target': {'kind': target.targetKind, 'name': target.targetName},
          'step': {
            'name': step.name,
            'command': step.command,
            'path': step.path,
          },
          'diagnosticCode': diagnostic.code,
          'suggestedChange': _feedbackSuggestedChange(reason, diagnostic),
        });
        nextId += 1;
      }
    }
  }
  return candidates;
}

String? _feedbackReason(WorkflowDiagnostic diagnostic) {
  if (diagnostic.nextCommand == null) {
    return 'missing-next-command';
  }
  if (diagnostic.code == 'command.failed') {
    return 'generic-diagnostic';
  }
  return null;
}

String _feedbackSummary(String reason, WorkflowDiagnostic diagnostic) {
  return switch (reason) {
    'missing-next-command' =>
      'Diagnostic ${diagnostic.code} does not provide a next command.',
    'generic-diagnostic' =>
      'Diagnostic used generic command.failed classification.',
    _ => 'Diagnostic may need a more actionable fluoh classification.',
  };
}

String _feedbackSuggestedChange(String reason, WorkflowDiagnostic diagnostic) {
  return switch (reason) {
    'missing-next-command' =>
      'Add a targeted nextCommand for ${diagnostic.code}.',
    'generic-diagnostic' =>
      'Replace command.failed with a stable domain-specific diagnostic code.',
    _ => 'Review whether this diagnostic should be more specific.',
  };
}
