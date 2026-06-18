part of 'workflow_commands.dart';

bool _isDesktopRunPlatform(String platform) {
  return platformWorkflowPolicy(platform).isDesktopRunPlatform;
}

int _lastExitCode(List<WorkflowStepResult> steps) {
  return steps.last.exitCode ?? 1;
}

const _allWorkflowPlatform = 'all';

final _buildRunPlatforms = [_allWorkflowPlatform, ...workflowPlatformNames];

final _attachPlatforms = workflowPlatformNames;

final _drivePlatforms = [_allWorkflowPlatform, ...workflowDrivePlatformNames];

Future<List<String>> _workflowPlatformsFromArgument(
  String platform, {
  required FluohEnvironment environment,
  required String? packageName,
  required List<String> candidates,
  required String usage,
}) async {
  if (platform != _allWorkflowPlatform) {
    return [platform];
  }
  final root = await _workflowPlatformRoot(
    environment: environment,
    packageName: packageName,
    usage: usage,
  );
  final selected = <String>[];
  for (final candidate in candidates) {
    if (candidate == _allWorkflowPlatform) {
      continue;
    }
    if (await Directory('${root.directory.path}/$candidate').exists()) {
      selected.add(candidate);
    }
  }
  if (selected.isEmpty) {
    throw UsageException(
      'No applicable workflow platforms found for all in ${root.label}. '
      'Add platform directories or run a specific platform.',
      usage,
    );
  }
  return selected;
}

Future<_WorkflowPlatformRoot> _workflowPlatformRoot({
  required FluohEnvironment environment,
  required String? packageName,
  required String usage,
}) async {
  final manifest = await _readOptionalPackageManifest(environment);
  if (manifest == null) {
    if (packageName != null) {
      throw UsageException(
        'Current directory is not a package repository.',
        usage,
      );
    }
    return _WorkflowPlatformRoot(
      directory: environment.workingDirectory,
      label: 'current project',
    );
  }
  final package = manifest.packageForName(packageName);
  return _WorkflowPlatformRoot(
    directory: Directory(
      '${packageDirectory(environment.workingDirectory, package.path).path}/example',
    ),
    label: '${package.name} example',
  );
}

class _WorkflowPlatformRoot {
  const _WorkflowPlatformRoot({required this.directory, required this.label});

  final Directory directory;
  final String label;
}

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

Map<String, Object?> _buildOnlyEvidence({
  required List<String> platforms,
  required List<WorkflowTargetResult> results,
  required String? packageName,
  required bool requestedAllPlatforms,
  required bool autoEmulator,
}) {
  final passed = _firstFailure(results) == 0;
  final blockingDiagnostics = [if (!passed) 'repairFailedTargets'];
  final notCollectedEvidenceKinds = ['launchSmoke', 'functionalInteraction'];
  final workflowContinuations = ['coverageReview', 'reportCheck'];
  return {
    'schema': 1,
    'kind': 'fluoh.workflowEvidence',
    'classification': 'buildOnly',
    'passed': passed,
    'scope': _workflowEvidenceScope(
      platforms: platforms,
      packageName: packageName,
      requestedAllPlatforms: requestedAllPlatforms,
    ),
    'observedEvidence': {
      'build': {
        'status': passed ? 'passed' : 'failed',
        'targetCount': results.length,
      },
      'launch': {'status': 'notCollectedByThisCommand'},
      'interaction': _interactionEvidenceSummary(results),
    },
    'collectedEvidenceKinds': const ['buildCommandResult'],
    'notCollectedEvidenceKinds': notCollectedEvidenceKinds,
    'workflowContinuations': workflowContinuations,
    if (blockingDiagnostics.isNotEmpty)
      'blockingDiagnostics': blockingDiagnostics,
    'toolCommands': [
      if (passed)
        {
          'purpose': 'collect launch smoke evidence',
          'command': _runCommandFromEvidenceScope(
            platforms: platforms,
            packageName: packageName,
            requestedAllPlatforms: requestedAllPlatforms,
            autoEmulator: autoEmulator,
          ),
        },
    ],
  };
}

Map<String, Object?> _runSmokeEvidence({
  required List<String> platforms,
  required List<WorkflowTargetResult> results,
  required String? packageName,
  required bool requestedAllPlatforms,
  required bool autoEmulator,
}) {
  final passed = _firstFailure(results) == 0;
  final interactionEvidence = _interactionEvidenceSummary(results);
  final hasPassedIntegrationEvidence =
      interactionEvidence['status'] == 'integrationTestEvidencePresent';
  final hasIntegrationCommandResult =
      interactionEvidence['status'] != 'notCollectedByThisCommand';
  final blockingDiagnostics = [if (!passed) 'repairFailedTargets'];
  final mobilePlatforms = platforms
      .where(_isDrivePlatform)
      .toList(growable: false);
  final postLaunchScreenshotEvidence = _postLaunchScreenshotEvidenceSummary(
    mobilePlatforms: mobilePlatforms,
    results: results,
  );
  final postLaunchScreenshotStatus =
      postLaunchScreenshotEvidence['status'] as String;
  final hasCollectedPostLaunchScreenshot =
      (postLaunchScreenshotEvidence['capturedTargetCount'] as int? ?? 0) > 0;
  final hasCompletePostLaunchScreenshot =
      postLaunchScreenshotStatus == 'postLaunchScreenshotEvidencePresent';
  final notCollectedEvidenceKinds = [
    if (mobilePlatforms.isNotEmpty && !hasCompletePostLaunchScreenshot)
      'postLaunchScreenshot',
    if (mobilePlatforms.isNotEmpty) 'visualPageReadiness',
    if (!hasPassedIntegrationEvidence) 'functionalInteraction',
  ];
  final workflowContinuations = [
    if (mobilePlatforms.isNotEmpty) 'postLaunchScreenshotReview',
    if (mobilePlatforms.isNotEmpty) 'demoRepairBeforeFullAutomation',
    'coverageReview',
    'reportCheck',
  ];
  return {
    'schema': 1,
    'kind': 'fluoh.workflowEvidence',
    'classification': 'launchSmoke',
    'passed': passed,
    'scope': _workflowEvidenceScope(
      platforms: platforms,
      packageName: packageName,
      requestedAllPlatforms: requestedAllPlatforms,
    ),
    'observedEvidence': {
      'launch': {
        'status': passed ? 'passed' : 'failed',
        'targetCount': results.length,
      },
      if (mobilePlatforms.isNotEmpty)
        'postLaunchScreenshot': postLaunchScreenshotEvidence,
      'interaction': interactionEvidence,
    },
    'collectedEvidenceKinds': [
      'launchCommandResult',
      if (hasCollectedPostLaunchScreenshot) 'postLaunchScreenshot',
      if (hasIntegrationCommandResult) 'integrationTestCommandResult',
    ],
    'notCollectedEvidenceKinds': notCollectedEvidenceKinds,
    'workflowContinuations': workflowContinuations,
    if (blockingDiagnostics.isNotEmpty)
      'blockingDiagnostics': blockingDiagnostics,
    'toolCommands': [
      if (passed && mobilePlatforms.isNotEmpty)
        {
          'purpose':
              'capture post-launch screenshot, verify the demo page, and plan functional interaction automation',
          'command': _driveCommandFromEvidenceScope(
            platforms: mobilePlatforms,
            packageName: packageName,
            requestedAllPlatforms: requestedAllPlatforms,
            autoEmulator: autoEmulator,
            dryRun: true,
          ),
        },
    ],
  };
}

Map<String, Object?> _postLaunchScreenshotEvidenceSummary({
  required List<String> mobilePlatforms,
  required List<WorkflowTargetResult> results,
}) {
  if (mobilePlatforms.isEmpty) {
    return const {'status': 'notApplicable'};
  }
  final mobilePlatformSet = mobilePlatforms.toSet();
  var successfulMobileRunTargetCount = 0;
  var capturedTargetCount = 0;
  var failedTargetCount = 0;
  var skippedTargetCount = 0;
  var missingTargetCount = 0;
  final paths = <String>[];
  final failures = <Map<String, Object?>>[];
  for (final result in results) {
    for (final step in result.steps) {
      if (!_isRunStep(step)) {
        continue;
      }
      final platform = _stepPlatform(step);
      if (platform == null || !mobilePlatformSet.contains(platform)) {
        continue;
      }
      if (step.status != 'passed') {
        continue;
      }
      successfulMobileRunTargetCount += 1;
      final evidence = step.details['postLaunchScreenshot'];
      if (evidence is! Map) {
        missingTargetCount += 1;
        continue;
      }
      final status = evidence['status'];
      if (status == 'passed') {
        capturedTargetCount += 1;
        final path = evidence['path'];
        if (path is String && path.isNotEmpty) {
          paths.add(path);
        }
      } else if (status == 'skipped') {
        skippedTargetCount += 1;
        failures.add(_postLaunchScreenshotIssue(platform, evidence));
      } else {
        failedTargetCount += 1;
        failures.add(_postLaunchScreenshotIssue(platform, evidence));
      }
    }
  }
  final status = successfulMobileRunTargetCount == 0
      ? 'notCollectedByThisCommand'
      : capturedTargetCount == successfulMobileRunTargetCount
      ? 'postLaunchScreenshotEvidencePresent'
      : capturedTargetCount > 0
      ? 'partialPostLaunchScreenshotEvidence'
      : 'notCollectedByThisCommand';
  return {
    'status': status,
    'targetCount': successfulMobileRunTargetCount,
    'capturedTargetCount': capturedTargetCount,
    'failedTargetCount': failedTargetCount,
    'skippedTargetCount': skippedTargetCount,
    'missingTargetCount': missingTargetCount,
    if (paths.isNotEmpty) 'paths': paths,
    if (failures.isNotEmpty) 'issues': failures,
  };
}

bool _isRunStep(WorkflowStepResult step) {
  return step.name.startsWith('example-run-') ||
      step.name.startsWith('project-run-');
}

String? _stepPlatform(WorkflowStepResult step) {
  final platform = step.details['platform'];
  if (platform is String && platform.trim().isNotEmpty) {
    return platform.trim().toLowerCase();
  }
  final match = RegExp(r'-(ohos|android|ios)$').firstMatch(step.name);
  return match?.group(1);
}

Map<String, Object?> _postLaunchScreenshotIssue(
  String platform,
  Map<Object?, Object?> evidence,
) {
  return {
    'platform': platform,
    if (evidence['status'] != null) 'status': evidence['status'],
    if (evidence['reason'] != null) 'reason': evidence['reason'],
    if (evidence['path'] != null) 'path': evidence['path'],
  };
}

Map<String, Object?> _workflowEvidenceScope({
  required List<String> platforms,
  required String? packageName,
  required bool requestedAllPlatforms,
}) {
  return {
    'platforms': platforms,
    'package': ?packageName,
    if (requestedAllPlatforms) 'requestedPlatform': _allWorkflowPlatform,
  };
}

Map<String, Object?> _interactionEvidenceSummary(
  List<WorkflowTargetResult> results,
) {
  final passedIntegrationCommands = <String>[];
  final failedIntegrationCommands = <String>[];
  final skippedIntegrationCommands = <String>[];
  var passedIntegrationTargetCount = 0;
  var failedIntegrationTargetCount = 0;
  var skippedIntegrationTargetCount = 0;
  var missingIntegrationTargetCount = 0;
  for (final result in results) {
    final integrationSteps = result.steps
        .where((step) => step.name.contains('-integration-'))
        .toList(growable: false);
    if (integrationSteps.isEmpty) {
      missingIntegrationTargetCount += 1;
      continue;
    }
    var targetPassed = false;
    var targetFailed = false;
    for (final step in integrationSteps) {
      if (step.status == 'passed') {
        targetPassed = true;
        passedIntegrationCommands.add(step.command);
      } else if (step.status == 'failed') {
        targetFailed = true;
        failedIntegrationCommands.add(step.command);
      } else {
        skippedIntegrationCommands.add(step.command);
      }
    }
    if (targetFailed) {
      failedIntegrationTargetCount += 1;
    } else if (targetPassed) {
      passedIntegrationTargetCount += 1;
    } else {
      skippedIntegrationTargetCount += 1;
    }
  }
  final status = failedIntegrationCommands.isNotEmpty
      ? 'integrationTestEvidenceFailed'
      : passedIntegrationCommands.isNotEmpty &&
            passedIntegrationTargetCount == results.length
      ? 'integrationTestEvidencePresent'
      : passedIntegrationCommands.isNotEmpty
      ? 'partialIntegrationTestEvidence'
      : 'notCollectedByThisCommand';
  return {
    'status': status,
    'targetCount': results.length,
    'passedIntegrationTargetCount': passedIntegrationTargetCount,
    'failedIntegrationTargetCount': failedIntegrationTargetCount,
    'skippedIntegrationTargetCount': skippedIntegrationTargetCount,
    'missingIntegrationTargetCount': missingIntegrationTargetCount,
    'observableSourceKinds': const [
      'flutter integration_test command result',
      'fluoh drive scenario JSON',
      'manual-assisted tool-readable logs, session state, stable text, semantics, test keys, command JSON, hilog, or app log markers',
    ],
    if (passedIntegrationCommands.isNotEmpty)
      'passedIntegrationCommands': passedIntegrationCommands,
    if (failedIntegrationCommands.isNotEmpty)
      'failedIntegrationCommands': failedIntegrationCommands,
    if (skippedIntegrationCommands.isNotEmpty)
      'skippedIntegrationCommands': skippedIntegrationCommands,
    'warning':
        'Launch smoke evidence is not functional interaction evidence by itself.',
  };
}

bool _isDrivePlatform(String platform) {
  return platform == 'ohos' || platform == 'android' || platform == 'ios';
}

String _runCommandFromEvidenceScope({
  required List<String> platforms,
  required String? packageName,
  required bool requestedAllPlatforms,
  required bool autoEmulator,
}) {
  final platform = requestedAllPlatforms
      ? _allWorkflowPlatform
      : platforms.single;
  final hasMobilePlatform = platforms.any(_isDrivePlatform);
  final parts = [
    'fluoh',
    'run',
    platform,
    if (packageName != null) ...['--package', packageName],
    if (autoEmulator || hasMobilePlatform) '--auto-emulator',
    '--json',
  ];
  return parts.map(_workflowShellQuote).join(' ');
}

String _driveCommandFromEvidenceScope({
  required List<String> platforms,
  required String? packageName,
  required bool requestedAllPlatforms,
  required bool autoEmulator,
  required bool dryRun,
}) {
  final platform = requestedAllPlatforms
      ? _allWorkflowPlatform
      : platforms.single;
  final parts = [
    'fluoh',
    'drive',
    platform,
    if (packageName != null) ...['--package', packageName],
    if (autoEmulator) '--auto-emulator',
    if (dryRun) '--dry-run',
    '--json',
  ];
  return parts.map(_workflowShellQuote).join(' ');
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
  final nextAction = _workflowNextAction(
    command: command,
    arguments: arguments,
    results: results,
  );
  final resultFields = {
    'targets': results.map((result) => result.toJson()).toList(),
    'nextAction': ?nextAction,
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

Map<String, Object?>? _workflowNextAction({
  required String command,
  required List<String> arguments,
  required List<WorkflowTargetResult> results,
}) {
  WorkflowTargetResult? failedTarget;
  for (final result in results) {
    if (!result.passed) {
      failedTarget = result;
      break;
    }
  }
  if (failedTarget == null) {
    return null;
  }

  final failedStep = _firstIncompleteStep(failedTarget);
  final diagnostic = failedStep == null
      ? null
      : _firstDiagnosticWithMessage(failedStep);
  final nextCommand = failedTarget.nextCommand;
  final reason =
      diagnostic?.message ??
      failedStep?.reason ??
      'Workflow command failed for ${failedTarget.targetKind} ${failedTarget.targetName}.';
  final rerunCommand = _workflowRerunCommand(command, arguments);
  final target = {
    'kind': failedTarget.targetKind,
    'name': failedTarget.targetName,
  };
  final step = failedStep == null
      ? null
      : {
          'name': failedStep.name,
          'command': failedStep.command,
          'status': failedStep.status,
          if (failedStep.exitCode != null) 'exitCode': failedStep.exitCode,
        };
  if (nextCommand != null) {
    return {
      'type': 'commandRequired',
      'state': 'active',
      'reason': reason,
      'command': nextCommand,
      'rerunCommand': rerunCommand,
      'target': target,
      'step': ?step,
      if (diagnostic != null) 'diagnosticCode': diagnostic.code,
    };
  }
  return {
    'type': 'blocked',
    'state': 'blocked',
    'reason': reason,
    'rerunCommand': rerunCommand,
    'target': target,
    'step': ?step,
    if (diagnostic != null) 'diagnosticCode': diagnostic.code,
  };
}

WorkflowStepResult? _firstIncompleteStep(WorkflowTargetResult target) {
  for (final step in target.steps) {
    if (step.status == 'failed' ||
        (step.exitCode != null && step.exitCode != 0)) {
      return step;
    }
  }
  for (final step in target.steps) {
    if (step.status != 'passed') {
      return step;
    }
  }
  return target.steps.isEmpty ? null : target.steps.last;
}

WorkflowDiagnostic? _firstDiagnosticWithMessage(WorkflowStepResult step) {
  for (final diagnostic in step.diagnostics) {
    if (diagnostic.message.trim().isNotEmpty) {
      return diagnostic;
    }
  }
  return step.diagnostics.isEmpty ? null : step.diagnostics.first;
}

String _workflowRerunCommand(String command, List<String> arguments) {
  final parts = ['fluoh', ...command.split(' '), ...arguments];
  return parts.map(_workflowShellQuote).join(' ');
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
