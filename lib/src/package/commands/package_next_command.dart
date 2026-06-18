import 'dart:convert';
import 'dart:io';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/skill_command.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../task/task_workspace.dart';
import '../../workflow/platform_workflow_policy.dart';
import '../git/package_git.dart';
import '../manifest/package_manifest.dart';
import '../package_discovery.dart';
import '../package_scope.dart';
import '../package_spec.dart';
import '../visual_page_readiness.dart';

/// Reports the next implementation action for a package repository.
class PackageNextCommand extends FluohCommand<int> {
  /// Creates the package next command.
  PackageNextCommand({
    required this.environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _output = output ?? TerminalOutput(stdout: stdout) {
    argParser
      ..addOption(
        'package',
        valueHelp: 'name',
        help: 'Package to inspect. Defaults to the current package branch.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the next implementation action as JSON.',
      );
  }

  /// Runtime environment.
  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final TerminalOutput _output;

  @override
  String get name => 'next';

  @override
  String get description => 'Report the next package implementation action.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);

    final repository = environment.workingDirectory;
    final manifest = await readPackageManifest(repository);
    final package = manifest.packageForName(argResults!.option('package'));
    final task = await TaskWorkspace(environment).resolveOrCreate(
      type: 'packageSupport',
      scopeName: package.name,
      packageName: package.name,
    );
    final branch = await currentBranch(repository);
    final latestTrace = await _latestTrace(task);
    final traceDir = '${task.relativePath(repository)}/traces/support';
    final trace = await _readTrace(latestTrace);
    final reports = await _reportFiles(task);
    final reportCheck = reports.isEmpty
        ? const _ReportCheckStatus.notRequired()
        : await _inspectReportCheck(reports.first, environment);
    final scopeStatus = await inspectPackageScope(
      repository: repository,
      packageName: package.name,
    );
    final specStatus = await inspectPackageSpec(
      repository: repository,
      manifest: manifest,
    );
    final qualityProfile = await _QualityProfile.inspect(
      repository: repository,
      package: package,
    );
    final steps = _supportSteps(
      package.name,
      traceDir,
      existingPlatforms: qualityProfile.example.existingPlatforms,
    );
    final evidenceSummary = _EvidenceSummary.fromTrace(
      trace: trace,
      steps: steps,
      reports: reports,
    );
    final visualPageReadiness = await inspectVisualPageReadiness(
      repository: repository,
      packageName: package.name,
      isRequired: evidenceSummary.completedPhases.contains('ohos-run'),
    );
    final failureStreak =
        trace?.latestFailureStreak ?? const _FailureStreak.none();
    final action = await _nextSupportAction(
      repository: repository,
      manifest: manifest,
      package: package,
      branch: branch,
      traceDir: traceDir,
      trace: trace,
      reports: reports,
      reportCheck: reportCheck,
      steps: steps,
      scopeStatus: scopeStatus,
      specStatus: specStatus,
      visualPageReadiness: visualPageReadiness,
      failureStreak: failureStreak,
    );
    final result = {
      'state': action.state,
      'stage': 'support',
      'package': {
        'name': package.name,
        'path': package.path,
        'upstreamVersion': package.upstreamVersion,
        'releaseStatus': package.status,
      },
      'branch': branch,
      'expectedBranch': manifest.branch,
      'branchMatches': branch == manifest.branch,
      'evidence': {
        'task': task.toJson(repository),
        'traceDir': traceDir,
        if (latestTrace != null) 'latestTrace': latestTrace.path,
        'reports': [for (final file in reports) file.path],
        if (reports.isNotEmpty) 'latestReport': reports.first.path,
      },
      'spec': specStatus.toJson(),
      'qualityProfile': qualityProfile.toJson(),
      'supportScope': scopeStatus.toJson(),
      'visualPageReadiness': visualPageReadiness.toJson(),
      'evidenceSummary': evidenceSummary.toJson(),
      'reportCheck': reportCheck.toJson(),
      'failureStreak': failureStreak.toJson(),
      'remainingRisks': _remainingRisks(
        evidenceSummary: evidenceSummary,
        reportCheck: reportCheck,
        failureStreak: failureStreak,
        qualityProfile: qualityProfile,
        scopeStatus: scopeStatus,
        specStatus: specStatus,
        visualPageReadiness: visualPageReadiness,
        packageName: package.name,
      ),
      'nextAction': action.toJson(),
    };

    if (argResults!.flag('json')) {
      writeMachineOutput(
        _stdout,
        command: 'package next',
        ok: true,
        exitCode: 0,
        fields: result,
      );
    } else {
      _output.info('Package: ${package.name}');
      _output.info('State: ${action.state}');
      _output.info('Next action: ${action.type}');
      _output.info(action.reason);
      if (action.command != null) {
        _output.next(action.command!);
      } else if (action.rerunCommand != null) {
        _output.next(action.rerunCommand!);
      }
    }
    return 0;
  }
}

Future<_SupportNextAction> _nextSupportAction({
  required Directory repository,
  required PackageManifest manifest,
  required PackageManifestPackage package,
  required String branch,
  required String traceDir,
  required _SupportTrace? trace,
  required List<File> reports,
  required _ReportCheckStatus reportCheck,
  required List<_SupportStep> steps,
  required PackageScopeStatus scopeStatus,
  required PackageSpecStatus specStatus,
  required VisualPageReadinessStatus visualPageReadiness,
  required _FailureStreak failureStreak,
}) async {
  final statusCommand = _statusCommand(package.name);
  if (branch != manifest.branch) {
    return _SupportNextAction.commandRequired(
      phase: 'branch',
      reason: 'Current branch $branch does not match ${manifest.branch}.',
      command: 'git switch ${manifest.branch}',
      rerunCommand: statusCommand,
    );
  }

  final structureAction = await _platformStructureAction(
    repository: repository,
    package: package,
    statusCommand: statusCommand,
  );
  if (structureAction != null) {
    return structureAction;
  }

  final specAction = _specReviewAction(
    packageName: package.name,
    statusCommand: statusCommand,
    specStatus: specStatus,
  );
  if (specAction != null) {
    return specAction;
  }

  final failed = trace?.latestFailedInvocation;
  if (failed != null) {
    if (failureStreak.shouldBlock) {
      return _SupportNextAction.blocked(
        phase: 'repair',
        reason:
            'The same traced command failed ${failureStreak.count} times in a row. Stop automatic repair and ask for a maintainer decision.',
        statusCommand: statusCommand,
        details: {
          'failedCommand': failed.commandLine,
          'failureStreak': failureStreak.toJson(),
          if (failed.exitCode != null) 'exitCode': failed.exitCode,
          if (failed.diagnostics.isNotEmpty) 'diagnostics': failed.diagnostics,
          if (failed.stdoutTail != null) 'stdoutTail': failed.stdoutTail,
          if (failed.stderrTail != null) 'stderrTail': failed.stderrTail,
          if (failed.nextCommand != null) 'nextCommand': failed.nextCommand,
        },
      );
    }
    return _SupportNextAction.editRequired(
      phase: 'repair',
      reason:
          'Last traced command failed; inspect diagnostics and repair the smallest blocking issue.',
      rerunCommand: failed.commandLine,
      statusCommand: statusCommand,
      details: {
        'failedCommand': failed.commandLine,
        if (failed.exitCode != null) 'exitCode': failed.exitCode,
        if (failed.diagnostics.isNotEmpty) 'diagnostics': failed.diagnostics,
        if (failed.stdoutTail != null) 'stdoutTail': failed.stdoutTail,
        if (failed.stderrTail != null) 'stderrTail': failed.stderrTail,
        if (failed.nextCommand != null) 'nextCommand': failed.nextCommand,
      },
    );
  }

  final scopeAction = _scopePlanningAction(
    packageName: package.name,
    statusCommand: statusCommand,
    scopeStatus: scopeStatus,
  );
  if (scopeAction != null) {
    return scopeAction;
  }

  for (final step in steps) {
    if (trace?.passed(step.matches) != true) {
      return _SupportNextAction.commandRequired(
        phase: step.phase,
        reason: step.reason,
        command: step.command,
        rerunCommand: statusCommand,
      );
    }
    if (step.phase == 'ohos-run' && !visualPageReadiness.ready) {
      return _visualPageReadinessAction(
        package: package,
        statusCommand: statusCommand,
        visualPageReadiness: visualPageReadiness,
      );
    }
  }

  if (!scopeStatus.functionalEvidenceReady) {
    return _SupportNextAction.editRequired(
      phase: 'functional-evidence',
      reason:
          'Record functional or regression evidence for supported, degraded, or preserved P0 platform rows before creating the support report.',
      rerunCommand: statusCommand,
      requiredEdits: [
        {
          'target': 'scope',
          'action': 'recordFunctionalEvidence',
          'path': scopeStatus.path,
        },
      ],
      details: {
        'supportScope': scopeStatus.toJson(),
        'issues': [
          for (final issue in scopeStatus.functionalEvidenceIssues)
            issue.toJson(),
        ],
      },
    );
  }

  if (!visualPageReadiness.ready) {
    return _visualPageReadinessAction(
      package: package,
      statusCommand: statusCommand,
      visualPageReadiness: visualPageReadiness,
    );
  }

  if (reports.isNotEmpty && !reportCheck.scriptAvailable) {
    return _SupportNextAction.blocked(
      phase: 'report-check',
      reason:
          'The bundled report checker script is unavailable, so the support report cannot be validated automatically.',
      statusCommand: statusCommand,
      details: {'reportCheck': reportCheck.toJson()},
    );
  }

  if (reports.isNotEmpty && !reportCheck.passed) {
    return _SupportNextAction.editRequired(
      phase: 'report-check',
      reason:
          'Fix the support report until the bundled check_report.py gate passes.',
      rerunCommand: statusCommand,
      statusCommand: statusCommand,
      requiredEdits: [
        {
          'target': 'supportReport',
          'action': 'fixReportCheckFailures',
          'path': reportCheck.reportPath ?? reports.first.path,
        },
      ],
      details: {'reportCheck': reportCheck.toJson()},
    );
  }

  if (reports.isNotEmpty) {
    final reportPath = reports.first.path;
    return _SupportNextAction.ready(
      phase: 'report-check',
      reason:
          'Required support evidence exists and the support report passes check_report.py. Use package status or package check for release readiness.',
      statusCommand: 'fluoh package status --package ${package.name} --json',
      nextCommands: [
        'fluoh package status --package ${package.name} --json',
        'fluoh package handoff --package ${package.name} --json',
        'fluoh package check --package ${package.name} --report ${_shellQuote(reportPath)} --json',
      ],
    );
  }

  return _SupportNextAction.commandRequired(
    phase: 'report',
    reason: 'Create a support report from accumulated trace evidence.',
    command:
        'fluoh report create --scope ${package.name} --package ${package.name} --trace-dir $traceDir --recommendation ready --json',
    rerunCommand: statusCommand,
  );
}

_SupportNextAction? _specReviewAction({
  required String packageName,
  required String statusCommand,
  required PackageSpecStatus specStatus,
}) {
  if (!specStatus.reviewRequired) {
    return null;
  }
  return _SupportNextAction.editRequired(
    phase: 'spec-review',
    reason:
        'Update the branch-local package spec before implementation work continues.',
    rerunCommand: statusCommand,
    statusCommand: statusCommand,
    requiredEdits: [
      {
        'target': 'packageSpec',
        'action': specStatus.exists ? 'reviewAndUpdate' : 'create',
        'path': specStatus.path,
      },
    ],
    details: {
      'spec': specStatus.toJson(),
      'issues': [for (final issue in specStatus.issues) issue.toJson()],
      'nextAfterEdit': 'fluoh package next --package $packageName --json',
    },
  );
}

_SupportNextAction _visualPageReadinessAction({
  required PackageManifestPackage package,
  required String statusCommand,
  required VisualPageReadinessStatus visualPageReadiness,
}) {
  return _SupportNextAction.editRequired(
    phase: 'visual-page-readiness',
    reason:
        'Inspect the captured mobile screenshot or equivalent UI-state evidence and record whether the demo page is functionally ready before continuing automation.',
    rerunCommand: statusCommand,
    requiredEdits: [
      {
        'target': 'visualPageReadiness',
        'action': 'inspectScreenshotAndRecord',
        'path': visualPageReadiness.path,
      },
    ],
    details: {
      'visualPageReadiness': visualPageReadiness.toJson(),
      'template': visualPageReadinessTemplate(package.name),
    },
  );
}

_SupportNextAction? _scopePlanningAction({
  required String packageName,
  required String statusCommand,
  required PackageScopeStatus scopeStatus,
}) {
  if (!scopeStatus.exists) {
    return _SupportNextAction.commandRequired(
      phase: 'scope',
      reason:
          'Initialize the package support scope before implementation work.',
      command: 'fluoh package scope init --package $packageName --json',
      rerunCommand: statusCommand,
    );
  }
  if (scopeStatus.planningReady) {
    return null;
  }
  final phase = scopeStatus.planningIssues.isEmpty
      ? 'planning'
      : scopeStatus.planningIssues.first.phase;
  return _SupportNextAction.editRequired(
    phase: phase,
    reason:
        'Complete P0 scope research, implementation plan, and test plan before implementation work.',
    rerunCommand: 'fluoh package scope check --package $packageName --json',
    statusCommand: statusCommand,
    requiredEdits: [
      {'target': 'scope', 'action': 'edit', 'path': scopeStatus.path},
    ],
    details: {
      'supportScope': scopeStatus.toJson(),
      'issues': [
        for (final issue in scopeStatus.planningIssues) issue.toJson(),
      ],
    },
  );
}

Future<_SupportNextAction?> _platformStructureAction({
  required Directory repository,
  required PackageManifestPackage package,
  required String statusCommand,
}) async {
  final packageRoot = _packageRoot(repository, package.path);
  final example = Directory('${packageRoot.path}/example');
  final examplePubspec = File('${example.path}/pubspec.yaml');
  if (await examplePubspec.exists()) {
    final ohos = Directory('${example.path}/ohos');
    if (!await ohos.exists()) {
      return _SupportNextAction.editRequired(
        phase: 'structure',
        reason: 'Example is missing the OHOS platform directory.',
        rerunCommand: statusCommand,
        requiredEdits: const [
          {'target': 'examplePlatform', 'action': 'create', 'platform': 'ohos'},
        ],
      );
    }
  }

  final discovery = await discoverPackageSupportCandidates(
    repository: repository,
    missingPlatform: 'ohos',
    includeExistingPlatform: true,
  );
  final recommendation = _federatedOhosImplementationRecommendation(
    discovery: discovery,
    package: package,
  );
  if (recommendation == null) {
    return null;
  }
  return _SupportNextAction.editRequired(
    phase: 'structure',
    reason:
        'Federated app-facing package is missing ${recommendation.platform}.default_package: ${recommendation.implementationPackageName}.',
    rerunCommand: statusCommand,
    requiredEdits: [
      {
        'target': 'implementationPackage',
        'action': 'create',
        'package': recommendation.implementationPackageName,
        'path': recommendation.implementationPackagePath,
      },
      {
        'target': 'appFacingPubspec',
        'action': 'add_dependency',
        'package': recommendation.implementationPackageName,
        'path': recommendation.implementationDependencyPath,
      },
      {
        'target': 'appFacingPubspec',
        'action': 'add_default_package',
        'platform': recommendation.platform,
        'package': recommendation.implementationPackageName,
      },
    ],
    details: recommendation.toJson(),
  );
}

List<_SupportStep> _supportSteps(
  String packageName,
  String traceDir, {
  required List<String> existingPlatforms,
}) {
  return [
    _SupportStep(
      phase: 'verify',
      reason: 'Run package verification before platform evidence collection.',
      command:
          'fluoh verify --package $packageName --json --trace-dir $traceDir',
      matches: (command) =>
          _containsCommand(command, 'fluoh verify --package $packageName'),
    ),
    _SupportStep(
      phase: 'ohos-build',
      reason: 'Build the OHOS example with automatic debug signing.',
      command:
          'fluoh build ohos --package $packageName --auto-sign --json --trace-dir $traceDir',
      matches: (command) =>
          _containsCommand(command, 'fluoh build ohos --package $packageName'),
    ),
    _SupportStep(
      phase: 'ohos-run',
      reason: 'Run the OHOS example and collect launch/session evidence.',
      command:
          'fluoh run ohos --package $packageName --auto-emulator --json --trace-dir $traceDir',
      matches: (command) =>
          _containsCommand(command, 'fluoh run ohos --package $packageName'),
    ),
    _SupportStep(
      phase: 'automation-dry-run',
      reason: 'Generate automation coverage inventory for the package.',
      command:
          'fluoh drive ohos --package $packageName --dry-run --json --trace-dir $traceDir',
      matches: (command) =>
          _containsCommand(
            command,
            'fluoh drive ohos --package $packageName',
          ) &&
          command.contains('--dry-run'),
    ),
    _SupportStep(
      phase: 'automation-run',
      reason:
          'Run OHOS interaction automation or collect the explicit blocker.',
      command:
          'fluoh drive ohos --package $packageName --json --trace-dir $traceDir',
      matches: (command) =>
          _containsCommand(
            command,
            'fluoh drive ohos --package $packageName',
          ) &&
          !command.contains('--dry-run') &&
          !command.contains('--profile exploratory-smoke') &&
          !command.contains('--profile=exploratory-smoke'),
    ),
    for (final platform in existingPlatforms)
      ..._existingPlatformSteps(platform, packageName, traceDir),
  ];
}

List<_SupportStep> _existingPlatformSteps(
  String platform,
  String packageName,
  String traceDir,
) {
  final policy = platformWorkflowPolicy(platform);
  final regressionCommand = policy.regressionCommand(
    packageName: packageName,
    traceDir: traceDir,
  );
  return [
    _SupportStep(
      phase: 'existing-$platform-regression',
      reason:
          'Run the existing ${policy.label} example after FlutterOH SDK selection to catch SDK, dependency, and example regressions.',
      command: regressionCommand,
      matches: (command) => _containsCommand(
        command,
        _phaseCommandNeedle(regressionCommand, packageName),
      ),
    ),
    if (_shouldDriveExistingPlatform(platform)) ...[
      _SupportStep(
        phase: 'existing-$platform-automation-dry-run',
        reason:
            'Generate automation coverage inventory for the existing ${policy.label} example.',
        command:
            'fluoh drive $platform --package $packageName --dry-run --json --trace-dir $traceDir',
        matches: (command) =>
            _containsCommand(
              command,
              'fluoh drive $platform --package $packageName',
            ) &&
            command.contains('--dry-run'),
      ),
      _SupportStep(
        phase: 'existing-$platform-automation-run',
        reason:
            'Run existing ${policy.label} interaction automation or collect the explicit blocker.',
        command:
            'fluoh drive $platform --package $packageName --json --trace-dir $traceDir',
        matches: (command) =>
            _containsCommand(
              command,
              'fluoh drive $platform --package $packageName',
            ) &&
            !command.contains('--dry-run') &&
            !command.contains('--profile exploratory-smoke') &&
            !command.contains('--profile=exploratory-smoke'),
      ),
    ],
  ];
}

String _phaseCommandNeedle(String command, String packageName) {
  final parts = command.split(' ');
  if (parts.length < 3) {
    return command;
  }
  return '${parts.take(3).join(' ')} --package $packageName';
}

bool _containsCommand(String command, String expectedPrefix) {
  return command == expectedPrefix || command.startsWith('$expectedPrefix ');
}

String _statusCommand(String packageName) {
  return 'fluoh package next --package $packageName --json';
}

Directory _packageRoot(Directory repository, String packagePath) {
  if (packagePath == '.' || packagePath.isEmpty) {
    return repository;
  }
  return Directory('${repository.path}/$packagePath');
}

PackageImplementationRecommendation?
_federatedOhosImplementationRecommendation({
  required PackageDiscovery discovery,
  required PackageManifestPackage package,
}) {
  for (final candidate in discovery.candidates) {
    if (candidate.name == package.name && candidate.path == package.path) {
      return candidate.implementationRecommendation('ohos');
    }
  }
  return null;
}

Future<File?> _latestTrace(FluohTask task) async {
  final preferred = File('${task.tracesDirectory.path}/support/trace.json');
  if (await preferred.exists()) {
    return preferred;
  }
  final traces = task.tracesDirectory;
  if (!await traces.exists()) {
    return null;
  }
  File? latest;
  await for (final entity in traces.list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('/trace.json')) {
      continue;
    }
    if (latest == null ||
        entity.lastModifiedSync().isAfter(latest.lastModifiedSync())) {
      latest = entity;
    }
  }
  return latest;
}

String _relativePath(Directory root, Directory directory) {
  final rootPath = root.absolute.path;
  final path = directory.absolute.path;
  if (path == rootPath) {
    return '.';
  }
  if (path.startsWith('$rootPath/')) {
    return path.substring(rootPath.length + 1);
  }
  return path;
}

Future<List<File>> _reportFiles(FluohTask task) async {
  final reports = task.reportsDirectory;
  if (!await reports.exists()) {
    return const [];
  }
  final files = <File>[];
  await for (final entity in reports.list()) {
    if (entity is File && _isReportFile(entity)) {
      files.add(entity);
    }
  }
  files.sort((a, b) {
    final timestamp = _reportTimestamp(b).compareTo(_reportTimestamp(a));
    if (timestamp != 0) {
      return timestamp;
    }
    return b.lastModifiedSync().compareTo(a.lastModifiedSync());
  });
  return files;
}

bool _isReportFile(File file) {
  final name = file.uri.pathSegments.isEmpty
      ? file.path
      : file.uri.pathSegments.last;
  return name == 'report.md' || RegExp(r'^report-\d+\.md$').hasMatch(name);
}

int _reportTimestamp(File file) {
  final name = file.uri.pathSegments.isEmpty
      ? file.path
      : file.uri.pathSegments.last;
  final match = RegExp(r'^report-(\d+)\.md$').firstMatch(name);
  if (match == null) {
    return 0;
  }
  return int.tryParse(match.group(1)!) ?? 0;
}

Future<_ReportCheckStatus> _inspectReportCheck(
  File report,
  FluohEnvironment environment,
) async {
  final skill = await resolveFluohSkillLocation(
    environment: environment.processEnvironment,
    workingDirectory: environment.workingDirectory,
  );
  final skillPath = skill.localPath;
  if (skillPath == null) {
    return _ReportCheckStatus(
      isRequired: true,
      scriptAvailable: false,
      reportPath: report.path,
      command:
          'python3 <skill-dir>/scripts/check_report.py ${_shellQuote(report.path)}',
      exitCode: null,
      passed: false,
      errors: const ['Bundled fluoh skill path was not found.'],
      warnings: const [],
      raw: const {},
    );
  }
  final script = File('$skillPath/scripts/check_report.py');
  final command =
      'python3 ${_shellQuote(script.path)} ${_shellQuote(report.path)}';
  if (!await script.exists()) {
    return _ReportCheckStatus(
      isRequired: true,
      scriptAvailable: false,
      reportPath: report.path,
      command: command,
      exitCode: null,
      passed: false,
      errors: ['Bundled report checker was not found: ${script.path}'],
      warnings: const [],
      raw: const {},
    );
  }

  final result = await Process.run('python3', [script.path, report.path]);
  final stdoutText = result.stdout.toString().trim();
  final stderrText = result.stderr.toString().trim();
  Map<String, Object?> raw = const <String, Object?>{};
  try {
    final decoded = jsonDecode(stdoutText);
    if (decoded is Map<String, Object?>) {
      raw = decoded;
    }
  } on FormatException {
    // Preserve stdout/stderr below so the repair action is still actionable.
  }
  final errors = _stringList(raw['errors']);
  final warnings = _stringList(raw['warnings']);
  final recommendation = _string(raw['recommendation']);
  final readyRecommendation = recommendation == 'ready';
  final passed =
      result.exitCode == 0 && raw['ok'] == true && readyRecommendation;
  return _ReportCheckStatus(
    isRequired: true,
    scriptAvailable: true,
    reportPath: report.path,
    command: command,
    exitCode: result.exitCode,
    passed: passed,
    errors: errors.isEmpty && !passed
        ? [
            if (result.exitCode == 0 &&
                raw['ok'] == true &&
                !readyRecommendation)
              'Support-ready reports must use release recommendation: ready.',
            if (stdoutText.isNotEmpty) stdoutText,
            if (stderrText.isNotEmpty) stderrText,
            if (stdoutText.isEmpty && stderrText.isEmpty)
              'check_report.py exited with ${result.exitCode}.',
          ]
        : errors,
    warnings: warnings,
    raw: raw,
  );
}

List<String> _stringList(Object? value) {
  if (value is List<Object?>) {
    return [
      for (final item in value)
        if (item != null) item.toString(),
    ];
  }
  return const [];
}

String _shellQuote(String value) {
  if (value.startsWith('<') && value.endsWith('>')) {
    return value;
  }
  if (RegExp(r'^[A-Za-z0-9_./:=@%+-]+$').hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", "'\\''")}'";
}

Future<_SupportTrace?> _readTrace(File? trace) async {
  if (trace == null || !await trace.exists()) {
    return null;
  }
  try {
    final decoded = jsonDecode(await trace.readAsString());
    if (decoded is Map<String, Object?>) {
      return _SupportTrace.fromJson(decoded);
    }
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
  return null;
}

class _SupportStep {
  const _SupportStep({
    required this.phase,
    required this.reason,
    required this.command,
    required this.matches,
  });

  final String phase;
  final String reason;
  final String command;
  final bool Function(String command) matches;
}

class _SupportTrace {
  const _SupportTrace({required this.invocations});

  factory _SupportTrace.fromJson(Map<String, Object?> json) {
    final rawInvocations = json['invocations'];
    final invocations = <_TraceInvocation>[];
    if (rawInvocations is List<Object?>) {
      for (final item in rawInvocations) {
        if (item is Map<String, Object?>) {
          invocations.add(_TraceInvocation.fromJson(item));
        }
      }
    } else {
      invocations.add(_TraceInvocation.fromJson(json));
    }
    return _SupportTrace(invocations: invocations);
  }

  final List<_TraceInvocation> invocations;

  _TraceInvocation? get latestFailedInvocation {
    for (final invocation in invocations.reversed) {
      if (!invocation.ok) {
        return invocation;
      }
      if (invocation.ok) {
        return null;
      }
    }
    return null;
  }

  _FailureStreak get latestFailureStreak {
    var count = 0;
    _TraceInvocation? latestFailure;
    for (final invocation in invocations.reversed) {
      if (invocation.ok) {
        break;
      }
      latestFailure ??= invocation;
      if (invocation.commandLine != latestFailure.commandLine) {
        break;
      }
      count += 1;
    }
    if (count == 0 || latestFailure == null) {
      return const _FailureStreak.none();
    }
    return _FailureStreak(
      count: count,
      commandLine: latestFailure.commandLine,
      exitCode: latestFailure.exitCode,
    );
  }

  bool passed(bool Function(String command) matches) {
    return invocations.any(
      (invocation) => invocation.ok && matches(invocation.commandLine),
    );
  }
}

class _EvidenceSummary {
  const _EvidenceSummary({
    required this.traceFound,
    required this.completedPhases,
    required this.missingPhases,
    required this.reportCreated,
  });

  factory _EvidenceSummary.fromTrace({
    required _SupportTrace? trace,
    required List<_SupportStep> steps,
    required List<File> reports,
  }) {
    final completedPhases = <String>[];
    final missingPhases = <String>[];
    for (final step in steps) {
      if (trace?.passed(step.matches) == true) {
        completedPhases.add(step.phase);
      } else {
        missingPhases.add(step.phase);
      }
    }
    return _EvidenceSummary(
      traceFound: trace != null,
      completedPhases: completedPhases,
      missingPhases: missingPhases,
      reportCreated: reports.isNotEmpty,
    );
  }

  final bool traceFound;
  final List<String> completedPhases;
  final List<String> missingPhases;
  final bool reportCreated;

  bool get supportEvidenceReady => missingPhases.isEmpty && reportCreated;

  Map<String, Object?> toJson() {
    return {
      'traceFound': traceFound,
      'completedPhases': completedPhases,
      'missingPhases': missingPhases,
      'reportCreated': reportCreated,
      'supportEvidenceReady': supportEvidenceReady,
    };
  }
}

class _ReportCheckStatus {
  const _ReportCheckStatus({
    required this.isRequired,
    required this.scriptAvailable,
    required this.reportPath,
    required this.command,
    required this.exitCode,
    required this.passed,
    required this.errors,
    required this.warnings,
    required this.raw,
  });

  const _ReportCheckStatus.notRequired()
    : isRequired = false,
      scriptAvailable = true,
      reportPath = null,
      command = null,
      exitCode = null,
      passed = false,
      errors = const [],
      warnings = const [],
      raw = const <String, Object?>{};

  final bool isRequired;
  final bool scriptAvailable;
  final String? reportPath;
  final String? command;
  final int? exitCode;
  final bool passed;
  final List<String> errors;
  final List<String> warnings;
  final Map<String, Object?> raw;

  Map<String, Object?> toJson() {
    return {
      'required': isRequired,
      'scriptAvailable': scriptAvailable,
      'passed': passed,
      if (reportPath != null) 'report': reportPath,
      if (command != null) 'command': command,
      if (exitCode != null) 'exitCode': exitCode,
      if (errors.isNotEmpty) 'errors': errors,
      if (warnings.isNotEmpty) 'warnings': warnings,
      if (raw.isNotEmpty) 'result': raw,
    };
  }
}

class _QualityProfile {
  const _QualityProfile({
    required this.packageRoot,
    required this.example,
    required this.packageTestFiles,
    required this.packageIntegrationTestFiles,
    required this.exampleTestFiles,
    required this.exampleIntegrationTestFiles,
    required this.automationScenarioFiles,
  });

  static Future<_QualityProfile> inspect({
    required Directory repository,
    required PackageManifestPackage package,
  }) async {
    final packageRoot = _packageRoot(repository, package.path);
    final packageRootPath = package.path.isEmpty ? '.' : package.path;
    final examplePath = _joinRelative(packageRootPath, 'example');
    final exampleRoot = Directory('${packageRoot.path}/example');
    final scenarioRoots = [
      Directory('${repository.path}/doc/fluoh/${package.name}/scenarios'),
      if (packageRoot.path != repository.path)
        Directory('${packageRoot.path}/doc/fluoh/${package.name}/scenarios'),
    ];
    return _QualityProfile(
      packageRoot: packageRootPath,
      example: _ExampleQualitySurface(
        path: examplePath,
        exists: await exampleRoot.exists(),
        pubspecExists: await File('${exampleRoot.path}/pubspec.yaml').exists(),
        ohosPlatformExists: await Directory(
          '${exampleRoot.path}/ohos',
        ).exists(),
        existingPlatforms: await _existingExamplePlatforms(exampleRoot),
      ),
      packageTestFiles: await _dartFileCount(
        Directory('${packageRoot.path}/test'),
      ),
      packageIntegrationTestFiles: await _dartFileCount(
        Directory('${packageRoot.path}/integration_test'),
      ),
      exampleTestFiles: await _dartFileCount(
        Directory('${exampleRoot.path}/test'),
      ),
      exampleIntegrationTestFiles: await _dartFileCount(
        Directory('${exampleRoot.path}/integration_test'),
      ),
      automationScenarioFiles: await _markdownFilesInDirectories(
        repository: repository,
        directories: scenarioRoots,
      ),
    );
  }

  final String packageRoot;
  final _ExampleQualitySurface example;
  final int packageTestFiles;
  final int packageIntegrationTestFiles;
  final int exampleTestFiles;
  final int exampleIntegrationTestFiles;
  final List<String> automationScenarioFiles;

  bool get hasFunctionalSurface =>
      packageIntegrationTestFiles > 0 ||
      exampleIntegrationTestFiles > 0 ||
      automationScenarioFiles.isNotEmpty;

  bool get launchOnlyRisk => example.exists && !hasFunctionalSurface;

  List<String> get interactionEvidenceMethods {
    return [
      if (packageIntegrationTestFiles > 0) 'package_integration_test',
      if (exampleIntegrationTestFiles > 0) 'example_integration_test',
      if (automationScenarioFiles.isNotEmpty) 'fluoh_scenario',
      if (example.exists) 'example_launch_smoke',
    ];
  }

  Map<String, Object?> toJson() {
    return {
      'packageRoot': packageRoot,
      'example': example.toJson(),
      'testSurfaces': {
        'packageTestFiles': packageTestFiles,
        'packageIntegrationTestFiles': packageIntegrationTestFiles,
        'exampleTestFiles': exampleTestFiles,
        'exampleIntegrationTestFiles': exampleIntegrationTestFiles,
        'automationScenarioFiles': automationScenarioFiles,
      },
      'interactionEvidenceMethods': interactionEvidenceMethods,
      'hasFunctionalSurface': hasFunctionalSurface,
      'launchOnlyRisk': launchOnlyRisk,
    };
  }
}

class _ExampleQualitySurface {
  const _ExampleQualitySurface({
    required this.path,
    required this.exists,
    required this.pubspecExists,
    required this.ohosPlatformExists,
    required this.existingPlatforms,
  });

  final String path;
  final bool exists;
  final bool pubspecExists;
  final bool ohosPlatformExists;
  final List<String> existingPlatforms;

  Map<String, Object?> toJson() {
    return {
      'path': path,
      'exists': exists,
      'pubspecExists': pubspecExists,
      'ohosPlatformExists': ohosPlatformExists,
      'existingPlatforms': existingPlatforms,
    };
  }
}

class _FailureStreak {
  const _FailureStreak({
    required this.count,
    required this.commandLine,
    required this.exitCode,
  });

  const _FailureStreak.none() : count = 0, commandLine = null, exitCode = null;

  final int count;
  final String? commandLine;
  final int? exitCode;

  bool get shouldBlock => count >= 3;

  Map<String, Object?> toJson() {
    return {
      'count': count,
      if (commandLine != null) 'command': commandLine,
      if (exitCode != null) 'exitCode': exitCode,
      'blocking': shouldBlock,
    };
  }
}

List<Map<String, Object?>> _remainingRisks({
  required _EvidenceSummary evidenceSummary,
  required _ReportCheckStatus reportCheck,
  required _FailureStreak failureStreak,
  required _QualityProfile qualityProfile,
  required PackageScopeStatus scopeStatus,
  required PackageSpecStatus specStatus,
  required VisualPageReadinessStatus visualPageReadiness,
  required String packageName,
}) {
  final risks = <Map<String, Object?>>[];
  if (specStatus.reviewRequired) {
    risks.add({
      'code': 'spec.review_required',
      'severity': 'actionRequired',
      'message':
          'Branch-local package spec is missing, incomplete, or not aligned with the current package contract.',
      'path': specStatus.path,
      'issues': [for (final issue in specStatus.issues) issue.toJson()],
    });
  }
  if (!scopeStatus.exists) {
    risks.add({
      'code': 'scope.missing',
      'severity': 'actionRequired',
      'message':
          'Missing package support scope for support planning and evidence tracking.',
      'path': scopeStatus.path,
      'nextCommand': 'fluoh package scope init --package $packageName --json',
    });
  } else if (!scopeStatus.planningReady) {
    risks.add({
      'code': 'scope.planning_incomplete',
      'severity': 'actionRequired',
      'message':
          'P0 scope research, implementation plan, or test plan is incomplete.',
      'path': scopeStatus.path,
      'issues': [
        for (final issue in scopeStatus.planningIssues) issue.toJson(),
      ],
    });
  } else if (!scopeStatus.functionalEvidenceReady) {
    risks.add({
      'code': 'scope.functional_evidence_missing',
      'severity': 'actionRequired',
      'message':
          'Supported or degraded P0 scope entries are missing functional evidence.',
      'path': scopeStatus.path,
      'issues': [
        for (final issue in scopeStatus.functionalEvidenceIssues)
          issue.toJson(),
      ],
    });
  }
  if (failureStreak.count > 0) {
    risks.add({
      'code': 'trace.latest_failure',
      'severity': failureStreak.shouldBlock ? 'blocked' : 'repair',
      'message': failureStreak.shouldBlock
          ? 'The same traced command failed repeatedly.'
          : 'The latest traced command failed and needs focused repair.',
      'failureStreak': failureStreak.toJson(),
    });
  }
  if (!evidenceSummary.traceFound) {
    risks.add({
      'code': 'evidence.trace_missing',
      'severity': 'actionRequired',
      'message': 'No support trace has been recorded yet.',
    });
  }
  if (evidenceSummary.missingPhases.isNotEmpty) {
    risks.add({
      'code': 'evidence.phases_missing',
      'severity': 'actionRequired',
      'message': 'Required support phases are missing passed evidence.',
      'phases': evidenceSummary.missingPhases,
    });
  }
  final missingExistingPlatformPhases = evidenceSummary.missingPhases
      .where((phase) => phase.startsWith('existing-'))
      .toList();
  if (missingExistingPlatformPhases.isNotEmpty) {
    final platforms = <String>{
      for (final phase in missingExistingPlatformPhases)
        _existingPlatformForPhase(phase),
    }.where((platform) => platform.isNotEmpty).toList();
    risks.add({
      'code': 'quality.existing_platform_regression_missing',
      'severity': 'actionRequired',
      'message':
          'Existing example platform build/run or automation evidence is missing after FlutterOH SDK selection.',
      'phases': missingExistingPlatformPhases,
      'platforms': platforms,
    });
  }
  if (!visualPageReadiness.ready) {
    risks.add({
      'code': 'quality.visual_page_readiness_missing',
      'severity': 'actionRequired',
      'message':
          'Passed mobile run evidence needs explicit visual page-readiness review before the support report.',
      'path': visualPageReadiness.path,
      'issues': visualPageReadiness.issues,
    });
  }
  if (evidenceSummary.missingPhases.isEmpty &&
      visualPageReadiness.ready &&
      !evidenceSummary.reportCreated) {
    risks.add({
      'code': 'evidence.report_missing',
      'severity': 'actionRequired',
      'message': 'Missing support report generated from trace evidence.',
    });
  } else if (evidenceSummary.missingPhases.isEmpty &&
      visualPageReadiness.ready &&
      reportCheck.isRequired &&
      !reportCheck.passed) {
    risks.add({
      'code': 'evidence.report_check_failed',
      'severity': reportCheck.scriptAvailable ? 'actionRequired' : 'blocked',
      'message': reportCheck.scriptAvailable
          ? 'The support report exists but check_report.py has not passed.'
          : 'The bundled report checker is unavailable.',
      'reportCheck': reportCheck.toJson(),
    });
  } else if (evidenceSummary.missingPhases.isEmpty &&
      visualPageReadiness.ready) {
    risks.add({
      'code': 'release.readiness_not_checked',
      'severity': 'info',
      'message':
          'Support evidence is ready; release readiness still needs package status or package check.',
      'nextCommand': 'fluoh package status --package $packageName --json',
    });
  }
  if (!qualityProfile.hasFunctionalSurface) {
    risks.add({
      'code': 'quality.functional_surface_missing',
      'severity': 'warning',
      'message':
          'No integration_test or fluoh scenario was found; current evidence may only prove build or launch smoke behavior.',
      'exploratoryCommand':
          'fluoh drive ohos --package $packageName --profile exploratory-smoke --json',
      'scenarioCommand':
          'python3 <skill-dir>/scripts/new_scenario.py . --platform ohos --package $packageName --name ${packageName}_ohos_functional',
    });
  }
  return risks;
}

String _joinRelative(String parent, String child) {
  if (parent == '.' || parent.isEmpty) {
    return child;
  }
  return '$parent/$child';
}

Future<int> _dartFileCount(Directory directory) async {
  if (!await directory.exists()) {
    return 0;
  }
  var count = 0;
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      count += 1;
    }
  }
  return count;
}

Future<List<String>> _existingExamplePlatforms(Directory exampleRoot) async {
  if (!await exampleRoot.exists()) {
    return const [];
  }
  final platforms = <String>[];
  for (final platform in _existingRegressionPlatforms) {
    if (await Directory('${exampleRoot.path}/$platform').exists()) {
      platforms.add(platform);
    }
  }
  return platforms;
}

const List<String> _existingRegressionPlatforms = [
  'android',
  'ios',
  'macos',
  'linux',
  'web',
  'windows',
];

bool _shouldDriveExistingPlatform(String platform) {
  if (platform == 'android') {
    return true;
  }
  if (platform == 'ios') {
    return Platform.isMacOS;
  }
  return false;
}

String _existingPlatformForPhase(String phase) {
  var value = phase.replaceFirst('existing-', '');
  for (final suffix in const [
    '-automation-dry-run',
    '-automation-run',
    '-regression',
  ]) {
    if (value.endsWith(suffix)) {
      value = value.substring(0, value.length - suffix.length);
      break;
    }
  }
  return value;
}

Future<List<String>> _markdownFilesInDirectories({
  required Directory repository,
  required List<Directory> directories,
}) async {
  final files = <String>{};
  for (final directory in directories) {
    files.addAll(
      await _markdownFiles(repository: repository, directory: directory),
    );
  }
  return files.toList()..sort();
}

Future<List<String>> _markdownFiles({
  required Directory repository,
  required Directory directory,
}) async {
  if (!await directory.exists()) {
    return const [];
  }
  final files = <String>[];
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.md')) {
      files.add(
        '${_relativePath(repository, entity.parent)}/${_fileName(entity)}',
      );
    }
  }
  files.sort();
  return files;
}

String _fileName(File file) {
  return file.uri.pathSegments.isEmpty ? file.path : file.uri.pathSegments.last;
}

class _TraceInvocation {
  const _TraceInvocation({
    required this.commandLine,
    required this.ok,
    this.exitCode,
    this.diagnostics = const [],
    this.stdoutTail,
    this.stderrTail,
    this.nextCommand,
  });

  factory _TraceInvocation.fromJson(Map<String, Object?> json) {
    final result = json['result'];
    final resultMap = result is Map<String, Object?> ? result : null;
    return _TraceInvocation(
      commandLine:
          _string(json['commandLine']) ?? _string(json['command']) ?? '',
      ok: json['ok'] == true,
      exitCode: json['exitCode'] is int ? json['exitCode'] as int : null,
      diagnostics: _diagnostics(resultMap),
      stdoutTail: _string(resultMap?['stdoutTail']),
      stderrTail: _string(resultMap?['stderrTail']),
      nextCommand: _string(resultMap?['nextCommand']),
    );
  }

  final String commandLine;
  final bool ok;
  final int? exitCode;
  final List<Object?> diagnostics;
  final String? stdoutTail;
  final String? stderrTail;
  final String? nextCommand;
}

List<Object?> _diagnostics(Map<String, Object?>? result) {
  if (result == null) {
    return const [];
  }
  final diagnostics = result['diagnostics'];
  if (diagnostics is List<Object?>) {
    return diagnostics;
  }
  return const [];
}

String? _string(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}

class _SupportNextAction {
  const _SupportNextAction({
    required this.type,
    required this.state,
    required this.phase,
    required this.reason,
    this.command,
    this.rerunCommand,
    this.statusCommand,
    this.nextCommands = const [],
    this.requiredEdits = const [],
    this.details,
  });

  factory _SupportNextAction.commandRequired({
    required String phase,
    required String reason,
    required String command,
    required String rerunCommand,
  }) {
    return _SupportNextAction(
      type: 'commandRequired',
      state: 'actionRequired',
      phase: phase,
      reason: reason,
      command: command,
      rerunCommand: rerunCommand,
    );
  }

  factory _SupportNextAction.editRequired({
    required String phase,
    required String reason,
    required String rerunCommand,
    String? statusCommand,
    List<Object?> requiredEdits = const [],
    Map<String, Object?>? details,
  }) {
    return _SupportNextAction(
      type: 'editRequired',
      state: 'actionRequired',
      phase: phase,
      reason: reason,
      rerunCommand: rerunCommand,
      statusCommand: statusCommand,
      requiredEdits: requiredEdits,
      details: details,
    );
  }

  factory _SupportNextAction.ready({
    required String phase,
    required String reason,
    required String statusCommand,
    List<String> nextCommands = const [],
  }) {
    return _SupportNextAction(
      type: 'ready',
      state: 'ready',
      phase: phase,
      reason: reason,
      statusCommand: statusCommand,
      nextCommands: nextCommands,
    );
  }

  factory _SupportNextAction.blocked({
    required String phase,
    required String reason,
    required String statusCommand,
    Map<String, Object?>? details,
  }) {
    return _SupportNextAction(
      type: 'blocked',
      state: 'blocked',
      phase: phase,
      reason: reason,
      statusCommand: statusCommand,
      details: details,
    );
  }

  final String type;
  final String state;
  final String phase;
  final String reason;
  final String? command;
  final String? rerunCommand;
  final String? statusCommand;
  final List<String> nextCommands;
  final List<Object?> requiredEdits;
  final Map<String, Object?>? details;

  Map<String, Object?> toJson() {
    return {
      'type': type,
      'state': state,
      'phase': phase,
      'reason': reason,
      if (command != null) 'command': command,
      if (rerunCommand != null) 'rerunCommand': rerunCommand,
      if (statusCommand != null) 'statusCommand': statusCommand,
      if (nextCommands.isNotEmpty) 'nextCommands': nextCommands,
      if (requiredEdits.isNotEmpty) 'requiredEdits': requiredEdits,
      if (details != null) 'details': details,
    };
  }
}
