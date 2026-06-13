import 'dart:io';

import 'package:args/command_runner.dart';

import '../../cli/argument_validation.dart';
import '../../cli/command_usage.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../package/git/package_git.dart';
import '../../package/manifest/package_manifest.dart';
import '../../schema/yaml_utils.dart';
import '../../sdk/sdk_project_config.dart';
import '../platform_workflow_policy.dart';

const _reportCheckCommand =
    'python3 <skill-dir>/scripts/check_report.py <report-path>';

/// Top-level `fluoh plan` command group.
class PlanCommand extends FluohCommand<int> {
  /// Creates the plan command group.
  PlanCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    addSubcommand(
      PlanAppCommand(environment: environment, stdout: stdout, output: _output),
    );
    addSubcommand(
      PlanPackageCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
  }

  final TerminalOutput _output;

  @override
  String get name => 'plan';

  @override
  String get description => 'Plan AI-assisted FlutterOH adaptation work.';

  @override
  String get usage => '$description\n\n$_usageWithoutDescription';

  @override
  void printUsage() {
    _output.write(usage);
  }

  @override
  Never usageException(String message) {
    throw UsageException(message, _usageWithoutDescription);
  }

  String get _usageWithoutDescription {
    return [
      'Usage: $invocation',
      argParser.usage,
      '',
      formatCommandUsage(
        subcommands,
        sections: const [
          CommandUsageSection('Adaptation plans:', ['app', 'package']),
        ],
        isSubcommand: true,
        lineLength: argParser.usageLineLength,
        style: _output.style,
      ),
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }
}

/// Prints a read-only plan for continuing a FlutterOH package branch.
class PlanPackageCommand extends FluohCommand<int> {
  /// Creates the package adaptation planning command.
  PlanPackageCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser
      ..addOption(
        'package',
        valueHelp: 'name',
        help: 'Package name. Defaults to the current package branch.',
      )
      ..addFlag('json', negatable: false, help: 'Print the plan as JSON.');
  }

  /// Runtime environment.
  final FluohEnvironment environment;

  /// JSON output writer.
  final OutputWriter stdout;

  final TerminalOutput _output;

  @override
  String get name => 'package';

  @override
  String get description => 'Plan adapting the current package branch to OHOS.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final json = argResults!.flag('json');
    final plan = await _buildPackageAdaptationPlan(
      environment,
      requestedPackage: argResults!.option('package')?.trim(),
    );
    if (json) {
      writeMachineOutput(
        stdout,
        command: 'plan package',
        ok: plan['readyToPlan'] == true,
        exitCode: 0,
        fields: {'changed': false, 'applied': false, 'plan': plan},
      );
    } else {
      _printPlan(plan);
    }
    return 0;
  }

  void _printPlan(Map<String, Object?> plan) {
    _output.success('Package adaptation plan');
    final package = plan['package'] as Map<String, Object?>?;
    _output.info('Package: ${package?['name'] ?? '<unknown>'}');
    _output.info('SDK: ${(plan['sdk'] as Map<String, Object?>)['selected']}');
    final repository = plan['repository'] as Map<String, Object?>?;
    _output.info('Branch: ${repository?['branch'] ?? '<unknown>'}');
    for (final item in plan['queue'] as List<Object?>) {
      final step = item as Map<String, Object?>;
      _output.next(step['command'] as String);
    }
  }
}

/// Prints a read-only plan for adapting a Flutter app project to OHOS.
class PlanAppCommand extends FluohCommand<int> {
  /// Creates the app adaptation planning command.
  PlanAppCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser
      ..addOption(
        'sdk',
        valueHelp: 'version-or-series',
        help: 'FlutterOH SDK version or version series to plan for.',
      )
      ..addFlag('json', negatable: false, help: 'Print the plan as JSON.');
  }

  /// Runtime environment.
  final FluohEnvironment environment;

  /// JSON output writer.
  final OutputWriter stdout;

  final TerminalOutput _output;

  @override
  String get name => 'app';

  @override
  String get description => 'Plan adapting the current Flutter app to OHOS.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final json = argResults!.flag('json');
    final plan = await _buildAppAdaptationPlan(
      environment,
      requestedSdk: argResults!.option('sdk')?.trim(),
    );
    if (json) {
      writeMachineOutput(
        stdout,
        command: 'plan app',
        ok: plan['readyToPlan'] == true,
        exitCode: 0,
        fields: {'changed': false, 'applied': false, 'plan': plan},
      );
    } else {
      _printPlan(plan);
    }
    return 0;
  }

  void _printPlan(Map<String, Object?> plan) {
    _output.success('App adaptation plan');
    _output.info('Project: ${plan['projectName'] ?? '<unknown>'}');
    _output.info('SDK: ${(plan['sdk'] as Map<String, Object?>)['selected']}');
    _output.info(
      'OHOS directory: '
      '${(plan['project'] as Map<String, Object?>)['hasOhos'] == true ? 'present' : 'missing'}',
    );
    for (final item in plan['queue'] as List<Object?>) {
      final step = item as Map<String, Object?>;
      _output.next(step['command'] as String);
    }
  }
}

Future<Map<String, Object?>> _buildAppAdaptationPlan(
  FluohEnvironment environment, {
  required String? requestedSdk,
}) async {
  final root = environment.workingDirectory;
  final pubspec = File('${root.path}/pubspec.yaml');
  final pubspecContent = await pubspec.exists()
      ? await pubspec.readAsString()
      : '';
  final projectName = pubspecContent.isEmpty
      ? null
      : _topLevelString(pubspecContent, 'name');
  final isFlutterProject = _isFlutterProject(pubspecContent);
  final readyToPlan = pubspec.existsSync() && isFlutterProject;
  final selectedSdk = requestedSdk?.isNotEmpty == true
      ? requestedSdk
      : await readProjectSdkVersion(root);
  final sdkValue = selectedSdk ?? '<sdk-version-or-line>';
  final scope = projectName ?? _scopePlaceholder();
  final traceDir =
      '.fluoh/traces/${_scopeSlug(projectName ?? 'app', fallback: 'app')}/adaptation';
  final platforms = {
    for (final platform in const [
      'ohos',
      'android',
      'ios',
      'macos',
      'linux',
      'web',
      'windows',
    ])
      platform: Directory('${root.path}/$platform').existsSync(),
  };
  return {
    'schema': 1,
    'adaptationKind': 'app',
    'readyToPlan': readyToPlan,
    'workingDirectory': root.path,
    'projectName': projectName,
    if (!readyToPlan)
      'error': {
        'message': pubspec.existsSync()
            ? 'Current directory is not a Flutter app project.'
            : 'Missing pubspec.yaml.',
      },
    'project': {
      'hasPubspec': pubspec.existsSync(),
      'isFlutter': isFlutterProject,
      'hasOhos': platforms['ohos'],
      'platformDirectories': platforms,
    },
    'sdk': {
      'selected': sdkValue,
      'source': requestedSdk?.isNotEmpty == true
          ? 'option'
          : selectedSdk == null
          ? 'placeholder'
          : 'fluoh.yaml',
    },
    'queue': readyToPlan
        ? _appAdaptationQueue(
            sdkValue,
            platforms,
            scope: scope,
            traceDir: traceDir,
          )
        : const <Map<String, Object?>>[],
    'automationRunbook': _automationRunbook('app', active: readyToPlan),
    'deliveryGate': _deliveryGate(
      kind: 'app',
      active: readyToPlan,
      finalCheckCommands: readyToPlan
          ? _appFinalCheckCommands(platforms, traceDir: traceDir)
          : const <String>[],
      reportCommand:
          'fluoh report create --scope $scope '
          '--trace-dir $traceDir --json',
    ),
    'safety': _adaptationSafety(),
  };
}

Future<Map<String, Object?>> _buildPackageAdaptationPlan(
  FluohEnvironment environment, {
  required String? requestedPackage,
}) async {
  final root = environment.workingDirectory;
  PackageManifest? manifest;
  Object? manifestError;
  try {
    manifest = await readPackageManifest(root);
  } on Object catch (error) {
    manifestError = error;
  }
  if (manifest == null) {
    return {
      'schema': 1,
      'adaptationKind': 'package',
      'readyToPlan': false,
      'workingDirectory': root.path,
      'error': {
        'message': manifestError is UsageException
            ? manifestError.message
            : manifestError?.toString() ?? 'Missing package fluoh.yaml.',
      },
      'sdk': {'selected': '<sdk-version-or-line>', 'source': 'placeholder'},
      'queue': const <Map<String, Object?>>[],
      'automationRunbook': _automationRunbook('package', active: false),
      'deliveryGate': _deliveryGate(
        kind: 'package',
        active: false,
        finalCheckCommands: const <String>[],
        reportCommand:
            'fluoh report create --scope <name> --package <name> --trace-dir .fluoh/traces/<name>/adaptation --json',
      ),
      'safety': _adaptationSafety(),
    };
  }

  final package = manifest.packageForName(requestedPackage);
  final branch = await _currentBranchOrNull(root);
  final status = await runGit(
    ['status', '--short'],
    workingDirectory: root,
    allowFailure: true,
  );
  final dirty = status.stdout.toString().trim().isNotEmpty;
  final packageDirectory = Directory(
    package.path == '.' ? root.path : '${root.path}/${package.path}',
  );
  final exampleDirectory = Directory('${packageDirectory.path}/example');
  final platforms = _packageExamplePlatforms(exampleDirectory);
  final scope = package.name;
  final traceDir = '.fluoh/traces/$scope/adaptation';
  return {
    'schema': 1,
    'adaptationKind': 'package',
    'readyToPlan': true,
    'workingDirectory': root.path,
    'repository': {
      'url': manifest.repositoryUrl,
      'branch': branch,
      'manifestBranch': manifest.branch,
      'branchMatchesManifest': branch == manifest.branch,
      'dirty': dirty,
      'statusShort': [
        for (final line in status.stdout.toString().split('\n'))
          if (line.trim().isNotEmpty) line,
      ],
    },
    'upstream': {
      'url': manifest.upstreamUrl,
      'branch': manifest.upstreamBranch,
    },
    'sdk': {'selected': manifest.sdkVersion, 'source': 'fluoh.yaml'},
    'package': {
      'name': package.name,
      'path': package.path,
      'upstreamVersion': package.upstreamVersion,
      'upstreamRef': package.upstreamRef,
      'upstreamCommit': package.upstreamCommit,
      'releaseVersion': package.version,
      'releaseStatus': package.status,
      'examplePath': _relativePath(root, exampleDirectory),
      'hasExample': exampleDirectory.existsSync(),
      'examplePlatforms': platforms,
    },
    'queue': _packageAdaptationQueue(scope, traceDir, platforms),
    'automationRunbook': _automationRunbook('package', active: true),
    'deliveryGate': _deliveryGate(
      kind: 'package',
      active: true,
      finalCheckCommands: _packageFinalCheckCommands(
        scope,
        platforms,
        traceDir: traceDir,
      ),
      reportCommand:
          'fluoh report create --scope $scope --package $scope --trace-dir $traceDir --json',
      packageName: scope,
    ),
    'safety': _adaptationSafety(),
  };
}

List<Map<String, Object?>> _appAdaptationQueue(
  String sdk,
  Map<String, bool> platforms, {
  required String scope,
  required String traceDir,
}) {
  final items = <Map<String, Object?>>[
    _queueItem(
      phase: 'setup',
      command: 'fluoh source update',
      mutating: true,
      requiresApproval: true,
      evidence: 'source update result',
    ),
    _queueItem(
      phase: 'setup',
      command: 'fluoh sdk use $sdk --pub-get',
      mutating: true,
      requiresApproval: true,
      evidence: 'selected SDK and OHOS platform directory',
    ),
    _queueItem(
      phase: 'deps',
      command: 'fluoh deps check --json',
      mutating: false,
      evidence: 'dependency support JSON',
    ),
    _queueItem(
      phase: 'deps',
      command: 'fluoh deps fix --dry-run --json',
      mutating: false,
      evidence: 'dependency rewrite plan',
    ),
    _queueItem(
      phase: 'deps',
      command: 'fluoh deps fix',
      mutating: true,
      requiresApproval: true,
      evidence: 'pubspec dependency rewrite summary',
    ),
    ..._ohosAdaptationQueue(traceDir: traceDir),
    for (final command in _mobileDriveCommands(platforms, traceDir: traceDir))
      _queueItem(
        phase: 'automation',
        command: command,
        mutating: true,
        evidence: 'automation coverage policy, scenarios, and repair queue',
      ),
  ];
  for (final platform in const [
    'android',
    'ios',
    'macos',
    'linux',
    'web',
    'windows',
  ]) {
    if (platforms[platform] != true) {
      continue;
    }
    final policy = platformWorkflowPolicy(platform);
    items
      ..add(
        _queueItem(
          phase: 'doctor',
          command: policy.doctorCommand(strict: true),
          mutating: false,
          evidence: '${policy.label} toolchain diagnostic JSON',
        ),
      )
      ..add(
        _queueItem(
          phase: 'regression',
          command: _regressionCommand(platform, traceDir),
          mutating: true,
          evidence: '$platform functional regression evidence',
        ),
      );
  }
  items.add(
    _queueItem(
      phase: 'report',
      command:
          'fluoh report create --scope $scope --trace-dir $traceDir --json',
      mutating: true,
      evidence: 'local AI report path',
    ),
  );
  items.add(
    _queueItem(
      phase: 'report-check',
      command: _reportCheckCommand,
      mutating: false,
      evidence: 'canonical report validation JSON',
    ),
  );
  return items;
}

List<Map<String, Object?>> _packageAdaptationQueue(
  String packageName,
  String traceDir,
  Map<String, bool> platforms,
) {
  final items = <Map<String, Object?>>[
    _queueItem(
      phase: 'docs',
      command: 'fluoh package docs refresh --dry-run',
      mutating: false,
      evidence: 'generated package docs refresh plan',
    ),
    _queueItem(
      phase: 'docs',
      command: 'fluoh package docs refresh',
      mutating: true,
      requiresApproval: true,
      evidence: 'refreshed FLUOH.md and AGENTS.md generated sections',
    ),
    _queueItem(
      phase: 'verify',
      command:
          'fluoh verify --package $packageName --json --trace-dir $traceDir',
      mutating: false,
      evidence: 'pub get, analysis, tests, and trace manifest',
    ),
    ..._ohosAdaptationQueue(packageName: packageName, traceDir: traceDir),
    for (final command in _mobileDriveCommands(
      platforms,
      packageName: packageName,
      traceDir: traceDir,
    ))
      _queueItem(
        phase: 'automation',
        command: command,
        mutating: true,
        evidence: 'automation coverage policy, scenarios, and repair queue',
      ),
  ];
  for (final platform in const [
    'android',
    'ios',
    'macos',
    'linux',
    'web',
    'windows',
  ]) {
    if (platforms[platform] != true) {
      continue;
    }
    final policy = platformWorkflowPolicy(platform);
    items
      ..add(
        _queueItem(
          phase: 'doctor',
          command: policy.doctorCommand(strict: true),
          mutating: false,
          evidence: '${policy.label} toolchain diagnostic JSON',
        ),
      )
      ..add(
        _queueItem(
          phase: 'regression',
          command: _packageRegressionCommand(platform, packageName, traceDir),
          mutating: true,
          evidence: '$platform package example functional evidence',
        ),
      );
  }
  items
    ..add(
      _queueItem(
        phase: 'release-check',
        command: 'fluoh package status --package $packageName',
        mutating: false,
        evidence: 'release readiness summary',
      ),
    )
    ..add(
      _queueItem(
        phase: 'report',
        command:
            'fluoh report create --scope $packageName --package $packageName --trace-dir $traceDir --json',
        mutating: true,
        evidence: 'local AI report path',
      ),
    )
    ..add(
      _queueItem(
        phase: 'report-check',
        command: _reportCheckCommand,
        mutating: false,
        evidence: 'canonical report validation JSON',
      ),
    )
    ..add(
      _queueItem(
        phase: 'handoff',
        command: 'fluoh package handoff --package $packageName --json',
        mutating: false,
        evidence: 'branch state, reports, traces, and next commands',
      ),
    )
    ..add(
      _queueItem(
        phase: 'release-check',
        command:
            'fluoh package check --package $packageName --report <report-path> --json',
        mutating: false,
        evidence: 'release gate JSON with certification report validation',
      ),
    );
  return items;
}

Map<String, Object?> _queueItem({
  required String phase,
  required String command,
  required bool mutating,
  required String evidence,
  bool requiresApproval = false,
}) {
  return {
    'phase': phase,
    'command': command,
    'mutating': mutating,
    'requiresApproval': requiresApproval || mutating,
    'expectedEvidence': evidence,
    'mustCompleteForDelivery': _mustCompleteForDelivery(command, phase),
    'failureAction': _failureAction(command),
  };
}

Map<String, Object?> _adaptationSafety() {
  return {
    'requiresConfirmationBeforeMutation': true,
    'autoCheckpointCommits': true,
    'scopeApprovalAuthorizesLocalCommits': true,
    'willNotRunWithoutSeparateApproval': [
      'release',
      'push',
      'force-push',
      'destructive git commands',
      'public API breaks',
    ],
  };
}

List<Map<String, Object?>> _qualityGates(String kind, {required bool active}) {
  final adaptationKind = kind == 'app' ? 'app' : 'package';
  return [
    {
      'id': 'functional-test-baseline',
      'requiredForReady': active,
      'description':
          'Before final verification, inspect existing $adaptationKind tests '
          'and integration tests against public API, platform interfaces, '
          'example flows, permissions, and behavior paths; add or repair '
          'missing functional tests before claiming ready.',
    },
    {
      'id': 'complete-existing-platform-matrix',
      'requiredForReady': active,
      'description':
          'Do not validate only OHOS. Run functional verification for OHOS '
          'and every existing non-OHOS platform directory when the current '
          'host/toolchain supports it; otherwise record the diagnostic '
          'command, unsupported environment reason, and remaining blocker in '
          'the report.',
    },
    {
      'id': 'behavior-evidence-not-smoke',
      'requiredForReady': active,
      'description':
          'Ready evidence must validate library behavior through package '
          'tests, integration_test, real fluoh drive JSON, or manual-assisted '
          'tool-readable assertions; build, launch, screenshot, or run-all '
          'smoke evidence is insufficient alone.',
    },
  ];
}

Map<String, Object?> _automationRunbook(String kind, {required bool active}) {
  return {
    'mode': 'autonomous-to-delivery',
    'commandSource': 'queue',
    'loop':
        'run, parse, fix, rerun until deliveryGate is satisfied or an explicit blocker remains',
    'qualityGates': _qualityGates(kind, active: active),
    'executionRules': [
      'Run queue commands in order after the approved adaptation scope.',
      'Before final verification, inspect whether existing tests cover the package or app behavior; add or repair missing functional tests before running the final test matrix.',
      'Parse every --json result before editing or deciding the next step.',
      'Follow diagnostics.nextCommand when present; otherwise rerun the failed command after the smallest relevant fix.',
      'Do not stop after setup, verify, build, run, or screenshot-only smoke evidence.',
      'Do not focus only on OHOS; every existing platform must have functional evidence or an explicit unsupported-host/toolchain diagnostic blocker.',
      'Do not skip drive, handoff, report creation, report check, or package check when they are applicable.',
      'Create local checkpoint commits after completed phases when command evidence is clean.',
      'Do not push, release, force-push, or run destructive Git commands without separate maintainer approval.',
    ],
    'checkpointPolicy': {
      'mode': 'auto-local-commits',
      'scopeApprovalAuthorizesCommits': true,
      'commitPhases': [
        'generated baseline',
        'selected SDK baseline',
        'implementation',
        'tests and example verification',
        'release metadata',
        'delivery report handoff',
      ],
      'beforeCommit': [
        "run the phase's relevant verification command",
        'review git status --short and git diff --check',
        'stage only intentional tracked files for the phase',
        'exclude .fluoh reports, traces, caches, credentials, signing secrets, and machine-local paths',
      ],
      'afterCommit': [
        'record the commit hash in the AI report Local State section',
        'continue to the next queue phase',
      ],
    },
    'repairLoop': {
      'onFailure': [
        'classify the failure as fluoh CLI, Source data, AI skill, local environment, upstream package, or project/package implementation',
        'read diagnostics, stdoutTail, stderrTail, trace, feedbackCandidates, and traceError',
        'fix the smallest owned issue',
        'rerun the failed command or printed nextCommand',
        'collect feedback candidates into the report when traces report them',
      ],
      'stopOnlyWhen': [
        'deliveryGate.readyRequires is satisfied',
        'deliveryGate.blockedWhen contains the remaining blocker',
        'a maintainer decision listed in deliveryGate.needsMaintainerDecision is required',
      ],
    },
    'adaptationKind': kind,
  };
}

Map<String, Object?> _deliveryGate({
  required String kind,
  required bool active,
  required List<String> finalCheckCommands,
  required String reportCommand,
  String? packageName,
}) {
  final commonReadyRequires = [
    'existing tests and integration tests were reviewed against public API, platform interfaces, example flows, permissions, and behavior paths before final verification; missing or weak functional tests were added or a concrete blocker is recorded',
    'functional evidence validates the library or app behavior, not only build, launch, screenshot, or run-all smoke',
    'OHOS and every existing non-OHOS platform directory has functional build/run/integration/drive evidence when the current host supports it; unsupported platforms have exact diagnostic evidence and skip reasons',
    'all queue items marked mustCompleteForDelivery passed or have a concrete blocker recorded',
    'finalCheckCommands ran after the last implementation edit',
    'canonical report exists under .fluoh/reports/',
    'reportCheckCommand passes against the canonical report',
    'the final response states exactly one terminal state and only remaining blocking risks',
  ];
  return {
    'active': active,
    'status': active ? 'active' : 'blocked',
    'terminalStates': ['ready', 'blocked', 'needs-maintainer-decision'],
    'finalCheckCommands': finalCheckCommands,
    'reportCommand': reportCommand,
    'reportCheckCommand': _reportCheckCommand,
    'requiresReportCheckPass': active,
    'readyRequires': active
        ? [
            ...commonReadyRequires,
            if (kind == 'app') ...[
              'OHOS build and run evidence are recorded, or the final report records the exact local blocker',
              'interaction evidence uses integration_test, real fluoh drive JSON, or tool-readable manual-assisted evidence',
            ],
            if (kind == 'package') ...[
              'fluoh package handoff --package ${packageName ?? '<name>'} --json reports current branch evidence',
              'fluoh package check --package ${packageName ?? '<name>'} --report <report-path> --json passes, or the report clearly records why this needs maintainer decision',
            ],
          ]
        : ['plan is readyToPlan before mutating files or claiming delivery'],
    'blockedWhen': [
      'a required local toolchain, SDK, signing, device, emulator, or host platform is unavailable after running the diagnostic command',
      'the selected upstream package cannot be made compatible with the selected FlutterOH SDK without maintainer approval',
      'automation evidence cannot be made tool-readable with the available device or emulator',
    ],
    'needsMaintainerDecision': [
      'release, publish, push, tag, force-push, or destructive Git operation',
      'public API break, upstream downgrade, SDK line change, release version override, or signing policy decision',
    ],
  };
}

bool _mustCompleteForDelivery(String command, String phase) {
  if (command.startsWith('Resolve package setup') ||
      command.startsWith('cd ') ||
      command.contains('--dry-run') ||
      command.contains('--plan')) {
    return false;
  }
  return const {
    'deps',
    'docs',
    'doctor',
    'verify',
    'ohos',
    'automation',
    'regression',
    'report',
    'report-check',
    'handoff',
    'release-check',
  }.contains(phase);
}

String _failureAction(String command) {
  if (command.contains('--dry-run') || command.contains('--plan')) {
    return 'inspect the plan output before running the mutating command';
  }
  if (command.contains(' package handoff ')) {
    return 'fix the reported branch, dirty tree, trace, or report gap before continuing';
  }
  if (command.contains(' package check ')) {
    return 'fix the release gate finding, rerun the failed command, then rerun package check';
  }
  if (command.contains('check_report.py')) {
    return 'fix report validation failures, update the report evidence, then rerun report check';
  }
  if (command.contains(' report create ')) {
    return 'create or update the report, then run the report check command';
  }
  return 'parse JSON diagnostics, make the smallest fix, and rerun this command or its nextCommand';
}

List<String> _appFinalCheckCommands(
  Map<String, bool> platforms, {
  required String traceDir,
}) {
  return [
    'git diff --check',
    for (final item in _ohosAdaptationQueue(traceDir: traceDir))
      item['command']! as String,
    ..._mobileDriveCommands(platforms, traceDir: traceDir),
    for (final platform in const [
      'android',
      'ios',
      'macos',
      'linux',
      'web',
      'windows',
    ])
      if (platforms[platform] == true) ...[
        platformWorkflowPolicy(platform).doctorCommand(strict: true),
        _regressionCommand(platform, traceDir),
      ],
    _reportCheckCommand,
  ];
}

List<String> _packageFinalCheckCommands(
  String packageName,
  Map<String, bool> platforms, {
  required String traceDir,
}) {
  return [
    'git diff --check',
    'fluoh verify --package $packageName --json --trace-dir $traceDir',
    for (final item in _ohosAdaptationQueue(
      packageName: packageName,
      traceDir: traceDir,
    ))
      item['command']! as String,
    ..._mobileDriveCommands(
      platforms,
      packageName: packageName,
      traceDir: traceDir,
    ),
    for (final platform in const [
      'android',
      'ios',
      'macos',
      'linux',
      'web',
      'windows',
    ])
      if (platforms[platform] == true) ...[
        platformWorkflowPolicy(platform).doctorCommand(strict: true),
        _packageRegressionCommand(platform, packageName, traceDir),
      ],
    'fluoh package status --package $packageName',
    _reportCheckCommand,
    'fluoh package handoff --package $packageName --json',
    'fluoh package check --package $packageName --report <report-path> --json',
  ];
}

List<String> _mobileDriveCommands(
  Map<String, bool> platforms, {
  String? packageName,
  required String traceDir,
}) {
  final commands = <String>[];
  for (final platform in const ['ohos', 'android', 'ios']) {
    if (!_shouldDriveMobilePlatform(platform, platforms)) {
      continue;
    }
    commands.add(
      'fluoh drive $platform'
      '${packageName == null ? '' : ' --package $packageName'}'
      ' --json --trace-dir $traceDir',
    );
  }
  return commands;
}

bool _shouldDriveMobilePlatform(String platform, Map<String, bool> platforms) {
  if (platform == 'ohos') {
    return true;
  }
  if (platform == 'android') {
    return platforms['android'] == true;
  }
  if (platform == 'ios') {
    return platforms['ios'] == true && Platform.isMacOS;
  }
  return false;
}

List<Map<String, Object?>> _ohosAdaptationQueue({
  String? packageName,
  required String traceDir,
}) {
  final policy = platformWorkflowPolicy('ohos');
  return [
    _queueItem(
      phase: policy.platform,
      command: policy.doctorCommand(project: true, strict: true),
      mutating: false,
      evidence: '${policy.label} toolchain diagnostics',
    ),
    _queueItem(
      phase: policy.platform,
      command: policy.buildCommand(
        packageName: packageName,
        autoSign: true,
        traceDir: traceDir,
      ),
      mutating: true,
      evidence: 'signed HAP build JSON',
    ),
    _queueItem(
      phase: policy.platform,
      command: policy.devicesCommand(json: true),
      mutating: false,
      evidence: 'connected ${policy.label} target inventory',
    ),
    _queueItem(
      phase: policy.platform,
      command: policy.emulatorsCommand(json: true),
      mutating: false,
      evidence: 'local ${policy.label} emulator inventory',
    ),
    _queueItem(
      phase: policy.platform,
      command: policy.runCommand(
        packageName: packageName,
        startEmulator: true,
        traceDir: traceDir,
      ),
      mutating: true,
      evidence: 'install, launch, hilog, and runtime findings',
    ),
  ];
}

String _regressionCommand(String platform, String traceDir) {
  return platformWorkflowPolicy(platform).regressionCommand(traceDir: traceDir);
}

String _packageRegressionCommand(
  String platform,
  String packageName,
  String traceDir,
) {
  return platformWorkflowPolicy(
    platform,
  ).regressionCommand(packageName: packageName, traceDir: traceDir);
}

String _scopePlaceholder() => '<scope>';

String _scopeSlug(String value, {required String fallback}) {
  if (value.startsWith('<') && value.endsWith('>')) {
    return fallback;
  }
  final normalized = value
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^[-._]+|[-._]+$'), '');
  return normalized.isEmpty ? fallback : normalized;
}

Map<String, bool> _packageExamplePlatforms(Directory exampleDirectory) {
  return {
    for (final platform in const [
      'ohos',
      'android',
      'ios',
      'macos',
      'linux',
      'web',
      'windows',
    ])
      platform: Directory('${exampleDirectory.path}/$platform').existsSync(),
  };
}

Future<String?> _currentBranchOrNull(Directory root) async {
  final result = await runGit(
    ['branch', '--show-current'],
    workingDirectory: root,
    allowFailure: true,
  );
  if (result.exitCode != 0) {
    return null;
  }
  final branch = result.stdout.toString().trim();
  return branch.isEmpty ? null : branch;
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

bool _isFlutterProject(String content) {
  if (content.trim().isEmpty) {
    return false;
  }
  try {
    final yaml = parseYamlMap(content, label: 'pubspec.yaml');
    final dependencies = yaml['dependencies'];
    return dependencies is Map<String, Object?> &&
        dependencies['flutter'] is Map<String, Object?> &&
        (dependencies['flutter'] as Map<String, Object?>)['sdk'] == 'flutter';
  } on Object {
    return false;
  }
}

String? _topLevelString(String content, String key) {
  try {
    final yaml = parseYamlMap(content, label: 'pubspec.yaml');
    final value = yaml[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  } on Object {
    return null;
  }
}
