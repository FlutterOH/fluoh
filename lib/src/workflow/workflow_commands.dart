import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../cli/argument_validation.dart';
import '../cli/fluoh_command_runner.dart';
import '../cli/machine_output.dart';
import '../cli/terminal_output.dart';
import '../cli/trace_output.dart';
import '../context/fluoh_environment.dart';
import '../platform/ohos/build_profile_signing.dart';
import '../platform/ohos/debug_signer.dart';
import '../platform/ohos/device_runner.dart';
import '../platform/ohos/resource_layout.dart';
import '../package/manifest/package_manifest.dart';
import '../package/flutter_example_runner.dart';
import '../package/git/package_git.dart';
import '../package/package_workflow_runner.dart';
import '../package/package_examples.dart';
import '../schema/yaml_utils.dart';
import '../sdk/flutter_runner.dart';
import 'automation_scenario.dart';
import 'workflow_result.dart';

/// Runs baseline verification for a project or package target.
class VerifyCommand extends FluohCommand<int> {
  /// Creates the verify command.
  VerifyCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _stderr = stderr,
       _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr) {
    _addPackageSelectionOptions(argParser);
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print the verification result as JSON.',
    );
    _addTraceOptions(argParser);
  }

  /// Runtime environment for the selected project or package repository.
  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  final TerminalOutput _output;

  @override
  String get name => 'verify';

  @override
  String get description => 'Run pub get, analysis, and existing tests.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    _validatePackageSelection(argResults!, usageException);
    final json = argResults!.flag('json');
    final output = _outputFor(json, _output);
    final stdout = json ? (_) {} : _stdout;
    final stderr = json ? (_) {} : _stderr;
    final beforeStatus = await _gitStatusSnapshot(environment.workingDirectory);
    final results = await _runPackageOrProject(
      environment: environment,
      packageName: _trimmedOption(argResults!, 'package'),
      all: argResults!.flag('all'),
      output: output,
      stdout: stdout,
      stderr: stderr,
      usage: usage,
      invocationForPackage: (package) =>
          _PackageWorkflowInvocation(phase: 'baseline'),
    );
    final workingTreeChanges = await _workingTreeChangesAfterWorkflow(
      environment.workingDirectory,
      beforeStatus,
    );
    final traceResult = await _printWorkflowJson(
      json: json,
      stdout: _stdout,
      environment: environment,
      command: 'verify',
      arguments: argResults!.arguments,
      results: results,
      traceOptions: _traceOptionsFrom(argResults!),
      extraFields: workingTreeChanges.toJson(),
    );
    final exitCode = _firstFailure(results);
    if (!json) {
      _writeTraceStatus(output, traceResult);
      if (workingTreeChanges.shouldWarn) {
        output.warning('Verification left working tree changes.');
        if (workingTreeChanges.generatedFilesChanged) {
          output.next('Review generated file changes before committing');
        }
        output.next('Run git status --short');
      }
    }
    if (exitCode == 0 && !json) {
      output.success(_passedMessage('Verification', results.length));
    }
    return exitCode;
  }
}

/// Builds a project or package example for a selected platform.
class BuildCommand extends FluohCommand<int> {
  /// Creates the build command.
  BuildCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _stderr = stderr,
       _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr) {
    argParser
      ..addOption(
        'platform',
        allowed: const [
          'ohos',
          'android',
          'ios',
          'macos',
          'linux',
          'web',
          'windows',
        ],
        mandatory: true,
        help: 'Platform to build.',
      )
      ..addFlag('debug', defaultsTo: true, help: 'Build a debug artifact.')
      ..addFlag(
        'auto-sign',
        negatable: false,
        help:
            'Generate temporary OHOS debug signing when building a project or package example.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the build result as JSON.',
      );
    _addTraceOptions(argParser);
    _addPackageSelectionOptions(argParser);
  }

  /// Runtime environment for the selected project or package repository.
  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  final TerminalOutput _output;

  @override
  String get name => 'build';

  @override
  String get description => 'Build a FlutterOH project or package example.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    _validatePackageSelection(argResults!, usageException);
    final platform = _platformFromBuildOption(argResults!.option('platform'));
    if (argResults!.flag('auto-sign') && platform != 'ohos') {
      usageException('Use --auto-sign only with --platform ohos.');
    }
    final json = argResults!.flag('json');
    final output = _outputFor(json, _output);
    final stdout = json ? (_) {} : _stdout;
    final stderr = json ? (_) {} : _stderr;
    final invocation = _PackageWorkflowInvocation(
      phase: '$platform-build',
      buildExampleTarget: _buildTargetForPlatform(platform),
      debug: argResults!.flag('debug'),
      autoSign: platform == 'ohos' && argResults!.flag('auto-sign'),
    );
    final results = await _runPackageOrProject(
      environment: environment,
      packageName: _trimmedOption(argResults!, 'package'),
      all: argResults!.flag('all'),
      output: output,
      stdout: stdout,
      stderr: stderr,
      usage: usage,
      invocationForPackage: (_) => invocation,
      projectInvocation: _ProjectWorkflowInvocation.build(
        platform: platform,
        debug: argResults!.flag('debug'),
        autoSign: platform == 'ohos' && argResults!.flag('auto-sign'),
      ),
    );
    final traceResult = await _printWorkflowJson(
      json: json,
      stdout: _stdout,
      environment: environment,
      command: 'build',
      arguments: argResults!.arguments,
      results: results,
      traceOptions: _traceOptionsFrom(argResults!),
    );
    final exitCode = _firstFailure(results);
    if (!json) {
      _writeTraceStatus(output, traceResult);
    }
    if (exitCode == 0 && !json) {
      output.success(_passedMessage('Build', results.length));
    }
    return exitCode;
  }
}

/// Builds, installs, launches, and diagnoses a target app.
class RunCommand extends FluohCommand<int> {
  /// Creates the run command.
  RunCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _stderr = stderr,
       _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr) {
    argParser
      ..addOption(
        'platform',
        allowed: const [
          'ohos',
          'android',
          'ios',
          'macos',
          'linux',
          'web',
          'windows',
        ],
        mandatory: true,
        help: 'Platform to run.',
      )
      ..addOption('device', valueHelp: 'id', help: 'Connected device id.')
      ..addOption(
        'emulator',
        valueHelp: 'name',
        help: 'Local emulator or simulator to start before running.',
      )
      ..addFlag(
        'auto-emulator',
        negatable: false,
        help:
            'Prefer a local emulator or simulator, falling back to a connected device only when none is available.',
      )
      ..addOption(
        'device-timeout',
        valueHelp: 'seconds',
        defaultsTo: '90',
        help: 'Seconds to wait for a target after starting an emulator.',
      )
      ..addOption(
        'log-duration',
        valueHelp: 'seconds',
        defaultsTo: '8',
        help: 'Seconds of run output or OHOS hilog to collect.',
      )
      ..addOption(
        'session-file',
        valueHelp: 'path',
        help:
            'Write a live Flutter debug session JSON file for Android, iOS, macOS, Linux, Web, or Windows runs.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the run result as JSON.',
      );
    _addTraceOptions(argParser);
    _addPackageSelectionOptions(argParser);
  }

  /// Runtime environment for the selected project or package repository.
  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  final TerminalOutput _output;

  @override
  String get name => 'run';

  @override
  String get description => 'Build, install, launch, and diagnose an app.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    _validatePackageSelection(argResults!, usageException);
    if (_trimmedOption(argResults!, 'device') != null &&
        _trimmedOption(argResults!, 'emulator') != null) {
      usageException('Use only one of --device or --emulator.');
    }
    if (_trimmedOption(argResults!, 'device') != null &&
        argResults!.flag('auto-emulator')) {
      usageException('Use only one of --device or --auto-emulator.');
    }
    if (_trimmedOption(argResults!, 'emulator') != null &&
        argResults!.flag('auto-emulator')) {
      usageException('Use only one of --emulator or --auto-emulator.');
    }
    final deviceTimeout = _durationOption('device-timeout');
    final logDuration = _durationOption('log-duration');
    final platform = _platformFromBuildOption(argResults!.option('platform'));
    final deviceId = _trimmedOption(argResults!, 'device');
    final emulatorName = _trimmedOption(argResults!, 'emulator');
    final autoEmulator = argResults!.flag('auto-emulator');
    final sessionFilePath = _trimmedOption(argResults!, 'session-file');
    if (sessionFilePath != null && platform == 'ohos') {
      usageException(
        'Use --session-file only with Android, iOS, macOS, Linux, Web, or Windows runs.',
      );
    }
    if (sessionFilePath != null && argResults!.flag('all')) {
      usageException('Use --session-file with one run target at a time.');
    }
    final sessionFile = sessionFilePath == null
        ? null
        : _resolveOutputFile(environment.workingDirectory, sessionFilePath);
    final json = argResults!.flag('json');
    final output = _outputFor(json, _output);
    final stdout = json ? (_) {} : _stdout;
    final stderr = json ? (_) {} : _stderr;
    final startEmulator = autoEmulator || emulatorName != null;
    final invocation = _PackageWorkflowInvocation(
      phase: '$platform-run',
      buildExampleTarget: _buildTargetForPlatform(platform),
      debug: true,
      buildExampleForSimulator:
          platform == 'ios' && deviceId == null && startEmulator,
      autoSign: platform == 'ohos',
      runExample: true,
      deviceId: deviceId,
      startEmulator: startEmulator,
      emulatorName: emulatorName,
      sessionFile: sessionFile,
    );
    final results = await _runPackageOrProject(
      environment: environment,
      packageName: _trimmedOption(argResults!, 'package'),
      all: argResults!.flag('all'),
      output: output,
      stdout: stdout,
      stderr: stderr,
      usage: usage,
      invocationForPackage: (_) => invocation,
      projectInvocation: _ProjectWorkflowInvocation.run(
        platform: platform,
        deviceId: deviceId,
        startEmulator: startEmulator,
        emulatorName: emulatorName,
        sessionFile: sessionFile,
      ),
      deviceTimeout: deviceTimeout,
      logDuration: logDuration,
    );
    final traceResult = await _printWorkflowJson(
      json: json,
      stdout: _stdout,
      environment: environment,
      command: 'run',
      arguments: argResults!.arguments,
      results: results,
      traceOptions: _traceOptionsFrom(argResults!),
    );
    final exitCode = _firstFailure(results);
    if (!json) {
      _writeTraceStatus(output, traceResult);
    }
    if (exitCode == 0 && !json) {
      output.success(_passedMessage('Run', results.length));
    }
    return exitCode;
  }

  Duration _durationOption(String name) {
    final seconds = int.tryParse(argResults!.option(name) ?? '');
    if (seconds == null || seconds < 0) {
      usageException('Use a non-negative integer for --$name.');
    }
    return Duration(seconds: seconds);
  }
}

/// Runs AI-oriented mobile automation for project and package targets.
class AutomateCommand extends FluohCommand<int> {
  /// Creates the automate command.
  AutomateCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _stderr = stderr,
       _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr) {
    argParser
      ..addOption(
        'platform',
        allowed: const ['all', 'ohos', 'android', 'ios'],
        defaultsTo: 'all',
        help: 'Mobile platform automation target.',
      )
      ..addOption('device', valueHelp: 'id', help: 'Connected device id.')
      ..addOption(
        'emulator',
        valueHelp: 'name',
        help: 'Local emulator or simulator to start before running.',
      )
      ..addFlag(
        'auto-emulator',
        defaultsTo: true,
        help:
            'Prefer local emulators and simulators, falling back to connected devices only when none is available.',
      )
      ..addOption(
        'device-timeout',
        valueHelp: 'seconds',
        defaultsTo: '90',
        help: 'Seconds to wait for a target after starting an emulator.',
      )
      ..addOption(
        'log-duration',
        valueHelp: 'seconds',
        defaultsTo: '8',
        help: 'Seconds of run output or OHOS hilog to collect.',
      )
      ..addOption(
        'session-dir',
        valueHelp: 'path',
        defaultsTo: '.fluoh/run-sessions/automation',
        help: 'Directory for Android and iOS flutterRunSession files.',
      )
      ..addMultiOption(
        'scenario',
        valueHelp: 'path',
        help:
            'Automation scenario YAML, JSON, or Markdown file to execute after the app launches.',
      )
      ..addFlag(
        'dry-run',
        abbr: 'n',
        negatable: false,
        help: 'Print the automation plan without launching targets.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the automation result as JSON.',
      );
    _addTraceOptions(argParser);
    _addPackageSelectionOptions(argParser);
  }

  /// Runtime environment for the selected project or package repository.
  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  final TerminalOutput _output;

  @override
  String get name => 'automate';

  @override
  String get description =>
      'Run mobile app automation scenarios and evidence checks.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    _validatePackageSelection(argResults!, usageException);
    final platforms = _automationPlatformsFromOption(
      argResults!.option('platform'),
    );
    final deviceId = _trimmedOption(argResults!, 'device');
    final emulatorName = _trimmedOption(argResults!, 'emulator');
    final autoEmulator = deviceId == null && argResults!.flag('auto-emulator');
    if (deviceId != null && emulatorName != null) {
      usageException('Use only one of --device or --emulator.');
    }
    if (deviceId != null && platforms.length != 1) {
      usageException('Use --device with one --platform value.');
    }
    if (emulatorName != null && platforms.length != 1) {
      usageException('Use --emulator with one --platform value.');
    }
    final deviceTimeout = _durationOption('device-timeout');
    final logDuration = _durationOption('log-duration');
    final packageName = _trimmedOption(argResults!, 'package');
    final all = argResults!.flag('all');
    final sessionDirectory = _resolveOutputDirectory(
      environment.workingDirectory,
      argResults!.option('session-dir') ?? '.fluoh/run-sessions/automation',
    );
    final scenarios = await _readAutomationScenarios(
      argResults!.multiOption('scenario'),
      workingDirectory: environment.workingDirectory,
      usageException: usageException,
    );
    _validateAutomationScenarios(scenarios, platforms, usageException);
    final inventory = await _automationInventory(
      environment: environment,
      packageName: packageName,
      all: all,
    );
    final plan = _automationPlan(
      platforms: platforms,
      packageName: packageName,
      all: all,
      deviceId: deviceId,
      emulatorName: emulatorName,
      autoEmulator: autoEmulator,
      deviceTimeout: deviceTimeout,
      logDuration: logDuration,
      sessionDirectory: sessionDirectory,
      traceOptions: _traceOptionsFrom(argResults!),
      scenarios: scenarios,
      inventory: inventory,
    );
    final json = argResults!.flag('json');
    if (argResults!.flag('dry-run')) {
      if (json) {
        writeMachineOutput(
          _stdout,
          command: 'automate',
          ok: true,
          exitCode: 0,
          fields: {
            'automation': plan.toJson(dryRun: true),
            'targets': const [],
          },
        );
      } else {
        _printAutomationPlan(plan, _output);
      }
      return 0;
    }

    final output = _outputFor(json, _output);
    final stdout = json ? (_) {} : _stdout;
    final stderr = json ? (_) {} : _stderr;
    final results = <WorkflowTargetResult>[];
    for (final platform in platforms) {
      output.step('Automating ${_platformLabel(platform)} run');
      final platformResults = await _runPackageOrProject(
        environment: environment,
        packageName: packageName,
        all: all,
        output: output,
        stdout: stdout,
        stderr: stderr,
        usage: usage,
        invocationForPackage: (package) => _automationPackageInvocation(
          platform: platform,
          packageName: package.name,
          deviceId: deviceId,
          emulatorName: emulatorName,
          autoEmulator: autoEmulator,
          sessionDirectory: sessionDirectory,
        ),
        projectInvocation: _automationProjectInvocation(
          platform: platform,
          deviceId: deviceId,
          emulatorName: emulatorName,
          autoEmulator: autoEmulator,
          sessionDirectory: sessionDirectory,
        ),
        deviceTimeout: deviceTimeout,
        logDuration: logDuration,
      );
      results.addAll(
        await _runAutomationScenariosForPlatform(
          platformResults,
          scenarios: _automationScenariosForPlatform(scenarios, platform),
          platform: platform,
          environment: environment,
          output: output,
          packageName: packageName,
          all: all,
          deviceId: deviceId,
          emulatorName: emulatorName,
          autoEmulator: autoEmulator,
          sessionDirectory: sessionDirectory,
          traceOptions: _traceOptionsFrom(argResults!),
        ),
      );
    }
    final traceResult = await _printWorkflowJson(
      json: json,
      stdout: _stdout,
      environment: environment,
      command: 'automate',
      arguments: argResults!.arguments,
      results: results,
      traceOptions: _traceOptionsFrom(argResults!),
      extraFields: {'automation': plan.toJson(results: results)},
    );
    final exitCode = _firstFailure(results);
    if (!json) {
      _writeTraceStatus(output, traceResult);
      if (exitCode == 0) {
        output.success(_passedMessage('Automation', results.length));
      }
    }
    return exitCode;
  }

  Duration _durationOption(String name) {
    final seconds = int.tryParse(argResults!.option(name) ?? '');
    if (seconds == null || seconds < 0) {
      usageException('Use a non-negative integer for --$name.');
    }
    return Duration(seconds: seconds);
  }
}

File _resolveOutputFile(Directory workingDirectory, String path) {
  final file = File(path);
  if (file.isAbsolute) {
    return file;
  }
  return File('${workingDirectory.path}/$path');
}

Directory _resolveOutputDirectory(Directory workingDirectory, String path) {
  final directory = Directory(path);
  if (directory.isAbsolute) {
    return directory;
  }
  return Directory('${workingDirectory.path}/$path');
}

Future<List<AutomationScenario>> _readAutomationScenarios(
  List<String> paths, {
  required Directory workingDirectory,
  required UsageError usageException,
}) async {
  final scenarios = <AutomationScenario>[];
  for (final path in paths) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      usageException('Use a non-empty path for --scenario.');
    }
    try {
      scenarios.add(
        await readAutomationScenario(
          File(trimmed),
          workingDirectory: workingDirectory,
        ),
      );
    } on FileSystemException catch (error) {
      usageException('Could not read scenario $trimmed: ${error.message}');
    } on FormatException catch (error) {
      usageException(error.message);
    }
  }
  return scenarios;
}

void _validateAutomationScenarios(
  List<AutomationScenario> scenarios,
  List<String> platforms,
  UsageError usageException,
) {
  const supportedPlatforms = {'ohos', 'android', 'ios'};
  for (final scenario in scenarios) {
    if (!supportedPlatforms.contains(scenario.platform)) {
      usageException(
        'Scenario ${scenario.path.path} uses unsupported platform ${scenario.platform}.',
      );
    }
    if (!platforms.contains(scenario.platform)) {
      usageException(
        'Scenario ${scenario.path.path} targets ${scenario.platform}, which is not included by --platform.',
      );
    }
  }
}

List<String> _automationPlatformsFromOption(String? value) {
  return switch (value) {
    'all' || null => const ['ohos', 'android', 'ios'],
    'ohos' || 'android' || 'ios' => [value],
    _ => throw ArgumentError.value(value, 'platform', 'Unsupported platform.'),
  };
}

_PackageWorkflowInvocation _automationPackageInvocation({
  required String platform,
  required String packageName,
  required String? deviceId,
  required String? emulatorName,
  required bool autoEmulator,
  required Directory sessionDirectory,
}) {
  final startEmulator = _automationStartsEmulator(
    platform: platform,
    deviceId: deviceId,
    emulatorName: emulatorName,
    autoEmulator: autoEmulator,
  );
  return _PackageWorkflowInvocation(
    phase: '$platform-run',
    buildExampleTarget: _buildTargetForPlatform(platform),
    debug: true,
    buildExampleForSimulator:
        platform == 'ios' && deviceId == null && startEmulator,
    autoSign: platform == 'ohos',
    runExample: true,
    deviceId: deviceId,
    startEmulator: startEmulator,
    emulatorName: emulatorName,
    sessionFile: _automationSessionFile(
      platform: platform,
      targetName: packageName,
      sessionDirectory: sessionDirectory,
    ),
  );
}

_ProjectWorkflowInvocation _automationProjectInvocation({
  required String platform,
  required String? deviceId,
  required String? emulatorName,
  required bool autoEmulator,
  required Directory sessionDirectory,
}) {
  return _ProjectWorkflowInvocation.run(
    platform: platform,
    deviceId: deviceId,
    startEmulator: _automationStartsEmulator(
      platform: platform,
      deviceId: deviceId,
      emulatorName: emulatorName,
      autoEmulator: autoEmulator,
    ),
    emulatorName: emulatorName,
    sessionFile: _automationSessionFile(
      platform: platform,
      targetName: 'current',
      sessionDirectory: sessionDirectory,
    ),
  );
}

List<AutomationScenario> _automationScenariosForPlatform(
  List<AutomationScenario> scenarios,
  String platform,
) {
  return [
    for (final scenario in scenarios)
      if (scenario.platform == platform) scenario,
  ];
}

Future<List<WorkflowTargetResult>> _runAutomationScenariosForPlatform(
  List<WorkflowTargetResult> results, {
  required List<AutomationScenario> scenarios,
  required String platform,
  required FluohEnvironment environment,
  required TerminalOutput output,
  required String? packageName,
  required bool all,
  required String? deviceId,
  required String? emulatorName,
  required bool autoEmulator,
  required Directory sessionDirectory,
  required TraceOptions traceOptions,
}) async {
  if (scenarios.isEmpty) {
    return results;
  }
  final updated = <WorkflowTargetResult>[];
  for (final target in results) {
    var current = target;
    for (final scenario in scenarios) {
      output.step(
        'Running ${_platformLabel(platform)} scenario ${scenario.name}',
      );
      final nextCommand = _automationScenarioNextCommand(
        scenario: scenario,
        platform: platform,
        targetKind: target.targetKind,
        packageName: packageName,
        targetName: target.targetName,
        all: all,
        deviceId: deviceId,
        emulatorName: emulatorName,
        autoEmulator: autoEmulator,
        sessionDirectory: sessionDirectory,
        traceOptions: traceOptions,
      );
      final scenarioResult = await runAutomationScenario(
        scenario: scenario,
        target: current,
        environment: environment,
        nextCommand: nextCommand,
      );
      current = _appendAutomationScenarioResult(
        current,
        scenarioResult,
        environment: environment,
        command: nextCommand,
      );
      if (!current.passed) {
        break;
      }
    }
    updated.add(current);
  }
  return updated;
}

WorkflowTargetResult _appendAutomationScenarioResult(
  WorkflowTargetResult target,
  AutomationScenarioRunResult result, {
  required FluohEnvironment environment,
  required String command,
}) {
  final steps = [
    ...target.steps,
    _automationScenarioStep(result, environment: environment, command: command),
  ];
  final exitCode = target.exitCode != 0 ? target.exitCode : result.exitCode;
  if (target.targetKind == 'package') {
    return WorkflowTargetResult.package(
      packageName: target.targetName,
      exitCode: exitCode,
      steps: steps,
      preset: target.preset,
      phase: target.phase,
    );
  }
  return WorkflowTargetResult.project(
    projectName: target.targetName,
    exitCode: exitCode,
    steps: steps,
    preset: target.preset,
    phase: target.phase,
  );
}

WorkflowStepResult _automationScenarioStep(
  AutomationScenarioRunResult result, {
  required FluohEnvironment environment,
  required String command,
}) {
  return WorkflowStepResult(
    name:
        'automation-scenario-${result.scenario.platform}-${_automationPathSlug(result.scenario.name)}',
    path: _automationScenarioStepPath(
      environment.workingDirectory,
      result.scenario.path.parent,
    ),
    command: command,
    status: result.status,
    exitCode: result.exitCode,
    reason: result.reason,
    details: result.toJson(),
    diagnostics: [if (result.diagnostic != null) result.diagnostic!],
  );
}

String _automationScenarioStepPath(Directory root, Directory directory) {
  final rootPath = root.absolute.path;
  final directoryPath = directory.absolute.path;
  if (directoryPath == rootPath) {
    return '.';
  }
  final prefix = '$rootPath${Platform.pathSeparator}';
  if (directoryPath.startsWith(prefix)) {
    return directoryPath.substring(prefix.length);
  }
  return directory.path;
}

String _automationScenarioNextCommand({
  required AutomationScenario scenario,
  required String platform,
  required String targetKind,
  required String? packageName,
  required String targetName,
  required bool all,
  required String? deviceId,
  required String? emulatorName,
  required bool autoEmulator,
  required Directory sessionDirectory,
  required TraceOptions traceOptions,
}) {
  final parts = [
    'fluoh',
    'automate',
    '--platform',
    platform,
    if (packageName != null) ...[
      '--package',
      packageName,
    ] else if (all)
      '--all'
    else if (targetKind == 'package') ...[
      '--package',
      targetName,
    ],
    if (deviceId != null) ...['--device', deviceId],
    if (emulatorName != null) ...['--emulator', emulatorName],
    if (deviceId == null && emulatorName == null)
      autoEmulator ? '--auto-emulator' : '--no-auto-emulator',
    '--session-dir',
    sessionDirectory.path,
    '--scenario',
    scenario.path.path,
    if (traceOptions.enabled && traceOptions.directory == null) '--trace',
    if (traceOptions.directory != null) ...[
      '--trace-dir',
      traceOptions.directory!.path,
    ],
    '--json',
  ];
  return parts.map(_workflowShellQuote).join(' ');
}

bool _automationStartsEmulator({
  required String platform,
  required String? deviceId,
  required String? emulatorName,
  required bool autoEmulator,
}) {
  if (deviceId != null) {
    return false;
  }
  if (emulatorName != null) {
    return true;
  }
  return autoEmulator && !_isDesktopRunPlatform(platform);
}

File? _automationSessionFile({
  required String platform,
  required String targetName,
  required Directory sessionDirectory,
}) {
  if (platform != 'android' && platform != 'ios') {
    return null;
  }
  return File(
    '${sessionDirectory.path}/${_automationPathSlug(targetName)}-$platform-session.json',
  );
}

String _automationPathSlug(String value) {
  final normalized = value
      .trim()
      .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^[-._]+|[-._]+$'), '');
  return normalized.isEmpty ? 'target' : normalized;
}

_AutomationPlan _automationPlan({
  required List<String> platforms,
  required String? packageName,
  required bool all,
  required String? deviceId,
  required String? emulatorName,
  required bool autoEmulator,
  required Duration deviceTimeout,
  required Duration logDuration,
  required Directory sessionDirectory,
  required TraceOptions traceOptions,
  required List<AutomationScenario> scenarios,
  required _AutomationInventory inventory,
}) {
  return _AutomationPlan(
    platforms: platforms,
    packageName: packageName,
    all: all,
    deviceId: deviceId,
    emulatorName: emulatorName,
    autoEmulator: autoEmulator,
    deviceTimeout: deviceTimeout,
    logDuration: logDuration,
    sessionDirectory: sessionDirectory,
    traceOptions: traceOptions,
    scenarios: scenarios,
    inventory: inventory,
  );
}

class _AutomationPlan {
  const _AutomationPlan({
    required this.platforms,
    required this.packageName,
    required this.all,
    required this.deviceId,
    required this.emulatorName,
    required this.autoEmulator,
    required this.deviceTimeout,
    required this.logDuration,
    required this.sessionDirectory,
    required this.traceOptions,
    required this.scenarios,
    required this.inventory,
  });

  final List<String> platforms;
  final String? packageName;
  final bool all;
  final String? deviceId;
  final String? emulatorName;
  final bool autoEmulator;
  final Duration deviceTimeout;
  final Duration logDuration;
  final Directory sessionDirectory;
  final TraceOptions traceOptions;
  final List<AutomationScenario> scenarios;
  final _AutomationInventory inventory;

  Map<String, Object?> toJson({
    List<WorkflowTargetResult>? results,
    bool dryRun = false,
  }) {
    final coveragePolicy = _AutomationCoveragePolicy(
      scenarios: scenarios,
      inventory: inventory,
      platforms: platforms,
    ).toJson();
    final checks = [
      for (final platform in platforms)
        _AutomationCheckPlan(
          platform: platform,
          packageName: packageName,
          all: all,
          deviceId: deviceId,
          emulatorName: emulatorName,
          autoEmulator: autoEmulator,
          sessionDirectory: sessionDirectory,
          traceOptions: traceOptions,
        ).toJson(),
    ];
    final executionResults = results ?? const <WorkflowTargetResult>[];
    final rerunCommand = _automateCommand(dryRun: dryRun);
    Map<String, Object?>? deliveryRecommendation;
    List<Map<String, Object?>>? repairQueue;
    if (results != null || dryRun) {
      deliveryRecommendation = _deliveryRecommendation(
        executionResults,
        coveragePolicy,
        dryRun: dryRun,
      );
      repairQueue = _repairQueue(
        executionResults,
        coveragePolicy,
        checks: checks,
        dryRun: dryRun,
      );
    }
    return {
      'schema': 1,
      'kind': 'fluoh.mobileAutomation',
      'platforms': platforms,
      'targetSelection': {
        if (packageName != null) 'package': packageName,
        if (all) 'all': true,
      },
      'targeting': {
        'autoEmulator': autoEmulator,
        if (deviceId != null) 'device': deviceId,
        if (emulatorName != null) 'emulator': emulatorName,
      },
      'sessionDirectory': sessionDirectory.path,
      if (scenarios.isNotEmpty)
        'scenarios': scenarios.map((scenario) => scenario.toJson()).toList(),
      'trace': {
        'enabled': traceOptions.enabled || traceOptions.directory != null,
        if (traceOptions.directory != null)
          'directory': traceOptions.directory!.path,
      },
      'coveragePolicy': coveragePolicy,
      'rerunCommand': rerunCommand,
      if (deliveryRecommendation != null && repairQueue != null) ...{
        'deliveryRecommendation': deliveryRecommendation,
        'repairQueue': repairQueue,
        'repairPlan': _repairPlan(
          deliveryRecommendation,
          repairQueue,
          rerunCommand: rerunCommand,
        ),
      },
      'inspiredBy': {
        'name': 'callstack/agent-device',
        'url': 'https://github.com/callstack/agent-device',
        'model':
            'boot or select target, launch the app, keep a session, collect compact evidence, then replay or debug from the recorded state',
      },
      'checks': checks,
    };
  }

  String _automateCommand({required bool dryRun}) {
    final platform = platforms.length == 3 ? 'all' : platforms.single;
    final parts = [
      'fluoh',
      'automate',
      '--platform',
      platform,
      if (packageName != null) ...['--package', packageName!],
      if (all) '--all',
      if (deviceId != null) ...['--device', deviceId!],
      if (emulatorName != null) ...['--emulator', emulatorName!],
      if (deviceId == null && emulatorName == null)
        autoEmulator ? '--auto-emulator' : '--no-auto-emulator',
      '--device-timeout',
      deviceTimeout.inSeconds.toString(),
      '--log-duration',
      logDuration.inSeconds.toString(),
      '--session-dir',
      sessionDirectory.path,
      for (final scenario in scenarios) ...['--scenario', scenario.path.path],
      if (traceOptions.enabled && traceOptions.directory == null) '--trace',
      if (traceOptions.directory != null) ...[
        '--trace-dir',
        traceOptions.directory!.path,
      ],
      if (dryRun) '--dry-run',
      '--json',
    ];
    return parts.map(_workflowShellQuote).join(' ');
  }

  Map<String, Object?> _repairPlan(
    Map<String, Object?> deliveryRecommendation,
    List<Map<String, Object?>> repairQueue, {
    required String rerunCommand,
  }) {
    final firstItem = repairQueue.isEmpty ? null : repairQueue.first;
    return {
      'schema': 1,
      'status': deliveryRecommendation['status'],
      'recommendation': deliveryRecommendation['recommendation'],
      'ready': deliveryRecommendation['ready'],
      'queueLength': repairQueue.length,
      'nextStep': firstItem == null
          ? {
              'kind': 'none',
              'action':
                  'No repair item remains. Prepare the final report review with the recorded automation evidence.',
            }
          : _repairPlanNextStep(firstItem, rerunCommand: rerunCommand),
    };
  }

  Map<String, Object?> _repairPlanNextStep(
    Map<String, Object?> item, {
    required String rerunCommand,
  }) {
    final type = item['type'] as String?;
    final nextAction = item['nextAction'];
    if (nextAction is Map<String, Object?>) {
      return {
        'kind': nextAction['kind'] ?? 'applyNextAction',
        'sourceType': type,
        'action': _repairPlanAction(type),
        if (item['gate'] != null) 'gate': item['gate'],
        if (item['status'] != null) 'status': item['status'],
        if (item['platform'] != null) 'platform': item['platform'],
        if (item['category'] != null) 'category': item['category'],
        if (item['item'] != null) 'item': item['item'],
        if (item['permission'] != null) 'permission': item['permission'],
        if (item['coverageItem'] != null) 'coverageItem': item['coverageItem'],
        'nextAction': nextAction,
        'doneWhen': _repairPlanDoneWhen(type, item),
        'validation': _repairPlanValidation(
          type,
          item,
          rerunCommand: rerunCommand,
        ),
      };
    }
    if (type == 'execution') {
      return {
        'kind': 'executeAutomation',
        'sourceType': type,
        'action':
            'Run the planned platform automation commands and keep the resulting JSON evidence before reporting ready.',
        if (item['nextCommands'] != null) 'nextCommands': item['nextCommands'],
        'doneWhen': _repairPlanDoneWhen(type, item),
        'validation': _repairPlanValidation(
          type,
          item,
          rerunCommand: rerunCommand,
        ),
      };
    }
    if (type == 'diagnostic') {
      return {
        'kind': item['nextCommand'] == null
            ? 'fixDiagnostic'
            : 'fixDiagnosticAndRerun',
        'sourceType': type,
        'action':
            'Fix the failed target or scenario diagnostic, then rerun the printed nextCommand.',
        if (item['target'] != null) 'target': item['target'],
        if (item['step'] != null) 'step': item['step'],
        if (item['code'] != null) 'code': item['code'],
        if (item['message'] != null) 'message': item['message'],
        if (item['repairHints'] != null) 'repairHints': item['repairHints'],
        if (item['nextCommand'] != null) 'nextCommand': item['nextCommand'],
        'doneWhen': _repairPlanDoneWhen(type, item),
        'validation': _repairPlanValidation(
          type,
          item,
          rerunCommand: rerunCommand,
        ),
      };
    }
    if (type == 'coverageBlocked') {
      return {
        'kind': 'resolveBlockedCoverage',
        'sourceType': type,
        'action':
            'Decide whether the blocked coverage row is an environment blocker or maintainer decision, then record that evidence in the report.',
        if (item['platform'] != null) 'platform': item['platform'],
        if (item['scenario'] != null) 'scenario': item['scenario'],
        if (item['path'] != null) 'path': item['path'],
        if (item['coverage'] != null) 'coverage': item['coverage'],
        'doneWhen': _repairPlanDoneWhen(type, item),
        'validation': _repairPlanValidation(
          type,
          item,
          rerunCommand: rerunCommand,
        ),
      };
    }
    if (type == 'coverage') {
      return {
        'kind': 'completeCoverageGate',
        'sourceType': type,
        'action':
            'Complete the reported coverage gate before executing automation or reporting ready.',
        if (item['gate'] != null) 'gate': item['gate'],
        if (item['status'] != null) 'status': item['status'],
        if (item['repair'] != null) 'repair': item['repair'],
        'doneWhen': _repairPlanDoneWhen(type, item),
        'validation': _repairPlanValidation(
          type,
          item,
          rerunCommand: rerunCommand,
        ),
      };
    }
    return {
      'kind': 'inspectRepairQueueItem',
      'sourceType': type ?? 'unknown',
      'action':
          'Inspect the first repairQueue item, make the smallest required edit, then rerun the same automation command.',
      'item': item,
      'doneWhen': _repairPlanDoneWhen(type, item),
      'validation': _repairPlanValidation(
        type,
        item,
        rerunCommand: rerunCommand,
      ),
    };
  }

  List<String> _repairPlanDoneWhen(String? type, Map<String, Object?> item) {
    final gate = item['gate'];
    final category = item['category'];
    final coverageItem = item['coverageItem'] ?? item['item'];
    final code = item['code'];
    return switch (type) {
      'diagnostic' => [
        if (code != null) 'diagnostic $code no longer appears',
        'the failed target or scenario step passes',
      ],
      'execution' => [
        'all planned automation commands exit successfully',
        'real run JSON includes passed targets and retained evidence',
      ],
      'coverageBlocked' => [
        'the blocked row has a concrete environment or maintainer-decision note',
        'the final report records the blocker instead of claiming ready',
      ],
      'coverage' => [
        if (gate != null) 'quality gate $gate reports readyForReview',
        'automation.deliveryRecommendation no longer reports needsCoverageReview',
      ],
      'scenarioCoverage' => [
        if (category != null && coverageItem != null)
          '$category/$coverageItem capability coverage reports readyForReview',
        'the scenario coverage row has covered, notApplicable, or blocked status with required notes',
      ],
      'permissionCoverage' => [
        if (coverageItem != null)
          'manifest permission coverage for $coverageItem reports readyForReview',
        'grant and denied/error permission paths are covered or explicitly documented',
      ],
      'pathCoverage' => [
        if (category != null && coverageItem != null)
          '$category/$coverageItem behavior paths report readyForReview',
        'both success and negative/error behavior paths are covered or explicitly documented',
      ],
      'scenarioEvidence' => [
        'scenarioEvidence reports readyForReview for the scenario',
        'the scenario includes a tool-readable assertion such as assertText, waitText, assertLog, or assertSession',
      ],
      'testCoverage' => [
        if (item['expectedTestPath'] != null)
          'focused package test exists at ${item['expectedTestPath']} or an accepted alternative',
        if (item['testCommand'] != null)
          'focused package test command passes: ${item['testCommand']}',
        'existing-test-baseline reports readyForReview',
      ],
      _ => [
        'the first repairQueue item is resolved',
        'rerunning automate no longer emits the same first repair item',
      ],
    };
  }

  Map<String, Object?> _repairPlanValidation(
    String? type,
    Map<String, Object?> item, {
    required String rerunCommand,
  }) {
    final nextCommand = item['nextCommand'];
    if (nextCommand is String && nextCommand.isNotEmpty) {
      return {'kind': 'command', 'command': nextCommand};
    }
    final nextCommands = item['nextCommands'];
    if (nextCommands is List<Object?> && nextCommands.isNotEmpty) {
      return {'kind': 'commands', 'commands': nextCommands};
    }
    if (type == 'testCoverage') {
      final testCommand = item['testCommand'];
      final acceptedTestCommands = item['acceptedTestCommands'];
      return {
        'kind': 'packageTestsThenAutomate',
        if (item['expectedTestPath'] != null)
          'testPath': item['expectedTestPath'],
        if (testCommand is String && testCommand.isNotEmpty)
          'testCommand': testCommand,
        if (acceptedTestCommands is List<Object?> &&
            acceptedTestCommands.isNotEmpty)
          'acceptedTestCommands': acceptedTestCommands,
        'automateCommand': rerunCommand,
        'commands': [
          if (testCommand is String && testCommand.isNotEmpty) testCommand,
          rerunCommand,
        ],
      };
    }
    if (type == 'coverageBlocked') {
      return {'kind': 'reportEvidence', 'automateCommand': rerunCommand};
    }
    return {'kind': 'sameAutomateCommand', 'command': rerunCommand};
  }

  String _repairPlanAction(String? type) {
    return switch (type) {
      'scenarioCoverage' =>
        'Add or update scenario coverage rows for the discovered package capability, then rerun automate.',
      'permissionCoverage' =>
        'Add selected-platform permission coverage rows for grant and denied or error paths, then rerun automate.',
      'pathCoverage' =>
        'Add the missing success or negative behavior path rows, then rerun automate.',
      'scenarioEvidence' =>
        'Add a tool-readable scenario verification action, then rerun automate.',
      'testCoverage' =>
        'Create or expand the focused package test, then rerun package tests and automate.',
      _ =>
        'Apply the printed nextAction, then rerun the same automation command.',
    };
  }

  Map<String, Object?> _deliveryRecommendation(
    List<WorkflowTargetResult> results,
    Map<String, Object?> coveragePolicy, {
    required bool dryRun,
  }) {
    final failedTargets = [
      for (final result in results)
        if (!result.passed) result.targetName,
    ];
    final coverageSummary =
        coveragePolicy['coverageSummary'] as Map<String, Object?>;
    final statusCounts =
        coverageSummary['statusCounts'] as Map<String, Object?>;
    final blockedCoverage = statusCounts['blocked'] as int? ?? 0;
    final gateStatuses = [
      for (final gate in coveragePolicy['qualityGates'] as List<Object?>)
        (gate as Map<String, Object?>)['status'] as String,
    ];
    final hasCoverageGap = gateStatuses.any(_isAutomationCoverageGapStatus);
    final status = failedTargets.isNotEmpty
        ? 'needsRepair'
        : hasCoverageGap
        ? 'needsCoverageReview'
        : blockedCoverage > 0
        ? 'needsMaintainerDecision'
        : dryRun
        ? 'needsExecution'
        : 'readyForReportReview';
    final recommendation = switch (status) {
      'readyForReportReview' => 'ready',
      'needsMaintainerDecision' => 'needs-maintainer-decision',
      _ => 'blocked',
    };
    return {
      'schema': 1,
      'status': status,
      'recommendation': recommendation,
      'ready': status == 'readyForReportReview',
      'reason': _deliveryRecommendationReason(status),
      'targetSummary': {
        'total': results.length,
        'passed': results.where((result) => result.passed).length,
        'failed': failedTargets.length,
        'executed': !dryRun,
        if (dryRun) 'dryRun': true,
      },
      if (failedTargets.isNotEmpty) 'failedTargets': failedTargets,
      'coverageSummary': coverageSummary,
      'finalReportReminder':
          'Ready only applies to the declared automation evidence. The final report must still prove the package capability inventory is complete.',
    };
  }

  String _deliveryRecommendationReason(String status) {
    return switch (status) {
      'needsRepair' =>
        'One or more workflow targets or scenario actions failed; inspect repairQueue and rerun the exact nextCommand.',
      'needsCoverageReview' =>
        'Automation launched, but coverage inventory, metadata, or rows are incomplete.',
      'needsMaintainerDecision' =>
        'Automation ran, but at least one declared coverage row is blocked and needs maintainer or environment decision.',
      'needsExecution' =>
        'Coverage inventory is complete for the dry run, but selected platform automation has not executed yet.',
      _ =>
        'Selected automation targets passed and declared coverage rows are covered or explicitly not applicable.',
    };
  }

  List<Map<String, Object?>> _repairQueue(
    List<WorkflowTargetResult> results,
    Map<String, Object?> coveragePolicy, {
    required List<Map<String, Object?>> checks,
    required bool dryRun,
  }) {
    final coverageQueue = _coverageRepairQueue(coveragePolicy);
    final scenarioCoverageQueue = _scenarioCoverageRepairQueue(coveragePolicy);
    final pathCoverageQueue = _pathCoverageRepairQueue(coveragePolicy);
    final scenarioEvidenceQueue = _scenarioEvidenceRepairQueue(coveragePolicy);
    final testCoverageQueue = _testCoverageRepairQueue(coveragePolicy);
    final blockedQueue = _blockedCoverageQueue(coveragePolicy);
    final targetQueue = _targetRepairQueue(results);
    return [
      ...targetQueue,
      ...scenarioCoverageQueue,
      ...pathCoverageQueue,
      ...scenarioEvidenceQueue,
      ...testCoverageQueue,
      ...blockedQueue,
      ...coverageQueue,
      if (dryRun &&
          coverageQueue.isEmpty &&
          scenarioCoverageQueue.isEmpty &&
          pathCoverageQueue.isEmpty &&
          scenarioEvidenceQueue.isEmpty &&
          testCoverageQueue.isEmpty &&
          targetQueue.isEmpty &&
          blockedQueue.isEmpty)
        _dryRunExecutionQueue(checks),
    ];
  }

  Map<String, Object?> _dryRunExecutionQueue(
    List<Map<String, Object?>> checks,
  ) {
    return {
      'type': 'execution',
      'status': 'needsExecution',
      'repair':
          'Dry-run coverage is ready. Execute the selected platform automation commands and keep the resulting JSON evidence before reporting ready.',
      'nextCommands': [
        for (final check in checks)
          {
            'platform': check['platform'],
            'command': check['command'],
            if (check['sessionFile'] != null)
              'sessionFile': check['sessionFile'],
          },
      ],
    };
  }

  List<Map<String, Object?>> _coverageRepairQueue(
    Map<String, Object?> coveragePolicy,
  ) {
    return [
      for (final gate in coveragePolicy['qualityGates'] as List<Object?>)
        if ((gate as Map<String, Object?>)['status'] != 'readyForReview')
          {
            'type': 'coverage',
            'gate': gate['id'],
            'status': gate['status'],
            'repair': gate['repair'],
            if (gate['items'] != null) 'items': gate['items'],
            if (gate['capabilities'] != null)
              'capabilities': gate['capabilities'],
            if (gate['missingCapabilities'] != null)
              'missingCapabilities': gate['missingCapabilities'],
            if (gate['permissions'] != null) 'permissions': gate['permissions'],
            if (gate['missingPermissions'] != null)
              'missingPermissions': gate['missingPermissions'],
            if (gate['baseline'] != null) 'baseline': gate['baseline'],
            if (gate['scenarios'] != null) 'scenarios': gate['scenarios'],
          },
    ];
  }

  List<Map<String, Object?>> _scenarioCoverageRepairQueue(
    Map<String, Object?> coveragePolicy,
  ) {
    Map<String, Object?>? capabilityGate;
    Map<String, Object?>? permissionGate;
    for (final gate in coveragePolicy['qualityGates'] as List<Object?>) {
      final gateJson = gate as Map<String, Object?>;
      switch (gateJson['id']) {
        case 'capability-inventory-coverage':
          capabilityGate = gateJson;
        case 'manifest-permission-coverage':
          permissionGate = gateJson;
      }
    }
    return [
      ..._capabilityCoverageRepairQueue(capabilityGate),
      ..._permissionCoverageRepairQueue(permissionGate),
    ];
  }

  List<Map<String, Object?>> _scenarioCandidates({
    String? platform,
    String? category,
    String? item,
  }) {
    final selectedPlatforms = platform == null ? platforms : [platform];
    final scope = _automationPathSlug(
      inventory.targetName ?? _pathBasename(inventory.rootPath),
    );
    final itemSlug = _automationPathSlug(item ?? category ?? 'coverage');
    return [
      for (final targetPlatform in selectedPlatforms)
        {
          'platform': targetPlatform,
          'path':
              '${inventory.rootPath}/.fluoh/scenarios/$scope/$targetPlatform-$itemSlug.md',
        },
    ];
  }

  String? _stringField(Map<String, Object?> value, String key) {
    final field = value[key];
    return field is String && field.isNotEmpty ? field : null;
  }

  List<Map<String, Object?>> _pathCoverageRepairQueue(
    Map<String, Object?> coveragePolicy,
  ) {
    Map<String, Object?>? pathGate;
    for (final gate in coveragePolicy['qualityGates'] as List<Object?>) {
      final gateJson = gate as Map<String, Object?>;
      if (gateJson['id'] == 'behavior-paths') {
        pathGate = gateJson;
        break;
      }
    }
    final items = pathGate?['items'];
    if (items is! List<Object?> || items.isEmpty) {
      return const [];
    }
    return [
      for (final item in items)
        if (item is Map<String, Object?>)
          _pathCoverageRepairItem(pathGate, item),
    ];
  }

  Map<String, Object?> _pathCoverageRepairItem(
    Map<String, Object?>? gate,
    Map<String, Object?> item,
  ) {
    final scenarioPaths = _objectList(item['scenarioPaths']);
    final scenarioCandidates = scenarioPaths.isEmpty
        ? _scenarioCandidates(
            category: _stringField(item, 'category'),
            item: _stringField(item, 'item'),
          )
        : [
            for (final path in scenarioPaths)
              if (path is String) {'path': path, 'mode': 'update'},
          ];
    final suggestedCoverage = _pathCoverageSuggestedRows(item);
    return {
      'type': 'pathCoverage',
      'gate': 'behavior-paths',
      'status': item['status'] ?? gate?['status'],
      'repair':
          item['repair'] ??
          'Add explicit coverage rows for both success and negative or error behavior paths.',
      'category': item['category'],
      'item': item['item'],
      if (item['paths'] != null) 'paths': item['paths'],
      if (item['statuses'] != null) 'statuses': item['statuses'],
      if (scenarioPaths.isNotEmpty) 'scenarioPaths': scenarioPaths,
      if (item['missingPath'] == true) 'missingPath': true,
      if (item['needsPositivePath'] == true) 'needsPositivePath': true,
      if (item['needsNegativeOrErrorPath'] == true)
        'needsNegativeOrErrorPath': true,
      'suggestedCoverage': suggestedCoverage,
      'scenarioCandidates': scenarioCandidates,
      'nextAction': {
        'kind': 'addScenarioCoverageRows',
        if (scenarioCandidates.length == 1 &&
            scenarioCandidates.single['path'] != null)
          'path': scenarioCandidates.single['path'],
        'scenarioCandidates': scenarioCandidates,
        'coverage': suggestedCoverage,
      },
    };
  }

  List<Object?> _objectList(Object? value) {
    return value is List<Object?> ? value : const [];
  }

  List<Map<String, Object?>> _pathCoverageSuggestedRows(
    Map<String, Object?> item,
  ) {
    final category = item['category'];
    final coverageItem = item['item'];
    if (category is! String || coverageItem is! String) {
      return const [];
    }
    final missingPath = item['missingPath'] == true;
    final rows = <Map<String, Object?>>[];
    if (missingPath || item['needsPositivePath'] == true) {
      rows.add({
        'category': category,
        'item': coverageItem,
        'path': 'success',
        'status': 'covered',
      });
    }
    if (missingPath || item['needsNegativeOrErrorPath'] == true) {
      rows.add({
        'category': category,
        'item': coverageItem,
        'path': 'error',
        'status': 'covered',
      });
    }
    return rows;
  }

  List<Map<String, Object?>> _scenarioEvidenceRepairQueue(
    Map<String, Object?> coveragePolicy,
  ) {
    Map<String, Object?>? evidenceGate;
    for (final gate in coveragePolicy['qualityGates'] as List<Object?>) {
      final gateJson = gate as Map<String, Object?>;
      if (gateJson['id'] == 'scenario-evidence-assertions') {
        evidenceGate = gateJson;
        break;
      }
    }
    final scenarios = evidenceGate?['scenarios'];
    if (scenarios is! List<Object?> || scenarios.isEmpty) {
      return const [];
    }
    return [
      for (final scenario in scenarios)
        if (scenario is Map<String, Object?>)
          {
            'type': 'scenarioEvidence',
            'gate': 'scenario-evidence-assertions',
            'status': scenario['status'] ?? evidenceGate?['status'],
            'repair':
                scenario['repair'] ??
                'Add a tool-readable verification action after the interaction flow.',
            'platform': scenario['platform'],
            'scenario': scenario['scenario'],
            'path': scenario['path'],
            if (scenario['suggestedActions'] != null)
              'suggestedActions': scenario['suggestedActions'],
            'nextAction': {
              'kind': 'addScenarioVerificationAction',
              'path': scenario['path'],
              if (scenario['suggestedActions'] != null)
                'actions': scenario['suggestedActions'],
            },
          },
    ];
  }

  List<Map<String, Object?>> _capabilityCoverageRepairQueue(
    Map<String, Object?>? gate,
  ) {
    final missingCapabilities = gate?['missingCapabilities'];
    if (missingCapabilities is! List<Object?> || missingCapabilities.isEmpty) {
      return const [];
    }
    return [
      for (final missing in missingCapabilities)
        if (missing is Map<String, Object?>)
          _capabilityCoverageRepairItem(gate, missing),
    ];
  }

  Map<String, Object?> _capabilityCoverageRepairItem(
    Map<String, Object?>? gate,
    Map<String, Object?> missing,
  ) {
    final scenarioCandidates = _scenarioCandidates(
      category: _stringField(missing, 'category'),
      item: _stringField(missing, 'item'),
    );
    return {
      'type': 'scenarioCoverage',
      'gate': 'capability-inventory-coverage',
      'status': missing['status'] ?? gate?['status'],
      'repair':
          missing['repair'] ??
          'Add scenario coverage rows or integration-test evidence for this package capability.',
      'category': missing['category'],
      'item': missing['item'],
      if (missing['source'] != null) 'source': missing['source'],
      if (missing['inventoryPath'] != null)
        'inventoryPath': missing['inventoryPath'],
      if (missing['suggestedCoverage'] != null)
        'suggestedCoverage': missing['suggestedCoverage'],
      'scenarioCandidates': scenarioCandidates,
      'nextAction': {
        'kind': 'addScenarioCoverageRows',
        'scenarioCandidates': scenarioCandidates,
        if (missing['inventoryPath'] != null)
          'source': missing['inventoryPath'],
        if (missing['suggestedCoverage'] != null)
          'coverage': missing['suggestedCoverage'],
      },
    };
  }

  List<Map<String, Object?>> _permissionCoverageRepairQueue(
    Map<String, Object?>? gate,
  ) {
    final missingPermissions = gate?['missingPermissions'];
    if (missingPermissions is! List<Object?> || missingPermissions.isEmpty) {
      return const [];
    }
    return [
      for (final missing in missingPermissions)
        if (missing is Map<String, Object?>)
          _permissionCoverageRepairItem(gate, missing),
    ];
  }

  Map<String, Object?> _permissionCoverageRepairItem(
    Map<String, Object?>? gate,
    Map<String, Object?> missing,
  ) {
    final scenarioCandidates = _scenarioCandidates(
      platform: _stringField(missing, 'platform'),
      category: 'permission',
      item: _stringField(missing, 'coverageItem'),
    );
    return {
      'type': 'permissionCoverage',
      'gate': 'manifest-permission-coverage',
      'status': missing['status'] ?? gate?['status'],
      'repair':
          missing['repair'] ??
          'Add selected-platform scenario rows for this manifest permission, including grant and denied/error paths.',
      'platform': missing['platform'],
      'permission': missing['permission'],
      'coverageItem': missing['coverageItem'],
      if (missing['manifestPath'] != null)
        'manifestPath': missing['manifestPath'],
      if (missing['suggestedCoverage'] != null)
        'suggestedCoverage': missing['suggestedCoverage'],
      'scenarioCandidates': scenarioCandidates,
      'nextAction': {
        'kind': 'addScenarioCoverageRows',
        'platform': missing['platform'],
        if (scenarioCandidates.length == 1 &&
            scenarioCandidates.single['path'] != null)
          'path': scenarioCandidates.single['path'],
        'scenarioCandidates': scenarioCandidates,
        if (missing['manifestPath'] != null) 'source': missing['manifestPath'],
        if (missing['suggestedCoverage'] != null)
          'coverage': missing['suggestedCoverage'],
      },
    };
  }

  List<Map<String, Object?>> _testCoverageRepairQueue(
    Map<String, Object?> coveragePolicy,
  ) {
    Map<String, Object?>? testGate;
    for (final gate in coveragePolicy['qualityGates'] as List<Object?>) {
      final gateJson = gate as Map<String, Object?>;
      if (gateJson['id'] == 'existing-test-baseline') {
        testGate = gateJson;
        break;
      }
    }
    final baseline = testGate?['baseline'];
    if (baseline is! Map<String, Object?>) {
      return const [];
    }
    final missingPackageTests = baseline['missingPackageTests'];
    final weakPackageTests = baseline['weakPackageTests'];
    return [
      if (missingPackageTests is List<Object?>)
        for (final missing in missingPackageTests)
          if (missing is Map<String, Object?>)
            {
              'type': 'testCoverage',
              'gate': 'existing-test-baseline',
              'status': baseline['status'],
              'repair':
                  'Create or expand the package test for this public library before relying on example smoke tests or final report prose.',
              'libraryPath': missing['libraryPath'],
              'expectedTestPath': missing['expectedTestPath'],
              if (missing['acceptedTestPaths'] != null)
                'acceptedTestPaths': missing['acceptedTestPaths'],
              if (missing['testCommand'] != null)
                'testCommand': missing['testCommand'],
              if (missing['acceptedTestCommands'] != null)
                'acceptedTestCommands': missing['acceptedTestCommands'],
              'nextAction': {
                'kind': 'createOrExpandPackageTest',
                'source': missing['libraryPath'],
                'path': missing['expectedTestPath'],
                if (missing['testCommand'] != null)
                  'testCommand': missing['testCommand'],
                if (missing['acceptedTestCommands'] != null)
                  'acceptedTestCommands': missing['acceptedTestCommands'],
              },
            },
      if (weakPackageTests is List<Object?>)
        for (final weak in weakPackageTests)
          if (weak is Map<String, Object?>)
            {
              'type': 'testCoverage',
              'gate': 'existing-test-baseline',
              'status': baseline['status'],
              'repair':
                  'Expand the existing package test so it exercises at least one public declaration from the matching library file.',
              'libraryPath': weak['libraryPath'],
              'testPath': weak['testPath'],
              if (weak['publicDeclarations'] != null)
                'publicDeclarations': weak['publicDeclarations'],
              if (weak['exercisedDeclarations'] != null)
                'exercisedDeclarations': weak['exercisedDeclarations'],
              if (weak['missingDeclarations'] != null)
                'missingDeclarations': weak['missingDeclarations'],
              if (weak['testCommand'] != null)
                'testCommand': weak['testCommand'],
              'nextAction': {
                'kind': 'expandPackageTest',
                'source': weak['libraryPath'],
                'path': weak['testPath'],
                if (weak['missingDeclarations'] != null)
                  'publicDeclarations': weak['missingDeclarations'],
                if (weak['missingDeclarations'] != null)
                  'missingDeclarations': weak['missingDeclarations'],
                if (weak['testCommand'] != null)
                  'testCommand': weak['testCommand'],
              },
            },
    ];
  }

  List<Map<String, Object?>> _targetRepairQueue(
    List<WorkflowTargetResult> results,
  ) {
    final queue = <Map<String, Object?>>[];
    for (final target in results) {
      if (target.passed) {
        continue;
      }
      var addedDiagnostic = false;
      for (final step in target.steps) {
        for (final diagnostic in step.diagnostics) {
          addedDiagnostic = true;
          final repairHints = diagnostic.details['repairHints'];
          queue.add({
            'type': 'diagnostic',
            'target': {'kind': target.targetKind, 'name': target.targetName},
            'step': step.name,
            'code': diagnostic.code,
            'message': diagnostic.message,
            if (diagnostic.nextCommand != null)
              'nextCommand': diagnostic.nextCommand,
            ...(repairHints == null
                ? const <String, Object?>{}
                : {'repairHints': repairHints}),
          });
        }
      }
      if (!addedDiagnostic) {
        queue.add({
          'type': 'target',
          'target': {'kind': target.targetKind, 'name': target.targetName},
          if (target.nextCommand != null) 'nextCommand': target.nextCommand,
        });
      }
    }
    return queue;
  }

  List<Map<String, Object?>> _blockedCoverageQueue(
    Map<String, Object?> coveragePolicy,
  ) {
    final queue = <Map<String, Object?>>[];
    for (final scenario
        in coveragePolicy['scenarioCoverage'] as List<Object?>) {
      final scenarioJson = scenario as Map<String, Object?>;
      for (final item in scenarioJson['items'] as List<Object?>) {
        final coverage = item as Map<String, Object?>;
        if (coverage['status'] == 'blocked') {
          queue.add({
            'type': 'coverageBlocked',
            'platform': scenarioJson['platform'],
            'scenario': scenarioJson['scenario'],
            'path': scenarioJson['path'],
            'coverage': coverage,
          });
        }
      }
    }
    return queue;
  }
}

bool _isAutomationCoverageGapStatus(String status) {
  return status == 'needsInventory' ||
      status == 'needsCapabilityInventory' ||
      status == 'needsCoverageRows' ||
      status == 'needsRepair' ||
      status == 'needsCapabilityCoverageRows' ||
      status == 'needsPathCoverageReview' ||
      status == 'needsTests' ||
      status == 'needsPackageTests' ||
      status == 'needsTestCoverageReview' ||
      status == 'needsPermissionCoverageRows' ||
      status == 'needsEvidenceAssertions';
}

class _AutomationInventory {
  const _AutomationInventory({
    required this.status,
    required this.targetKind,
    required this.rootPath,
    required this.tests,
    required this.platforms,
    required this.capabilities,
    required this.manifestPermissions,
    this.targetName,
    this.packagePath,
    this.examplePath,
    this.warnings = const [],
  });

  final String status;
  final String targetKind;
  final String? targetName;
  final String rootPath;
  final String? packagePath;
  final String? examplePath;
  final _AutomationTestInventory tests;
  final List<_AutomationPlatformInventory> platforms;
  final List<_AutomationCapability> capabilities;
  final List<_AutomationManifestPermission> manifestPermissions;
  final List<String> warnings;

  int get totalTestFileCount => tests.totalTestFileCount;

  int get manifestPermissionCount => manifestPermissions.length;

  int get capabilityCount => capabilities.length;

  Map<String, Object?> toJson() {
    return {
      'schema': 1,
      'status': status,
      'targetKind': targetKind,
      if (targetName != null) 'targetName': targetName,
      'rootPath': rootPath,
      if (packagePath != null) 'packagePath': packagePath,
      if (examplePath != null) 'examplePath': examplePath,
      'tests': tests.toJson(),
      'platforms': platforms.map((platform) => platform.toJson()).toList(),
      'capabilities': capabilities
          .map((capability) => capability.toJson())
          .toList(),
      'manifestPermissions': manifestPermissions
          .map((permission) => permission.toJson())
          .toList(),
      if (warnings.isNotEmpty) 'warnings': warnings,
    };
  }
}

class _AutomationCapability {
  const _AutomationCapability({
    required this.category,
    required this.item,
    required this.path,
    required this.source,
  });

  final String category;
  final String item;
  final String path;
  final String source;

  String get coverageItem => item;

  Map<String, Object?> toJson() {
    return {
      'category': category,
      'item': item,
      'coverageItem': coverageItem,
      'path': path,
      'source': source,
    };
  }
}

class _AutomationTestInventory {
  const _AutomationTestInventory({
    required this.packageTestRunner,
    required this.publicLibraryFiles,
    required this.packageTestFiles,
    required this.packageIntegrationTestFiles,
    required this.exampleTestFiles,
    required this.exampleIntegrationTestFiles,
    this.publicLibraryFilePaths = const [],
    this.packageTestFilePaths = const [],
    this.missingPackageTests = const [],
    this.weakPackageTests = const [],
  });

  final String packageTestRunner;
  final int publicLibraryFiles;
  final int packageTestFiles;
  final int packageIntegrationTestFiles;
  final int exampleTestFiles;
  final int exampleIntegrationTestFiles;
  final List<String> publicLibraryFilePaths;
  final List<String> packageTestFilePaths;
  final List<_AutomationMissingPackageTest> missingPackageTests;
  final List<_AutomationWeakPackageTest> weakPackageTests;

  int get totalTestFileCount =>
      packageTestFiles +
      packageIntegrationTestFiles +
      exampleTestFiles +
      exampleIntegrationTestFiles;

  int get integrationTestFileCount =>
      packageIntegrationTestFiles + exampleIntegrationTestFiles;

  int get missingPackageTestFileCount {
    if (missingPackageTests.isNotEmpty) {
      return missingPackageTests.length;
    }
    final missing = publicLibraryFiles - packageTestFiles;
    return missing > 0 ? missing : 0;
  }

  int get weakPackageTestFileCount => weakPackageTests.length;

  String get baselineStatus {
    if (totalTestFileCount == 0) {
      return 'needsTests';
    }
    if (publicLibraryFiles > 0 && packageTestFiles == 0) {
      return 'needsPackageTests';
    }
    if (missingPackageTestFileCount > 0) {
      return 'needsTestCoverageReview';
    }
    if (weakPackageTestFileCount > 0) {
      return 'needsTestCoverageReview';
    }
    return 'readyForReview';
  }

  Map<String, Object?> get coverageBaseline {
    return {
      'status': baselineStatus,
      'packageTestRunner': packageTestRunner,
      'focusedPackageTestCommandPattern': '$packageTestRunner test <path>',
      'publicLibraryFiles': publicLibraryFiles,
      'packageTestFiles': packageTestFiles,
      'packageIntegrationTestFiles': packageIntegrationTestFiles,
      'exampleTestFiles': exampleTestFiles,
      'exampleIntegrationTestFiles': exampleIntegrationTestFiles,
      'totalTestFiles': totalTestFileCount,
      'integrationTestFiles': integrationTestFileCount,
      'minimumPackageTestFiles': publicLibraryFiles,
      'missingPackageTestFiles': missingPackageTestFileCount,
      'weakPackageTestFiles': weakPackageTestFileCount,
      if (publicLibraryFilePaths.isNotEmpty)
        'publicLibraryFilePaths': publicLibraryFilePaths,
      if (packageTestFilePaths.isNotEmpty)
        'packageTestFilePaths': packageTestFilePaths,
      if (missingPackageTests.isNotEmpty)
        'missingPackageTests': missingPackageTests
            .map((target) => target.toJson())
            .toList(),
      if (weakPackageTests.isNotEmpty)
        'weakPackageTests': weakPackageTests
            .map((target) => target.toJson())
            .toList(),
      'repair':
          'Add or expand package tests for public library files, then add integration_test or scenario evidence for device-facing behavior.',
    };
  }

  Map<String, Object?> toJson() {
    return {
      'packageTestRunner': packageTestRunner,
      'publicLibraryFiles': publicLibraryFiles,
      'packageTestFiles': packageTestFiles,
      'packageIntegrationTestFiles': packageIntegrationTestFiles,
      'exampleTestFiles': exampleTestFiles,
      'exampleIntegrationTestFiles': exampleIntegrationTestFiles,
      'totalTestFiles': totalTestFileCount,
      'coverageBaseline': coverageBaseline,
    };
  }
}

class _AutomationMissingPackageTest {
  const _AutomationMissingPackageTest({
    required this.libraryPath,
    required this.expectedTestPath,
    required this.acceptedTestPaths,
    required this.testCommand,
    required this.acceptedTestCommands,
  });

  final String libraryPath;
  final String expectedTestPath;
  final List<String> acceptedTestPaths;
  final String testCommand;
  final List<String> acceptedTestCommands;

  Map<String, Object?> toJson() {
    return {
      'libraryPath': libraryPath,
      'expectedTestPath': expectedTestPath,
      'acceptedTestPaths': acceptedTestPaths,
      'testCommand': testCommand,
      'acceptedTestCommands': acceptedTestCommands,
      'repair':
          'Add a focused package test for this library file, or add equivalent integration/scenario evidence and mark the coverage row explicitly.',
    };
  }
}

class _AutomationWeakPackageTest {
  const _AutomationWeakPackageTest({
    required this.libraryPath,
    required this.testPath,
    required this.publicDeclarations,
    required this.exercisedDeclarations,
    required this.missingDeclarations,
    required this.testCommand,
  });

  final String libraryPath;
  final String testPath;
  final List<String> publicDeclarations;
  final List<String> exercisedDeclarations;
  final List<String> missingDeclarations;
  final String testCommand;

  Map<String, Object?> toJson() {
    return {
      'libraryPath': libraryPath,
      'testPath': testPath,
      'publicDeclarationCount': publicDeclarations.length,
      'exercisedDeclarationCount': exercisedDeclarations.length,
      'missingDeclarationCount': missingDeclarations.length,
      'publicDeclarations': publicDeclarations,
      'exercisedDeclarations': exercisedDeclarations,
      'missingDeclarations': missingDeclarations,
      'testCommand': testCommand,
      'repair':
          'Expand this package test so it exercises every public declaration from the library file, or move non-runtime behavior to an explicit scenario/integration coverage row.',
    };
  }
}

class _AutomationPlatformInventory {
  const _AutomationPlatformInventory({
    required this.platform,
    required this.packageDirectoryExists,
    required this.exampleDirectoryExists,
  });

  final String platform;
  final bool packageDirectoryExists;
  final bool exampleDirectoryExists;

  Map<String, Object?> toJson() {
    return {
      'platform': platform,
      'packageDirectoryExists': packageDirectoryExists,
      'exampleDirectoryExists': exampleDirectoryExists,
    };
  }
}

class _AutomationManifestPermission {
  const _AutomationManifestPermission({
    required this.platform,
    required this.name,
    required this.path,
    required this.source,
  });

  final String platform;
  final String name;
  final String path;
  final String source;

  String get coverageItem => _permissionCoverageItem(platform, name);

  Map<String, Object?> toJson() {
    return {
      'platform': platform,
      'name': name,
      'coverageItem': coverageItem,
      'path': path,
      'source': source,
    };
  }
}

Future<_AutomationInventory> _automationInventory({
  required FluohEnvironment environment,
  required String? packageName,
  required bool all,
}) async {
  final manifest = await _readOptionalPackageManifest(environment);
  if (manifest == null) {
    if (packageName != null || all) {
      return _AutomationInventory(
        status: 'unresolved',
        targetKind: 'package',
        targetName: packageName,
        rootPath: environment.workingDirectory.path,
        tests: const _AutomationTestInventory(
          packageTestRunner: 'flutter',
          publicLibraryFiles: 0,
          packageTestFiles: 0,
          packageIntegrationTestFiles: 0,
          exampleTestFiles: 0,
          exampleIntegrationTestFiles: 0,
        ),
        platforms: const [],
        capabilities: const [],
        manifestPermissions: const [],
        warnings: const [
          'Package inventory could not be resolved because fluoh.yaml is missing.',
        ],
      );
    }
    return _scanAutomationInventory(
      root: environment.workingDirectory,
      targetKind: 'project',
      targetName: await _pubspecPackageName(environment.workingDirectory),
    );
  }

  final PackageManifestPackage package;
  try {
    package = manifest.packageForName(packageName);
  } on Object catch (error) {
    return _AutomationInventory(
      status: 'unresolved',
      targetKind: 'package',
      targetName: packageName,
      rootPath: environment.workingDirectory.path,
      tests: const _AutomationTestInventory(
        packageTestRunner: 'flutter',
        publicLibraryFiles: 0,
        packageTestFiles: 0,
        packageIntegrationTestFiles: 0,
        exampleTestFiles: 0,
        exampleIntegrationTestFiles: 0,
      ),
      platforms: const [],
      capabilities: const [],
      manifestPermissions: const [],
      warnings: ['Package inventory could not be resolved: $error'],
    );
  }
  final root = _directoryInside(environment.workingDirectory, package.path);
  return _scanAutomationInventory(
    root: root,
    targetKind: 'package',
    targetName: package.name,
    packagePath: package.path,
  );
}

Future<_AutomationInventory> _scanAutomationInventory({
  required Directory root,
  required String targetKind,
  required String? targetName,
  String? packagePath,
}) async {
  final example = Directory('${root.path}/example');
  final exampleExists = await example.exists();
  final isFlutterPackage = await isFlutterPackageDirectory(root);
  final packageTestRunner = isFlutterPackage ? 'flutter' : 'dart';
  final publicLibraryFiles = await _dartFiles(Directory('${root.path}/lib'));
  final packageTestFiles = await _dartFiles(Directory('${root.path}/test'));
  final packageIntegrationTestFiles = await _dartFiles(
    Directory('${root.path}/integration_test'),
  );
  final exampleTestFiles = exampleExists
      ? await _dartFiles(Directory('${example.path}/test'))
      : const <File>[];
  final exampleIntegrationTestFiles = exampleExists
      ? await _dartFiles(Directory('${example.path}/integration_test'))
      : const <File>[];
  final missingPackageTests = _missingPackageTestsForLibraryFiles(
    root: root,
    libraryFiles: publicLibraryFiles,
    packageTestFiles: packageTestFiles,
    packageTestRunner: packageTestRunner,
  );
  final weakPackageTests = await _weakPackageTestsForLibraryFiles(
    root: root,
    libraryFiles: publicLibraryFiles,
    packageTestFiles: packageTestFiles,
    packageTestRunner: packageTestRunner,
  );
  final tests = _AutomationTestInventory(
    packageTestRunner: packageTestRunner,
    publicLibraryFiles: publicLibraryFiles.length,
    packageTestFiles: packageTestFiles.length,
    packageIntegrationTestFiles: packageIntegrationTestFiles.length,
    exampleTestFiles: exampleTestFiles.length,
    exampleIntegrationTestFiles: exampleIntegrationTestFiles.length,
    publicLibraryFilePaths: publicLibraryFiles
        .map((file) => file.path)
        .toList(),
    packageTestFilePaths: packageTestFiles.map((file) => file.path).toList(),
    missingPackageTests: missingPackageTests,
    weakPackageTests: weakPackageTests,
  );
  final platforms = [
    for (final platform in const [
      'ohos',
      'android',
      'ios',
      'macos',
      'linux',
      'web',
      'windows',
    ])
      _AutomationPlatformInventory(
        platform: platform,
        packageDirectoryExists: await Directory(
          '${root.path}/$platform',
        ).exists(),
        exampleDirectoryExists: exampleExists
            ? await Directory('${example.path}/$platform').exists()
            : false,
      ),
  ];
  final permissions = await _manifestPermissions(
    root,
    example: exampleExists ? example : null,
  );
  final capabilities = await _automationCapabilities(
    root,
    example: exampleExists ? example : null,
  );
  return _AutomationInventory(
    status: 'ready',
    targetKind: targetKind,
    targetName: targetName,
    rootPath: root.path,
    packagePath: packagePath,
    examplePath: exampleExists ? example.path : null,
    tests: tests,
    platforms: platforms,
    capabilities: capabilities,
    manifestPermissions: permissions,
    warnings: [
      if (capabilities.isEmpty)
        'No public package capabilities were discovered; inspect public API and example entry points before reporting ready.',
      if (tests.totalTestFileCount == 0)
        'No Dart tests were found under test, integration_test, example/test, or example/integration_test.',
      if (tests.baselineStatus == 'needsPackageTests')
        'No package tests were found for public library files.',
      if (tests.baselineStatus == 'needsTestCoverageReview')
        'Package tests appear lower than the public library surface; inspect coverage before reporting ready.',
      if (permissions.isNotEmpty)
        'Manifest runtime permissions were found; ensure grant and denied/error behavior paths are covered.',
    ],
  );
}

Directory _directoryInside(Directory root, String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty || trimmed == '.') {
    return root;
  }
  return Directory('${root.path}/$trimmed');
}

Future<String?> _pubspecPackageName(Directory directory) async {
  final pubspec = File('${directory.path}/pubspec.yaml');
  if (!await pubspec.exists()) {
    return null;
  }
  try {
    final yaml = parseYamlMap(
      await pubspec.readAsString(),
      label: pubspec.path,
    );
    return optionalString(yaml, 'name');
  } on Object {
    return null;
  }
}

List<_AutomationMissingPackageTest> _missingPackageTestsForLibraryFiles({
  required Directory root,
  required List<File> libraryFiles,
  required List<File> packageTestFiles,
  required String packageTestRunner,
}) {
  final testPaths = {for (final file in packageTestFiles) file.absolute.path};
  final lib = Directory('${root.path}/lib');
  final test = Directory('${root.path}/test');
  final missing = <_AutomationMissingPackageTest>[];
  for (final libraryFile in libraryFiles) {
    final relativeLibraryPath = _relativeFilePath(lib, libraryFile);
    if (relativeLibraryPath == null || !relativeLibraryPath.endsWith('.dart')) {
      continue;
    }
    final libraryStem = relativeLibraryPath.substring(
      0,
      relativeLibraryPath.length - '.dart'.length,
    );
    final expectedTest = File('${test.path}/${libraryStem}_test.dart').absolute;
    final flatTest = File(
      '${test.path}/${_pathBasename(libraryStem)}_test.dart',
    ).absolute;
    final accepted = <String>{expectedTest.path, flatTest.path}.toList()
      ..sort();
    if (accepted.any(testPaths.contains)) {
      continue;
    }
    missing.add(
      _AutomationMissingPackageTest(
        libraryPath: libraryFile.absolute.path,
        expectedTestPath: expectedTest.path,
        acceptedTestPaths: accepted,
        testCommand:
            '$packageTestRunner test ${_workflowShellQuote(expectedTest.path)}',
        acceptedTestCommands: [
          for (final path in accepted)
            '$packageTestRunner test ${_workflowShellQuote(path)}',
        ],
      ),
    );
  }
  missing.sort((a, b) => a.libraryPath.compareTo(b.libraryPath));
  return missing;
}

Future<List<_AutomationWeakPackageTest>> _weakPackageTestsForLibraryFiles({
  required Directory root,
  required List<File> libraryFiles,
  required List<File> packageTestFiles,
  required String packageTestRunner,
}) async {
  final testFilesByPath = {
    for (final file in packageTestFiles) file.absolute.path: file.absolute,
  };
  final lib = Directory('${root.path}/lib');
  final test = Directory('${root.path}/test');
  final weak = <_AutomationWeakPackageTest>[];
  for (final libraryFile in libraryFiles) {
    final relativeLibraryPath = _relativeFilePath(lib, libraryFile);
    if (relativeLibraryPath == null || !relativeLibraryPath.endsWith('.dart')) {
      continue;
    }
    final declarations = await _publicDeclarationNamesForLibraryFile(
      libraryFile,
    );
    if (declarations.isEmpty) {
      continue;
    }
    final libraryStem = relativeLibraryPath.substring(
      0,
      relativeLibraryPath.length - '.dart'.length,
    );
    final acceptedTestFiles = [
      File('${test.path}/${libraryStem}_test.dart').absolute,
      File('${test.path}/${_pathBasename(libraryStem)}_test.dart').absolute,
    ];
    final existingTestFiles = [
      for (final candidate in acceptedTestFiles)
        ?testFilesByPath[candidate.path],
    ];
    if (existingTestFiles.isEmpty) {
      continue;
    }
    final testSource = StringBuffer();
    for (final testFile in existingTestFiles) {
      final content = await _readFileIfExists(testFile);
      if (content != null) {
        testSource.writeln(_stripDartCommentsAndStrings(content));
      }
    }
    final source = testSource.toString();
    final exercisedDeclarations = [
      for (final declaration in declarations)
        if (_containsDartIdentifier(source, declaration)) declaration,
    ];
    final missingDeclarations = [
      for (final declaration in declarations)
        if (!exercisedDeclarations.contains(declaration)) declaration,
    ];
    if (missingDeclarations.isEmpty) {
      continue;
    }
    final testPath = existingTestFiles.first.path;
    weak.add(
      _AutomationWeakPackageTest(
        libraryPath: libraryFile.absolute.path,
        testPath: testPath,
        publicDeclarations: declarations,
        exercisedDeclarations: exercisedDeclarations,
        missingDeclarations: missingDeclarations,
        testCommand: '$packageTestRunner test ${_workflowShellQuote(testPath)}',
      ),
    );
  }
  weak.sort((a, b) => a.libraryPath.compareTo(b.libraryPath));
  return weak;
}

Future<List<String>> _publicDeclarationNamesForLibraryFile(File file) async {
  final declarations = <String>{};
  final declarationFiles = [file, ...await _localDartExportFiles(file)];
  for (final declarationFile in declarationFiles) {
    final content = await _readFileIfExists(declarationFile);
    if (content == null) {
      continue;
    }
    declarations.addAll(_publicDartDeclarations(content));
  }
  final result = declarations.toList()..sort();
  return result;
}

bool _containsDartIdentifier(String source, String identifier) {
  final pattern = RegExp(
    '(^|[^A-Za-z0-9_])${RegExp.escape(identifier)}([^A-Za-z0-9_]|'
    r'$'
    ')',
  );
  return pattern.hasMatch(source);
}

String _stripDartCommentsAndStrings(String content) {
  return _stripDartStringLiterals(_stripDartComments(content));
}

String _stripDartStringLiterals(String content) {
  final buffer = StringBuffer();
  var index = 0;
  while (index < content.length) {
    final rawPrefix =
        content[index] == 'r' &&
        index + 1 < content.length &&
        (content[index + 1] == "'" || content[index + 1] == '"') &&
        (index == 0 || !RegExp(r'[A-Za-z0-9_]').hasMatch(content[index - 1]));
    final quoteIndex = rawPrefix ? index + 1 : index;
    final quote = content[quoteIndex];
    if (quote == "'" || quote == '"') {
      buffer.write(' ');
      index = _skipDartStringLiteral(content, quoteIndex, raw: rawPrefix);
      continue;
    }
    buffer.write(content[index]);
    index += 1;
  }
  return buffer.toString();
}

int _skipDartStringLiteral(
  String content,
  int quoteIndex, {
  required bool raw,
}) {
  final quote = content[quoteIndex];
  final triple =
      quoteIndex + 2 < content.length &&
      content[quoteIndex + 1] == quote &&
      content[quoteIndex + 2] == quote;
  var index = quoteIndex + (triple ? 3 : 1);
  while (index < content.length) {
    if (!raw && content[index] == '\\') {
      index += 2;
      continue;
    }
    if (triple) {
      if (index + 2 < content.length &&
          content[index] == quote &&
          content[index + 1] == quote &&
          content[index + 2] == quote) {
        return index + 3;
      }
      index += 1;
      continue;
    }
    if (content[index] == quote) {
      return index + 1;
    }
    index += 1;
  }
  return content.length;
}

String? _relativeFilePath(Directory root, File file) {
  final rootPath = root.absolute.path;
  final filePath = file.absolute.path;
  final prefix = '$rootPath/';
  if (!filePath.startsWith(prefix)) {
    return null;
  }
  return filePath.substring(prefix.length);
}

String _pathBasename(String path) {
  final index = path.lastIndexOf('/');
  return index == -1 ? path : path.substring(index + 1);
}

Future<List<_AutomationCapability>> _automationCapabilities(
  Directory root, {
  required Directory? example,
}) async {
  final capabilities = <_AutomationCapability>[];
  final seen = <String>{};

  void add({
    required String category,
    required String item,
    required String path,
    required String source,
  }) {
    final trimmedItem = item.trim();
    if (trimmedItem.isEmpty || trimmedItem.startsWith('_')) {
      return;
    }
    final key = '$category\u0000$trimmedItem\u0000$path\u0000$source';
    if (!seen.add(key)) {
      return;
    }
    capabilities.add(
      _AutomationCapability(
        category: category,
        item: trimmedItem,
        path: path,
        source: source,
      ),
    );
  }

  final lib = Directory('${root.path}/lib');
  for (final file in await _publicLibraryEntryFiles(lib)) {
    final declarationFiles = [file, ...await _localDartExportFiles(file)];
    final declarations = <({String name, String path})>[];
    for (final declarationFile in declarationFiles) {
      final content = await _readFileIfExists(declarationFile);
      if (content == null) {
        continue;
      }
      for (final declaration in _publicDartDeclarations(content)) {
        declarations.add((name: declaration, path: declarationFile.path));
      }
    }
    if (declarations.isEmpty) {
      add(
        category: 'publicApi',
        item: _dartFileStem(file),
        path: file.path,
        source: 'publicLibrary',
      );
    } else {
      for (final declaration in declarations) {
        add(
          category: 'publicApi',
          item: declaration.name,
          path: declaration.path,
          source: 'publicLibrary',
        );
      }
    }
  }

  for (final file in await _dartFiles(lib)) {
    final content = await _readFileIfExists(file);
    if (content == null) {
      continue;
    }
    for (final method in _methodChannelCalls(content)) {
      add(
        category: 'methodChannel',
        item: method,
        path: file.path,
        source: 'dartPlatformInterface',
      );
    }
    for (final channel in _platformChannelNames(content)) {
      add(
        category: 'platformChannel',
        item: channel,
        path: file.path,
        source: 'dartPlatformInterface',
      );
    }
  }

  if (example != null) {
    final exampleLib = Directory('${example.path}/lib');
    for (final file in await _dartFiles(exampleLib)) {
      add(
        category: 'exampleFlow',
        item: _dartFileStem(file),
        path: file.path,
        source: 'exampleLibrary',
      );
    }
  }

  capabilities.sort((a, b) {
    final categoryOrder = a.category.compareTo(b.category);
    if (categoryOrder != 0) {
      return categoryOrder;
    }
    final itemOrder = a.item.compareTo(b.item);
    if (itemOrder != 0) {
      return itemOrder;
    }
    return a.path.compareTo(b.path);
  });
  return capabilities;
}

Future<List<File>> _publicLibraryEntryFiles(Directory directory) async {
  if (!await directory.exists()) {
    return const [];
  }
  final files = <File>[];
  try {
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      if (name.endsWith('.dart') && !name.startsWith('_')) {
        files.add(entity);
      }
    }
  } on FileSystemException {
    return files;
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

Future<List<File>> _dartFiles(Directory directory) async {
  if (!await directory.exists()) {
    return const [];
  }
  final files = <File>[];
  try {
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        files.add(entity);
      }
    }
  } on FileSystemException {
    return files;
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

Future<List<File>> _localDartExportFiles(File file) async {
  final files = <File>[];
  final seen = <String>{file.absolute.path};

  Future<void> visit(File current) async {
    final content = await _readFileIfExists(current);
    if (content == null) {
      return;
    }
    for (final exportPath in _localDartExportPaths(content)) {
      final exported = File.fromUri(current.uri.resolve(exportPath)).absolute;
      if (!await exported.exists()) {
        continue;
      }
      if (!seen.add(exported.path)) {
        continue;
      }
      files.add(exported);
      await visit(exported);
    }
  }

  await visit(file.absolute);
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

Iterable<String> _localDartExportPaths(String content) sync* {
  final exportRegex = RegExp(
    r'''^\s*export\s+["']([^"']+)["']''',
    multiLine: true,
  );
  for (final match in exportRegex.allMatches(_stripDartComments(content))) {
    final path = match.group(1)!.trim();
    if (path.endsWith('.dart') &&
        !path.startsWith('dart:') &&
        !path.startsWith('package:')) {
      yield path;
    }
  }
}

Iterable<String> _publicDartDeclarations(String content) sync* {
  final source = _stripDartComments(content);
  var braceDepth = 0;
  for (final line in source.split('\n')) {
    if (braceDepth == 0) {
      final name = _publicDartDeclarationName(line);
      if (name != null && !name.startsWith('_')) {
        yield name;
      }
    }
    braceDepth += _braceDelta(line);
    if (braceDepth < 0) {
      braceDepth = 0;
    }
  }
}

String? _publicDartDeclarationName(String line) {
  final trimmed = line.trimLeft();
  if (trimmed.isEmpty ||
      trimmed.startsWith('@') ||
      trimmed.startsWith('import ') ||
      trimmed.startsWith('export ') ||
      trimmed.startsWith('part ') ||
      trimmed.startsWith('library ')) {
    return null;
  }

  final typeDeclaration = RegExp(
    r'^(?:abstract\s+|base\s+|final\s+|interface\s+|sealed\s+)*'
    r'(?:class|enum|extension|mixin|typedef)\s+([A-Za-z][A-Za-z0-9_]*)',
  ).firstMatch(trimmed);
  if (typeDeclaration != null) {
    return typeDeclaration.group(1);
  }

  final getter = RegExp(
    r'^(?:external\s+)?(?:[A-Za-z][A-Za-z0-9_?<>,.\s]*\s+)?'
    r'get\s+([A-Za-z][A-Za-z0-9_]*)\b',
  ).firstMatch(trimmed);
  if (getter != null) {
    return getter.group(1);
  }

  final function = RegExp(
    r'^(?:external\s+)?(?:[A-Za-z][A-Za-z0-9_?<>,.\s]*\s+)?'
    r'([A-Za-z][A-Za-z0-9_]*)\s*(?:<[^>]+>)?\s*\(',
  ).firstMatch(trimmed);
  if (function != null) {
    final name = function.group(1);
    if (name != 'if' &&
        name != 'for' &&
        name != 'while' &&
        name != 'switch' &&
        name != 'catch') {
      return name;
    }
  }

  return _publicTopLevelVariableName(trimmed);
}

String? _publicTopLevelVariableName(String trimmed) {
  final keywordVariable = RegExp(
    r'^(?:external\s+)?(?:late\s+)?(?:final|const|var)\s+(.+)$',
  ).firstMatch(trimmed);
  if (keywordVariable != null) {
    return _lastIdentifierBeforeInitializer(keywordVariable.group(1)!);
  }

  final typedVariable = RegExp(
    r'^[A-Za-z][A-Za-z0-9_?<>,.\s]*\s+([A-Za-z][A-Za-z0-9_]*)\s*(?:=|;)',
  ).firstMatch(trimmed);
  return typedVariable?.group(1);
}

String? _lastIdentifierBeforeInitializer(String source) {
  final declaration = source.split(RegExp(r'[=;,]')).first.trim();
  if (declaration.isEmpty) {
    return null;
  }
  final tokens = declaration.split(RegExp(r'\s+'));
  final candidate = tokens.last.trim();
  return RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(candidate)
      ? candidate
      : null;
}

int _braceDelta(String line) {
  var delta = 0;
  for (var index = 0; index < line.length; index += 1) {
    final char = line[index];
    if (char == '{') {
      delta += 1;
    } else if (char == '}') {
      delta -= 1;
    }
  }
  return delta;
}

Iterable<String> _methodChannelCalls(String content) sync* {
  final methodRegex = RegExp(
    r'''\.invokeMethod(?:<[^>]+>)?\(\s*["']([^"']+)["']''',
    multiLine: true,
  );
  for (final match in methodRegex.allMatches(content)) {
    final name = match.group(1)!;
    if (!name.startsWith('_')) {
      yield name;
    }
  }
}

Iterable<String> _platformChannelNames(String content) sync* {
  final channelRegex = RegExp(
    r'''(?:MethodChannel|EventChannel|BasicMessageChannel)(?:<[^>]+>)?\s*\(\s*["']([^"']+)["']''',
    multiLine: true,
  );
  for (final match in channelRegex.allMatches(_stripDartComments(content))) {
    final name = match.group(1)!;
    if (!name.startsWith('_')) {
      yield name;
    }
  }
}

String _stripDartComments(String content) {
  return content
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//.*$', multiLine: true), '');
}

String _dartFileStem(File file) {
  final name = file.uri.pathSegments.last;
  return name.endsWith('.dart') ? name.substring(0, name.length - 5) : name;
}

Future<List<_AutomationManifestPermission>> _manifestPermissions(
  Directory root, {
  required Directory? example,
}) async {
  final permissions = <_AutomationManifestPermission>[];
  final seen = <String>{};
  Future<void> add({
    required String platform,
    required String source,
    required File file,
    required Iterable<String> names,
  }) async {
    for (final name in names) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final key = '$platform\u0000$source\u0000$trimmed\u0000${file.path}';
      if (!seen.add(key)) {
        continue;
      }
      permissions.add(
        _AutomationManifestPermission(
          platform: platform,
          name: trimmed,
          path: file.path,
          source: source,
        ),
      );
    }
  }

  for (final sourceRoot in [
    (source: 'package', directory: root),
    if (example != null) (source: 'example', directory: example),
  ]) {
    for (final file in [
      File('${sourceRoot.directory.path}/android/src/main/AndroidManifest.xml'),
      File(
        '${sourceRoot.directory.path}/android/app/src/main/AndroidManifest.xml',
      ),
    ]) {
      final content = await _readFileIfExists(file);
      if (content != null) {
        await add(
          platform: 'android',
          source: sourceRoot.source,
          file: file,
          names: _androidManifestPermissions(content),
        );
      }
    }

    for (final file in await _filesNamed(
      Directory('${sourceRoot.directory.path}/ios'),
      'Info.plist',
    )) {
      final content = await _readFileIfExists(file);
      if (content != null) {
        await add(
          platform: 'ios',
          source: sourceRoot.source,
          file: file,
          names: _iosUsageDescriptionPermissions(content),
        );
      }
    }

    for (final file in await _filesNamed(
      Directory('${sourceRoot.directory.path}/ohos'),
      'module.json5',
    )) {
      final content = await _readFileIfExists(file);
      if (content != null) {
        await add(
          platform: 'ohos',
          source: sourceRoot.source,
          file: file,
          names: _ohosManifestPermissions(content),
        );
      }
    }
  }
  permissions.sort((a, b) {
    final platformOrder = a.platform.compareTo(b.platform);
    if (platformOrder != 0) {
      return platformOrder;
    }
    final nameOrder = a.name.compareTo(b.name);
    if (nameOrder != 0) {
      return nameOrder;
    }
    return a.path.compareTo(b.path);
  });
  return permissions;
}

Future<String?> _readFileIfExists(File file) async {
  if (!await file.exists()) {
    return null;
  }
  try {
    return await file.readAsString();
  } on FileSystemException {
    return null;
  }
}

Future<List<File>> _filesNamed(Directory directory, String name) async {
  if (!await directory.exists()) {
    return const [];
  }
  final files = <File>[];
  try {
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File && entity.uri.pathSegments.last == name) {
        files.add(entity);
      }
    }
  } on FileSystemException {
    return files;
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

Iterable<String> _androidManifestPermissions(String content) sync* {
  final regex = RegExp(
    r'''<uses-permission\b[^>]*\bandroid:name\s*=\s*["']([^"']+)["']''',
    multiLine: true,
  );
  for (final match in regex.allMatches(content)) {
    yield match.group(1)!;
  }
}

Iterable<String> _iosUsageDescriptionPermissions(String content) sync* {
  final regex = RegExp(r'<key>(NS[A-Za-z0-9]+UsageDescription)</key>');
  for (final match in regex.allMatches(content)) {
    yield match.group(1)!;
  }
}

Iterable<String> _ohosManifestPermissions(String content) sync* {
  final regex = RegExp(r'ohos\.permission\.[A-Za-z0-9_.$]+');
  for (final match in regex.allMatches(content)) {
    yield match.group(0)!;
  }
}

String _permissionCoverageItem(String platform, String value) {
  var normalized = value.trim();
  if (platform == 'ios') {
    normalized = normalized
        .replaceFirst(RegExp(r'^NS'), '')
        .replaceFirst(RegExp(r'UsageDescription$'), '');
  } else if (normalized.contains('.')) {
    normalized = normalized.split('.').last;
  }
  final token = _normalizedCoveragePath(normalized);
  if (token.contains('camera')) {
    return 'camera';
  }
  if (token.contains('readmediaaudio') || token == 'audio') {
    return 'audio';
  }
  if (token.contains('recordaudio') || token.contains('microphone')) {
    return 'microphone';
  }
  if (token.contains('speechrecognition')) {
    return 'speech';
  }
  if (token.contains('applemusic') ||
      token.contains('medialibrary') ||
      token == 'media') {
    return 'mediaLibrary';
  }
  if (token.contains('apptrackingtransparency') ||
      token.contains('usertracking')) {
    return 'appTrackingTransparency';
  }
  if (token.contains('siri')) {
    return 'assistant';
  }
  if (token.contains('backgroundlocation') ||
      token.contains('accessbackgroundlocation') ||
      token.contains('locationalways')) {
    return 'locationAlways';
  }
  if (token.contains('locationwheninuse')) {
    return 'locationWhenInUse';
  }
  if (token.contains('finelocation') ||
      token.contains('coarselocation') ||
      token.contains('location')) {
    return 'location';
  }
  if (token.contains('writeexternalstorage')) {
    return 'storage';
  }
  if (token.contains('readmediaimages') ||
      token.contains('readexternalstorage') ||
      token.contains('photo') ||
      token.contains('image')) {
    return 'photos';
  }
  if (token.contains('readmediavideo') || token.contains('video')) {
    return 'videos';
  }
  if (token.contains('getaccounts')) {
    return 'contacts';
  }
  if (token.contains('contact')) {
    return 'contacts';
  }
  if (token.contains('calendar')) {
    return 'calendar';
  }
  if (token.contains('bluetooth')) {
    return 'bluetooth';
  }
  if (token.contains('accessnotificationpolicy') ||
      token.contains('notificationcontroller')) {
    return 'accessNotificationPolicy';
  }
  if (token.contains('postnotifications') || token.contains('notification')) {
    return 'notification';
  }
  if (token.contains('sensor') || token.contains('motion')) {
    return 'sensors';
  }
  if (token.contains('activityrecognition')) {
    return 'activityRecognition';
  }
  if (token.contains('addvoicemail') ||
      token.contains('usesip') ||
      token.contains('phone') ||
      token.contains('call')) {
    return 'phone';
  }
  if (token.contains('receivemms') ||
      token.contains('receivewappush') ||
      token.contains('sms')) {
    return 'sms';
  }
  if (token.contains('ignorebatteryoptimizations')) {
    return 'ignoreBatteryOptimizations';
  }
  if (token.contains('installpackages')) {
    return 'requestInstallPackages';
  }
  if (token.contains('manageexternalstorage')) {
    return 'manageExternalStorage';
  }
  if (token.contains('systemalertwindow')) {
    return 'systemAlertWindow';
  }
  if (token.contains('scheduleexactalarm')) {
    return 'scheduleExactAlarm';
  }
  if (token.contains('nearbywifidevices')) {
    return 'nearbyWifiDevices';
  }
  return token.isEmpty ? value.trim() : token;
}

class _AutomationCoveragePolicy {
  const _AutomationCoveragePolicy({
    required this.scenarios,
    required this.inventory,
    required this.platforms,
  });

  final List<AutomationScenario> scenarios;
  final _AutomationInventory inventory;
  final List<String> platforms;

  Map<String, Object?> toJson() {
    final pathCoverage = _coveragePathCoverage();
    final pathCoverageWarnings = [
      for (final group in pathCoverage)
        if (group.needsReview) group.toJson(),
    ];
    final manifestPermissionCoverage = _manifestPermissionCoverage();
    final manifestPermissionWarnings = [
      for (final requirement in manifestPermissionCoverage)
        if (requirement.needsReview) requirement.toJson(),
    ];
    final capabilityCoverage = _capabilityCoverage();
    final capabilityCoverageWarnings = [
      for (final requirement in capabilityCoverage)
        if (requirement.needsReview) requirement.toJson(),
    ];
    final scenarioEvidence = _scenarioEvidence();
    final scenarioEvidenceWarnings = [
      for (final evidence in scenarioEvidence)
        if (evidence.needsReview) evidence.toJson(),
    ];
    final coverageSummary = _coverageSummary(
      pathGroupCount: pathCoverage.length,
      pathCoverageWarningCount: pathCoverageWarnings.length,
      capabilityCount: capabilityCoverage.length,
      capabilityCoverageWarningCount: capabilityCoverageWarnings.length,
      manifestPermissionCount: manifestPermissionCoverage.length,
      manifestPermissionWarningCount: manifestPermissionWarnings.length,
      scenarioEvidenceWarningCount: scenarioEvidenceWarnings.length,
    );
    final qualityGates = _qualityGates(
      coverageSummary,
      pathCoverageWarnings,
      capabilityCoverageWarnings,
      manifestPermissionWarnings,
      scenarioEvidenceWarnings,
    );
    final status = _coveragePolicyStatus(coverageSummary, qualityGates);
    return {
      'schema': 1,
      'status': status,
      'readyForAutomation': status == 'readyForExecution',
      'readyRule':
          'A package adaptation is ready only after every applicable package capability is covered by automation, integration_test, or an explicit notApplicable or blocked entry in the report.',
      'minimumGates': const [
        {
          'id': 'platform-matrix',
          'required': true,
          'rule':
              'Run every selected mobile platform and keep workflow JSON plus trace or session evidence.',
        },
        {
          'id': 'package-api-inventory',
          'required': true,
          'rule':
              'Inventory public package APIs and example entry points before declaring coverage complete.',
        },
        {
          'id': 'interaction-matrix',
          'required': true,
          'rule':
              'For each applicable interaction class, provide a scenario, integration_test, manual-assisted evidence, or a notApplicable or blocked reason.',
        },
        {
          'id': 'permission-matrix',
          'requiredWhen': 'package declares or requests runtime permissions',
          'rule':
              'Cover every declared or requestable permission on every supported platform; include grant and deny/error paths when package behavior differs.',
        },
        {
          'id': 'regression-matrix',
          'required': true,
          'rule':
              'Run existing-platform regression checks when local Android, iOS, web, or desktop toolchains are available.',
        },
      ],
      'scenarioCoverage': [
        for (final scenario in scenarios)
          {
            'platform': scenario.platform,
            'scenario': scenario.name,
            'path': scenario.path.path,
            'items': scenario.coverage.map((item) => item.toJson()).toList(),
            if (scenario.coverage.isEmpty)
              'coverageWarning':
                  'Scenario has no coverage metadata. Add coverage entries for every capability item it verifies.',
          },
      ],
      'inventory': inventory.toJson(),
      'coverageSummary': coverageSummary,
      'qualityGateSummary': _qualityGateSummary(qualityGates),
      'scenarioSuggestions': _scenarioSuggestions(),
      'pathCoverage': pathCoverage.map((group) => group.toJson()).toList(),
      'capabilityCoverage': capabilityCoverage
          .map((requirement) => requirement.toJson())
          .toList(),
      'manifestPermissionCoverage': manifestPermissionCoverage
          .map((requirement) => requirement.toJson())
          .toList(),
      'scenarioEvidence': scenarioEvidence
          .map((evidence) => evidence.toJson())
          .toList(),
      'qualityGates': qualityGates,
      'repairLoop': const {
        'goal':
            'Repeat diagnose, minimal edit, rerun, and coverage update until every applicable capability row is covered, notApplicable, or blocked with evidence.',
        'steps': [
          {
            'id': 'read-json-diagnostics',
            'action':
                'Parse command JSON, step diagnostics, repairHints, nextCommand, trace paths, session files, and log tails before editing.',
          },
          {
            'id': 'patch-smallest-surface',
            'action':
                'Make the smallest package, example, scenario, or test change needed to address the current failed or missing evidence row.',
          },
          {
            'id': 'rerun-same-command',
            'action':
                'Rerun the exact nextCommand or scenario command that failed before broadening the test scope.',
          },
          {
            'id': 'refresh-coverage',
            'action':
                'Update scenario coverage metadata and the report so missing, blocked, and notApplicable rows stay explicit.',
          },
        ],
        'stopWhen': [
          'all applicable capability rows have tool-readable evidence',
          'format, analysis, tests, and selected platform automation pass',
          'remaining blocked rows are local-environment or maintainer-decision issues with evidence',
        ],
      },
      'interactionClasses': const [
        'permissions',
        'fileOrMediaPickers',
        'cameraOrMicrophone',
        'locationAndSensors',
        'maps',
        'mediaPlaybackOrRecording',
        'deepLinksAndExternalCallbacks',
        'backgroundOrLifecycle',
        'multiStepForms',
        'negativeOrErrorPaths',
      ],
      'capabilityCoverageGuidance':
          'Create coverage rows from the package capability inventory. For each category/item, use explicit path values such as grant, deny, success, failure, cancel, or error, and add notApplicable or blocked rows with notes when a behavior path cannot be automated.',
    };
  }

  List<Map<String, Object?>> _scenarioSuggestions({
    String? platform,
    String? category,
    String? item,
  }) {
    final selectedPlatforms = platform == null ? platforms : [platform];
    final scope = _automationPathSlug(
      inventory.targetName ?? _pathBasename(inventory.rootPath),
    );
    final itemSlug = _automationPathSlug(item ?? category ?? 'coverage');
    return [
      for (final targetPlatform in selectedPlatforms)
        {
          'platform': targetPlatform,
          'path':
              '${inventory.rootPath}/.fluoh/scenarios/$scope/$targetPlatform-$itemSlug.md',
        },
    ];
  }

  Map<String, Object?> _coverageSummary({
    required int pathGroupCount,
    required int pathCoverageWarningCount,
    required int capabilityCount,
    required int capabilityCoverageWarningCount,
    required int manifestPermissionCount,
    required int manifestPermissionWarningCount,
    required int scenarioEvidenceWarningCount,
  }) {
    final statusCounts = <String, int>{
      'covered': 0,
      'notApplicable': 0,
      'blocked': 0,
    };
    final categoryCounts = <String, int>{};
    final scenariosWithoutCoverage = <String>[];
    var itemCount = 0;
    for (final scenario in scenarios) {
      if (scenario.coverage.isEmpty) {
        scenariosWithoutCoverage.add(scenario.path.path);
      }
      for (final item in scenario.coverage) {
        itemCount += 1;
        statusCounts[item.status] = (statusCounts[item.status] ?? 0) + 1;
        categoryCounts[item.category] =
            (categoryCounts[item.category] ?? 0) + 1;
      }
    }
    return {
      'scenarioCount': scenarios.length,
      'itemCount': itemCount,
      'statusCounts': statusCounts,
      'categoryCounts': categoryCounts,
      'scenariosWithoutCoverage': scenariosWithoutCoverage,
      'pathGroupCount': pathGroupCount,
      'pathCoverageWarningCount': pathCoverageWarningCount,
      'capabilityCount': capabilityCount,
      'capabilityCoverageWarningCount': capabilityCoverageWarningCount,
      'manifestPermissionCount': manifestPermissionCount,
      'manifestPermissionWarningCount': manifestPermissionWarningCount,
      'scenarioEvidenceWarningCount': scenarioEvidenceWarningCount,
    };
  }

  String _coveragePolicyStatus(
    Map<String, Object?> coverageSummary,
    List<Map<String, Object?>> qualityGates,
  ) {
    final scenarioCount = coverageSummary['scenarioCount'] as int? ?? 0;
    if (scenarioCount == 0) {
      return 'needsInteractionInventory';
    }
    final hasCoverageGap = qualityGates.any(
      (gate) => _isAutomationCoverageGapStatus(gate['status'] as String? ?? ''),
    );
    if (hasCoverageGap) {
      return 'needsAgentCoverageReview';
    }
    final statusCounts =
        coverageSummary['statusCounts'] as Map<String, Object?>? ??
        const <String, Object?>{};
    final blockedCoverage = statusCounts['blocked'] as int? ?? 0;
    if (blockedCoverage > 0) {
      return 'needsMaintainerDecision';
    }
    return 'readyForExecution';
  }

  Map<String, Object?> _qualityGateSummary(
    List<Map<String, Object?>> qualityGates,
  ) {
    final statusCounts = <String, int>{};
    final notReady = <Map<String, Object?>>[];
    for (final gate in qualityGates) {
      final status = gate['status'] as String? ?? 'unknown';
      statusCounts[status] = (statusCounts[status] ?? 0) + 1;
      if (status != 'readyForReview') {
        notReady.add({
          if (gate['id'] != null) 'id': gate['id'],
          'status': status,
        });
      }
    }
    return {
      'total': qualityGates.length,
      'ready': statusCounts['readyForReview'] ?? 0,
      'notReady': notReady,
      'statusCounts': statusCounts,
    };
  }

  List<_CoveragePathGroup> _coveragePathCoverage() {
    final groups = <String, _CoveragePathGroup>{};
    for (final scenario in scenarios) {
      for (final item in scenario.coverage) {
        final key = '${item.category}\u0000${item.item}';
        final group = groups.putIfAbsent(
          key,
          () => _CoveragePathGroup(category: item.category, item: item.item),
        );
        group.add(item, scenario: scenario);
      }
    }
    return groups.values.toList()..sort((a, b) {
      final categoryOrder = a.category.compareTo(b.category);
      if (categoryOrder != 0) {
        return categoryOrder;
      }
      return a.item.compareTo(b.item);
    });
  }

  List<_CapabilityCoverage> _capabilityCoverage() {
    final requirements = <_CapabilityCoverage>[];
    for (final capability in inventory.capabilities) {
      final requirement = _CapabilityCoverage(capability: capability);
      for (final scenario in scenarios) {
        for (final item in scenario.coverage) {
          if (_coverageMatchesCapability(item, capability)) {
            requirement.add(item, scenario: scenario);
          }
        }
      }
      requirements.add(requirement);
    }
    requirements.sort((a, b) {
      final categoryOrder = a.capability.category.compareTo(
        b.capability.category,
      );
      if (categoryOrder != 0) {
        return categoryOrder;
      }
      final itemOrder = a.capability.coverageItem.compareTo(
        b.capability.coverageItem,
      );
      if (itemOrder != 0) {
        return itemOrder;
      }
      return a.capability.path.compareTo(b.capability.path);
    });
    return requirements;
  }

  List<_ManifestPermissionCoverage> _manifestPermissionCoverage() {
    final requirements = <_ManifestPermissionCoverage>[];
    for (final permission in inventory.manifestPermissions) {
      if (!platforms.contains(permission.platform)) {
        continue;
      }
      final requirement = _ManifestPermissionCoverage(permission: permission);
      for (final scenario in scenarios) {
        if (scenario.platform != permission.platform) {
          continue;
        }
        for (final item in scenario.coverage) {
          if (item.category.toLowerCase() != 'permission') {
            continue;
          }
          if (_permissionCoverageItem(scenario.platform, item.item) !=
              permission.coverageItem) {
            continue;
          }
          requirement.add(item, scenario: scenario);
        }
      }
      requirements.add(requirement);
    }
    requirements.sort((a, b) {
      final platformOrder = a.permission.platform.compareTo(
        b.permission.platform,
      );
      if (platformOrder != 0) {
        return platformOrder;
      }
      final itemOrder = a.permission.coverageItem.compareTo(
        b.permission.coverageItem,
      );
      if (itemOrder != 0) {
        return itemOrder;
      }
      return a.permission.name.compareTo(b.permission.name);
    });
    return requirements;
  }

  List<_ScenarioEvidence> _scenarioEvidence() {
    return [
      for (final scenario in scenarios) _ScenarioEvidence(scenario: scenario),
    ];
  }

  List<Map<String, Object?>> _qualityGates(
    Map<String, Object?> summary,
    List<Map<String, Object?>> pathCoverageWarnings,
    List<Map<String, Object?>> capabilityCoverageWarnings,
    List<Map<String, Object?>> manifestPermissionWarnings,
    List<Map<String, Object?>> scenarioEvidenceWarnings,
  ) {
    final scenarioCount = summary['scenarioCount'] as int;
    final itemCount = summary['itemCount'] as int;
    final scenariosWithoutCoverage =
        (summary['scenariosWithoutCoverage'] as List<String>);
    final capabilityCount = summary['capabilityCount'] as int;
    final manifestPermissionCount = summary['manifestPermissionCount'] as int;
    return [
      {
        'id': 'coverage-inventory',
        'status': scenarioCount == 0 ? 'needsInventory' : 'readyForReview',
        'repair':
            'Inventory package APIs, example entry points, platform interfaces, permissions, and feature classes before declaring readiness.',
      },
      {
        'id': 'coverage-metadata',
        'status': scenarioCount == 0
            ? 'needsInventory'
            : scenariosWithoutCoverage.isEmpty
            ? 'readyForReview'
            : 'needsRepair',
        'repair':
            'Add coverage metadata to every scenario, or mark capability rows notApplicable or blocked with evidence.',
      },
      {
        'id': 'coverage-items',
        'status': itemCount == 0 ? 'needsCoverageRows' : 'readyForReview',
        'repair':
            'Create one coverage row for every applicable capability item and behavior path.',
      },
      {
        'id': 'capability-inventory-coverage',
        'status': inventory.status == 'unresolved'
            ? 'needsInventory'
            : capabilityCount == 0
            ? 'needsCapabilityInventory'
            : capabilityCoverageWarnings.isEmpty
            ? 'readyForReview'
            : 'needsCapabilityCoverageRows',
        'repair':
            'For every discovered public API, platform call, or example entry point, add matching scenario coverage rows, integration-test evidence, or explicit notApplicable or blocked rows.',
        if (capabilityCount > 0)
          'capabilities': inventory.capabilities
              .map((capability) => capability.toJson())
              .toList(),
        if (capabilityCoverageWarnings.isNotEmpty)
          'missingCapabilities': capabilityCoverageWarnings,
      },
      {
        'id': 'scenario-evidence-assertions',
        'status': scenarioCount == 0
            ? 'needsInventory'
            : itemCount == 0
            ? 'needsCoverageRows'
            : scenarioEvidenceWarnings.isEmpty
            ? 'readyForReview'
            : 'needsEvidenceAssertions',
        'repair':
            'Every scenario with coverage rows must include tool-readable verification such as assertText, waitText, assertLog, or assertSession.',
        if (scenarioEvidenceWarnings.isNotEmpty)
          'scenarios': scenarioEvidenceWarnings,
      },
      {
        'id': 'existing-test-baseline',
        'status': inventory.status == 'unresolved'
            ? 'needsInventory'
            : inventory.tests.baselineStatus,
        'repair':
            'Inspect existing test and integration_test coverage, then add or expand unit, widget, integration, or scenario evidence before marking the package ready.',
        if (inventory.status != 'unresolved')
          'baseline': inventory.tests.coverageBaseline,
      },
      {
        'id': 'manifest-permission-coverage',
        'status': inventory.status == 'unresolved'
            ? 'needsInventory'
            : manifestPermissionWarnings.isNotEmpty
            ? 'needsPermissionCoverageRows'
            : 'readyForReview',
        'repair':
            'For every runtime permission found in selected Android, iOS, or OHOS manifests, add scenario coverage rows for grant and denied/error behavior paths, or mark rows notApplicable or blocked with notes.',
        if (manifestPermissionCount > 0)
          'permissions': inventory.manifestPermissions
              .where((permission) => platforms.contains(permission.platform))
              .map((permission) => permission.toJson())
              .toList(),
        if (manifestPermissionWarnings.isNotEmpty)
          'missingPermissions': manifestPermissionWarnings,
      },
      {
        'id': 'behavior-paths',
        'status': scenarioCount == 0
            ? 'needsInventory'
            : itemCount == 0
            ? 'needsCoverageRows'
            : pathCoverageWarnings.isEmpty
            ? 'readyForReview'
            : 'needsPathCoverageReview',
        'repair':
            'For each category/item, declare both a successful path and a denied, cancelled, failure, or error path. Use notApplicable or blocked with notes when a path cannot be automated.',
        if (pathCoverageWarnings.isNotEmpty) 'items': pathCoverageWarnings,
      },
    ];
  }
}

class _ScenarioEvidence {
  const _ScenarioEvidence({required this.scenario});

  final AutomationScenario scenario;

  int get coveredCoverageItemCount =>
      scenario.coverage.where((item) => item.status == 'covered').length;

  int get explanatoryCoverageItemCount =>
      scenario.coverage.length - coveredCoverageItemCount;

  bool get needsReview =>
      coveredCoverageItemCount > 0 && verificationActions.isEmpty;

  List<String> get verificationActions {
    return [
      for (final action in scenario.steps)
        if (_isScenarioVerificationAction(action.action)) action.action,
    ];
  }

  Map<String, Object?> toJson() {
    final actions = verificationActions;
    return {
      'platform': scenario.platform,
      'scenario': scenario.name,
      'path': scenario.path.path,
      'coverageItemCount': scenario.coverage.length,
      'coveredCoverageItemCount': coveredCoverageItemCount,
      'explanatoryCoverageItemCount': explanatoryCoverageItemCount,
      'status': needsReview ? 'needsEvidenceAssertions' : 'readyForReview',
      'verificationActions': actions,
      if (needsReview)
        'repair':
            'Add at least one tool-readable verification action after the interaction flow, such as assertText, waitText, assertLog, or assertSession.',
      if (needsReview)
        'suggestedActions': const [
          {'action': 'assertText'},
          {'action': 'assertLog'},
          {'action': 'assertSession'},
        ],
    };
  }
}

bool _isScenarioVerificationAction(String action) {
  const verificationActions = {
    'assertText',
    'waitText',
    'assertLog',
    'assertSession',
  };
  return verificationActions.contains(action);
}

class _CapabilityCoverage {
  _CapabilityCoverage({required this.capability});

  final _AutomationCapability capability;
  final Set<String> _statuses = <String>{};
  final Set<String> _scenarios = <String>{};
  final Set<String> _paths = <String>{};

  bool get needsReview => _scenarios.isEmpty;

  void add(
    AutomationScenarioCoverageItem item, {
    required AutomationScenario scenario,
  }) {
    _statuses.add(item.status);
    _scenarios.add(scenario.path.path);
    final path = item.path?.trim();
    if (path != null && path.isNotEmpty) {
      _paths.add(path);
    }
  }

  Map<String, Object?> toJson() {
    return {
      'category': capability.category,
      'item': capability.coverageItem,
      'source': capability.source,
      'inventoryPath': capability.path,
      'status': needsReview ? 'needsCapabilityCoverageRows' : 'readyForReview',
      'paths': _sorted(_paths),
      'statuses': _sorted(_statuses),
      'scenarioPaths': _sorted(_scenarios),
      'scenarioCount': _scenarios.length,
      if (needsReview)
        'suggestedCoverage': [
          {
            'category': capability.category,
            'item': capability.coverageItem,
            'path': 'success',
            'status': 'covered',
          },
          {
            'category': capability.category,
            'item': capability.coverageItem,
            'path': 'error',
            'status': 'covered',
          },
        ],
      if (needsReview)
        'repair':
            'Add scenario coverage or integration-test evidence for this package capability, or mark it notApplicable or blocked with a note.',
    };
  }

  List<String> _sorted(Set<String> values) {
    return values.toList()..sort();
  }
}

bool _coverageMatchesCapability(
  AutomationScenarioCoverageItem item,
  _AutomationCapability capability,
) {
  if (_normalizedCoveragePath(item.item) !=
      _normalizedCoveragePath(capability.coverageItem)) {
    return false;
  }
  final coverageCategory = _normalizedCapabilityCategory(item.category);
  if (coverageCategory == 'capability') {
    return true;
  }
  return coverageCategory == _normalizedCapabilityCategory(capability.category);
}

String _normalizedCapabilityCategory(String category) {
  final normalized = _normalizedCoveragePath(category);
  return switch (normalized) {
    'api' || 'publicapi' || 'packageapi' => 'publicapi',
    'methodchannel' || 'platformcall' || 'nativecall' => 'methodchannel',
    'example' || 'exampleflow' || 'exampleentrypoint' => 'exampleflow',
    'capability' || 'feature' => 'capability',
    _ => normalized,
  };
}

class _ManifestPermissionCoverage {
  _ManifestPermissionCoverage({required this.permission});

  final _AutomationManifestPermission permission;
  final Set<String> _paths = <String>{};
  final Set<String> _statuses = <String>{};
  final Set<String> _scenarios = <String>{};
  var _hasPositivePath = false;
  var _hasNegativeOrErrorPath = false;

  bool get needsReview => !_hasPositivePath || !_hasNegativeOrErrorPath;

  void add(
    AutomationScenarioCoverageItem item, {
    required AutomationScenario scenario,
  }) {
    _statuses.add(item.status);
    _scenarios.add(scenario.path.path);
    final path = item.path?.trim();
    if (path == null || path.isEmpty) {
      return;
    }
    _paths.add(path);
    if (_isNegativeOrErrorCoveragePath(path)) {
      _hasNegativeOrErrorPath = true;
    } else if (_isPositiveCoveragePath(path)) {
      _hasPositivePath = true;
    }
  }

  Map<String, Object?> toJson() {
    return {
      'platform': permission.platform,
      'permission': permission.name,
      'coverageItem': permission.coverageItem,
      'source': permission.source,
      'manifestPath': permission.path,
      'status': needsReview ? 'needsPermissionCoverageRows' : 'readyForReview',
      'paths': _sorted(_paths),
      'statuses': _sorted(_statuses),
      'scenarioCount': _scenarios.length,
      if (!_hasPositivePath) 'needsPositivePath': true,
      if (!_hasNegativeOrErrorPath) 'needsNegativeOrErrorPath': true,
      if (needsReview)
        'suggestedCoverage': [
          {
            'category': 'permission',
            'item': permission.coverageItem,
            'path': 'grant',
            'status': 'covered',
          },
          {
            'category': 'permission',
            'item': permission.coverageItem,
            'path': 'deny',
            'status': 'covered',
          },
        ],
      if (needsReview)
        'repair':
            'Add selected-platform scenario coverage for this manifest permission, including grant and denied/error behavior paths, or mark a path notApplicable or blocked with a note.',
    };
  }

  List<String> _sorted(Set<String> values) {
    return values.toList()..sort();
  }
}

class _CoveragePathGroup {
  _CoveragePathGroup({required this.category, required this.item});

  final String category;
  final String item;
  final Set<String> _paths = <String>{};
  final Set<String> _statuses = <String>{};
  final Set<String> _scenarios = <String>{};
  var _hasMissingPath = false;
  var _hasPositivePath = false;
  var _hasNegativeOrErrorPath = false;

  bool get needsReview =>
      _hasMissingPath || !_hasPositivePath || !_hasNegativeOrErrorPath;

  void add(
    AutomationScenarioCoverageItem item, {
    required AutomationScenario scenario,
  }) {
    _statuses.add(item.status);
    _scenarios.add(scenario.path.path);
    final path = item.path?.trim();
    if (path == null || path.isEmpty) {
      _hasMissingPath = true;
      return;
    }
    _paths.add(path);
    if (_isNegativeOrErrorCoveragePath(path)) {
      _hasNegativeOrErrorPath = true;
    } else if (_isPositiveCoveragePath(path)) {
      _hasPositivePath = true;
    }
  }

  Map<String, Object?> toJson() {
    return {
      'category': category,
      'item': item,
      'status': needsReview ? 'needsPathCoverageReview' : 'readyForReview',
      'paths': _sorted(_paths),
      'statuses': _sorted(_statuses),
      'scenarioPaths': _sorted(_scenarios),
      'scenarioCount': _scenarios.length,
      if (_hasMissingPath) 'missingPath': true,
      if (!_hasPositivePath) 'needsPositivePath': true,
      if (!_hasNegativeOrErrorPath) 'needsNegativeOrErrorPath': true,
      if (needsReview)
        'repair':
            'Add explicit coverage rows for both success and denied, cancelled, failure, or error behavior paths; use notApplicable or blocked with a note when a path is intentionally not automated.',
    };
  }

  List<String> _sorted(Set<String> values) {
    return values.toList()..sort();
  }
}

bool _isPositiveCoveragePath(String path) {
  if (_isNegativeOrErrorCoveragePath(path)) {
    return false;
  }
  final normalized = _normalizedCoveragePath(path);
  const tokens = [
    'grant',
    'allow',
    'authorize',
    'success',
    'happy',
    'enable',
    'available',
    'select',
    'pick',
    'capture',
    'record',
    'play',
    'read',
    'write',
    'create',
    'update',
    'delete',
    'request',
    'load',
    'save',
    'start',
    'stop',
    'open',
    'callback',
    'valid',
    'accept',
  ];
  return tokens.any(normalized.contains);
}

bool _isNegativeOrErrorCoveragePath(String path) {
  final normalized = _normalizedCoveragePath(path);
  const tokens = [
    'deny',
    'denied',
    'reject',
    'revoke',
    'error',
    'fail',
    'cancel',
    'unavailable',
    'disable',
    'blocked',
    'timeout',
    'exception',
    'unsupported',
    'missing',
    'invalid',
    'unauthorize',
    'forbidden',
    'empty',
    'negative',
  ];
  return tokens.any(normalized.contains);
}

String _normalizedCoveragePath(String path) {
  return path.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

class _AutomationCheckPlan {
  const _AutomationCheckPlan({
    required this.platform,
    required this.packageName,
    required this.all,
    required this.deviceId,
    required this.emulatorName,
    required this.autoEmulator,
    required this.sessionDirectory,
    required this.traceOptions,
  });

  final String platform;
  final String? packageName;
  final bool all;
  final String? deviceId;
  final String? emulatorName;
  final bool autoEmulator;
  final Directory sessionDirectory;
  final TraceOptions traceOptions;

  Map<String, Object?> toJson() {
    final sessionFile = _automationSessionFile(
      platform: platform,
      targetName: packageName ?? '<target>',
      sessionDirectory: sessionDirectory,
    );
    return {
      'platform': platform,
      'command': _automationRunCommand(
        platform: platform,
        packageName: packageName,
        all: all,
        deviceId: deviceId,
        emulatorName: emulatorName,
        autoEmulator: autoEmulator,
        sessionFile: sessionFile,
        traceOptions: traceOptions,
      ),
      'evidence': [
        'fluoh workflow JSON',
        'trace manifest when --trace or --trace-dir is used',
        if (platform == 'ohos') 'OHOS hilog runtime scan',
        if (platform == 'android' || platform == 'ios')
          'flutterRunSession JSON',
        if (platform == 'android' || platform == 'ios')
          'Flutter VM Service URI when exposed',
        if (platform == 'android' || platform == 'ios')
          'flutter run output log',
        'integration_test result when integration_test/ exists',
      ],
      'agentLoop': [
        'select or boot local emulator/simulator',
        'build and launch package example or project app',
        'collect run session, logs, diagnostics, and trace references',
        'route failures through nextCommand before editing again',
      ],
      if (sessionFile != null) 'sessionFile': sessionFile.path,
      if (platform == 'ohos')
        'ohos': {
          'sessionFile': null,
          'debugEvidence':
              'installable HAP, launch ability metadata, target id, hilog file, and runtime findings',
        },
    };
  }
}

String _automationRunCommand({
  required String platform,
  required String? packageName,
  required bool all,
  required String? deviceId,
  required String? emulatorName,
  required bool autoEmulator,
  required File? sessionFile,
  required TraceOptions traceOptions,
}) {
  final parts = [
    'fluoh',
    'run',
    '--platform',
    platform,
    if (packageName != null) ...['--package', packageName],
    if (all) '--all',
    if (deviceId != null) ...['--device', deviceId],
    if (emulatorName != null) ...['--emulator', emulatorName],
    if (deviceId == null &&
        emulatorName == null &&
        autoEmulator &&
        !_isDesktopRunPlatform(platform))
      '--auto-emulator',
    if (sessionFile != null) ...['--session-file', sessionFile.path],
    if (traceOptions.enabled && traceOptions.directory == null) '--trace',
    if (traceOptions.directory != null) ...[
      '--trace-dir',
      traceOptions.directory!.path,
    ],
    '--json',
  ];
  return parts.map(_workflowShellQuote).join(' ');
}

String _workflowShellQuote(String value) {
  if (value.isEmpty) {
    return "''";
  }
  if (!RegExp(r'''[\s'"\\$`]''').hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", r"'\''")}'";
}

void _printAutomationPlan(_AutomationPlan plan, TerminalOutput output) {
  output.write('Automation plan:');
  for (final check in plan.toJson()['checks']! as List<Object?>) {
    final item = check as Map<String, Object?>;
    output.write('  ${item['platform']}: ${item['command']}');
  }
}

void _addPackageSelectionOptions(ArgParser parser) {
  parser
    ..addOption(
      'package',
      valueHelp: 'name',
      help: 'Package to use. Defaults to the current package branch.',
    )
    ..addFlag(
      'all',
      negatable: false,
      help: 'Run every target in the current project or package branch.',
    );
}

void _addTraceOptions(ArgParser parser) {
  parser
    ..addFlag(
      'trace',
      negatable: false,
      help:
          'Write a local AI diagnostic trace under .fluoh/traces, grouped by package when possible.',
    )
    ..addOption(
      'trace-dir',
      valueHelp: 'path',
      help: 'Write the AI diagnostic trace to a specific directory.',
    );
}

void _validatePackageSelection(ArgResults results, UsageError usageException) {
  if (results.flag('all') &&
      (results.option('package')?.trim().isNotEmpty ?? false)) {
    usageException('Use only one of --all or --package.');
  }
}

TraceOptions _traceOptionsFrom(ArgResults results) {
  final traceDir = _trimmedOption(results, 'trace-dir');
  return TraceOptions(
    enabled: results.flag('trace') || traceDir != null,
    directory: traceDir == null ? null : Directory(traceDir),
  );
}

Future<List<WorkflowTargetResult>> _runPackageOrProject({
  required FluohEnvironment environment,
  required String? packageName,
  required bool all,
  required TerminalOutput output,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required String usage,
  _PackageWorkflowInvocation Function(PackageManifestPackage package)?
  invocationForPackage,
  _ProjectWorkflowInvocation? projectInvocation,
  Duration deviceTimeout = const Duration(seconds: 90),
  Duration logDuration = const Duration(seconds: 8),
}) async {
  final manifest = await _readOptionalPackageManifest(environment);
  if (manifest == null) {
    if (all || packageName != null) {
      throw UsageException(
        'Current directory is not a package repository.',
        usage,
      );
    }
    return [
      await _runProjectWorkflow(
        environment: environment,
        output: output,
        stdout: stdout,
        stderr: stderr,
        usage: usage,
        invocation:
            projectInvocation ?? const _ProjectWorkflowInvocation.baseline(),
        deviceTimeout: deviceTimeout,
        logDuration: logDuration,
      ),
    ];
  }

  final packages = all
      ? [manifest.package]
      : [manifest.packageForName(packageName)];
  final results = <WorkflowTargetResult>[];
  for (final package in packages) {
    final invocation =
        invocationForPackage?.call(package) ??
        const _PackageWorkflowInvocation(phase: 'baseline');
    output.step(invocation.stepMessage(package.name));
    final result = await runPackageWorkflow(
      environment: environment,
      manifest: manifest,
      package: package,
      stdout: stdout,
      stderr: stderr,
      output: output,
      usage: usage,
      buildExampleTarget: invocation.buildExampleTarget,
      buildExampleDebug: invocation.debug,
      buildExampleForSimulator: invocation.buildExampleForSimulator,
      autoSignExample: invocation.autoSign,
      runExample: invocation.runExample,
      deviceId: invocation.deviceId,
      startEmulator: invocation.startEmulator,
      emulatorName: invocation.emulatorName,
      sessionFile: invocation.sessionFile,
      deviceTimeout: deviceTimeout,
      logDuration: logDuration,
      phase: invocation.phase,
    );
    results.add(result);
    if (!result.passed) {
      return results;
    }
  }
  return results;
}

Future<PackageManifest?> _readOptionalPackageManifest(
  FluohEnvironment environment,
) async {
  final file = File('${environment.workingDirectory.path}/fluoh.yaml');
  if (!await file.exists()) {
    return null;
  }
  final content = await file.readAsString();
  final yaml = parseYamlMap(content, label: 'fluoh.yaml');
  if (!yaml.containsKey('packages') &&
      !yaml.containsKey('repository') &&
      !yaml.containsKey('upstream')) {
    return null;
  }
  return readPackageManifest(environment.workingDirectory);
}

class _PackageWorkflowInvocation {
  const _PackageWorkflowInvocation({
    required this.phase,
    this.buildExampleTarget,
    this.debug = false,
    this.buildExampleForSimulator = false,
    this.autoSign = false,
    this.runExample = false,
    this.deviceId,
    this.startEmulator = false,
    this.emulatorName,
    this.sessionFile,
  });

  final String phase;
  final String? buildExampleTarget;
  final bool debug;
  final bool buildExampleForSimulator;
  final bool autoSign;
  final bool runExample;
  final String? deviceId;
  final bool startEmulator;
  final String? emulatorName;
  final File? sessionFile;

  String stepMessage(String packageName) {
    if (phase == 'baseline') {
      return 'Verifying $packageName';
    }
    if (phase.endsWith('-build')) {
      return 'Building $packageName ($phase)';
    }
    if (phase.endsWith('-run')) {
      return 'Running $packageName ($phase)';
    }
    return 'Running $packageName ($phase)';
  }
}

class _ProjectWorkflowInvocation {
  const _ProjectWorkflowInvocation.baseline()
    : kind = 'baseline',
      platform = null,
      debug = false,
      autoSign = false,
      deviceId = null,
      startEmulator = false,
      emulatorName = null,
      sessionFile = null;

  const _ProjectWorkflowInvocation.build({
    required this.platform,
    required this.debug,
    required this.autoSign,
  }) : kind = 'build',
       deviceId = null,
       startEmulator = false,
       emulatorName = null,
       sessionFile = null;

  const _ProjectWorkflowInvocation.run({
    required this.platform,
    required this.deviceId,
    required this.startEmulator,
    required this.emulatorName,
    required this.sessionFile,
  }) : kind = 'run',
       debug = true,
       autoSign = false;

  final String kind;
  final String? platform;
  final bool debug;
  final bool autoSign;
  final String? deviceId;
  final bool startEmulator;
  final String? emulatorName;
  final File? sessionFile;
}

Future<WorkflowTargetResult> _runProjectWorkflow({
  required FluohEnvironment environment,
  required TerminalOutput output,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required String usage,
  required _ProjectWorkflowInvocation invocation,
  Duration deviceTimeout = const Duration(seconds: 90),
  Duration logDuration = const Duration(seconds: 8),
}) async {
  final project = environment.workingDirectory;
  final pubspec = File('${project.path}/pubspec.yaml');
  if (!await pubspec.exists()) {
    throw UsageException('Missing pubspec.yaml.', usage);
  }
  final isFlutter = await isFlutterPackageDirectory(project);
  final steps = <WorkflowStepResult>[];

  Future<bool> runTool(List<String> arguments, String name) async {
    final result = isFlutter
        ? await runSelectedFlutterResult(
            environment: environment,
            arguments: arguments,
            workingDirectory: project,
            stdout: stdout,
            stderr: stderr,
            output: output,
            usage: usage,
          )
        : await runSelectedDartResult(
            environment: environment,
            arguments: arguments,
            workingDirectory: project,
            stdout: stdout,
            stderr: stderr,
            output: output,
            usage: usage,
          );
    steps.add(
      _toolStep(
        name: name,
        path: '.',
        flutter: isFlutter,
        arguments: arguments,
        result: result,
        diagnosticCode: _projectBaselineDiagnosticCode(name),
        diagnosticMessage: _projectBaselineDiagnosticMessage(name),
        nextCommand: 'fluoh verify --json',
      ),
    );
    return result.exitCode == 0;
  }

  if (invocation.kind == 'baseline') {
    output.step('Running baseline verification in current project');
    if (!await runTool(const ['pub', 'get'], 'project-pub-get')) {
      return WorkflowTargetResult.project(
        projectName: 'current',
        exitCode: _lastExitCode(steps),
        steps: steps,
        phase: 'baseline',
      );
    }
    if (!await runTool(const ['analyze'], 'project-analyze')) {
      return WorkflowTargetResult.project(
        projectName: 'current',
        exitCode: _lastExitCode(steps),
        steps: steps,
        phase: 'baseline',
      );
    }
    if (await hasPackageTests(project)) {
      if (!await runTool(const ['test'], 'project-test')) {
        return WorkflowTargetResult.project(
          projectName: 'current',
          exitCode: _lastExitCode(steps),
          steps: steps,
          phase: 'baseline',
        );
      }
    } else {
      steps.add(
        const WorkflowStepResult(
          name: 'project-test',
          path: '.',
          command: 'test',
          status: 'skipped',
          reason: 'no test files',
        ),
      );
    }
    if (await hasIntegrationTests(project)) {
      output.skipped(
        'Discovered project integration tests: run a platform target to execute them on a device',
      );
      steps.add(
        _projectIntegrationDiscoveryStep(
          name: 'project-integration',
          path: '.',
        ),
      );
    }
    return WorkflowTargetResult.project(
      projectName: 'current',
      exitCode: 0,
      steps: steps,
      phase: 'baseline',
    );
  }

  if (!isFlutter) {
    throw UsageException('Build and run require a Flutter project.', usage);
  }
  final platform = invocation.platform!;
  if (invocation.kind == 'run') {
    if (platform == 'ohos') {
      return _runProjectOhosWorkflow(
        environment: environment,
        project: project,
        output: output,
        stdout: stdout,
        stderr: stderr,
        usage: usage,
        invocation: invocation,
        deviceTimeout: deviceTimeout,
        logDuration: logDuration,
      );
    }
    final runResult = await runFlutterExampleOnDevice(
      environment: environment,
      exampleDirectory: project,
      buildExampleTarget: _buildTargetForPlatform(platform),
      output: output,
      stdout: stdout,
      stderr: stderr,
      deviceId: invocation.deviceId,
      startEmulator: invocation.startEmulator,
      emulatorName: invocation.emulatorName,
      sessionFile: invocation.sessionFile,
      deviceTimeout: deviceTimeout,
      runDuration: logDuration,
      usage: usage,
    );
    steps.add(
      WorkflowStepResult(
        name: 'project-run-${runResult.platform}',
        path: '.',
        command: runResult.command,
        status: runResult.passed ? 'passed' : 'failed',
        exitCode: runResult.exitCode,
        reason: runResult.reason,
        details: {
          ...runResult.details,
          'platform': runResult.platform,
          if (runResult.target != null) 'target': runResult.target!.toJson(),
          if (runResult.emulator != null)
            'emulator': runResult.emulator!.toJson(),
          if (runResult.outputLog != null)
            'outputLog': runResult.outputLog!.path,
        },
        diagnostics: runResult.diagnostics
            .map(
              (diagnostic) => WorkflowDiagnostic(
                code: diagnostic.code,
                severity: diagnostic.severity,
                message: diagnostic.message,
                details: diagnostic.details,
                nextCommand: _projectNextCommandForDiagnosticCode(
                  diagnostic.code,
                  invocation,
                ),
              ),
            )
            .toList(),
      ),
    );
    if (!runResult.passed) {
      return WorkflowTargetResult.project(
        projectName: 'current',
        exitCode: runResult.exitCode,
        steps: steps,
        phase: 'run-$platform',
      );
    }
    final integrationExitCode = await _appendProjectIntegrationRunSteps(
      environment: environment,
      project: project,
      platform: runResult.platform,
      targetId: runResult.target?.id,
      stdout: stdout,
      stderr: stderr,
      output: output,
      usage: usage,
      steps: steps,
      nextCommand: _projectRunNextCommand(invocation),
    );
    return WorkflowTargetResult.project(
      projectName: 'current',
      exitCode: integrationExitCode ?? runResult.exitCode,
      steps: steps,
      phase: 'run-$platform',
    );
  }

  final signingSteps = <WorkflowStepResult>[];
  OhosBuildProfileSigningSession? signingSession;
  OhosDebugSigningMaterial? signingMaterial;
  var signingMode = '';
  final ohosDirectory = Directory('${project.path}/ohos');
  if (platform == 'ohos') {
    await stabilizeOhosResourceLayout(ohosDirectory);
  }
  if (invocation.autoSign) {
    if (!await ohosDirectory.exists()) {
      const reason = 'Missing OHOS project.';
      steps.add(
        _projectOhosDiagnosticStep(
          name: 'ohos-auto-sign',
          command: 'prepare OHOS debug signing',
          code: 'ohos.ohos_project_missing',
          message: reason,
          reason: '$reason Expected ./ohos.',
          details: {'expectedPath': 'ohos'},
          nextCommand: 'fluoh doctor --platform ohos --project --json',
        ),
      );
      return WorkflowTargetResult.project(
        projectName: 'current',
        exitCode: 1,
        steps: steps,
        phase: 'build-$platform',
      );
    }
    output.step('Preparing temporary OHOS debug signing in current project');
    try {
      signingMaterial = await prepareOhosDebugSigning(
        environment: environment,
        ohosDirectory: ohosDirectory,
        output: output,
        usage: usage,
      );
    } on UsageException catch (error) {
      steps.add(
        _projectOhosDiagnosticStep(
          name: 'ohos-auto-sign',
          command: 'prepare OHOS debug signing',
          code: 'ohos.toolchain_missing',
          message: 'Could not locate the local OpenHarmony toolchain.',
          reason: error.message,
          details: {'error': error.message},
          nextCommand: 'fluoh doctor --platform ohos --json',
        ),
      );
      return WorkflowTargetResult.project(
        projectName: 'current',
        exitCode: 1,
        steps: steps,
        phase: 'build-$platform',
      );
    } on Object catch (error) {
      steps.add(
        _projectOhosDiagnosticStep(
          name: 'ohos-auto-sign',
          command: 'prepare OHOS debug signing',
          code: error is OhosSigningException
              ? 'ohos.signing_profile_failed'
              : 'ohos.auto_sign_failed',
          message: 'OHOS automatic debug signing failed.',
          reason: error.toString(),
          details: {'error': error.toString()},
          nextCommand: 'fluoh doctor --platform ohos --json',
        ),
      );
      return WorkflowTargetResult.project(
        projectName: 'current',
        exitCode: 1,
        steps: steps,
        phase: 'build-$platform',
      );
    }
    try {
      signingSession = await applyTemporaryOhosSigning(
        ohosDirectory: ohosDirectory,
        config: signingMaterial.signingConfig,
      );
    } on Object catch (error) {
      steps.add(
        _projectOhosDiagnosticStep(
          name: 'ohos-auto-sign',
          command: 'patch OHOS build-profile signing',
          code: 'ohos.build_profile_patch_failed',
          message: 'Could not patch OHOS build-profile signing.',
          reason: error.toString(),
          details: {
            ..._ohosSigningDetails(signingMaterial),
            'error': error.toString(),
          },
          nextCommand: 'fluoh build --platform ohos --auto-sign --json',
        ),
      );
      return WorkflowTargetResult.project(
        projectName: 'current',
        exitCode: 1,
        steps: steps,
        phase: 'build-$platform',
      );
    }
    signingMode = 'build-profile';
    signingSteps.add(
      WorkflowStepResult(
        name: 'ohos-auto-sign',
        path: '.',
        command: 'prepare OHOS debug signing',
        status: 'passed',
        exitCode: 0,
        details: _ohosSigningDetails(signingMaterial),
      ),
    );
    if (signingMaterial.permissionProfile.restrictedPermissions.isNotEmpty) {
      output.detail(
        'Restricted permissions: '
        '${signingMaterial.permissionProfile.restrictedPermissions.join(', ')}',
      );
    }
  }

  final arguments = [
    'build',
    _buildTargetForPlatform(platform),
    if (invocation.debug) '--debug',
    if (platform == 'ios') '--no-codesign',
  ];
  output.step('Running flutter ${arguments.join(' ')} in current project');
  final SelectedToolResult result;
  var effectiveExitCode = 1;
  var signedHaps = <File>[];
  var installableHaps = <File>[];
  final postBuildSteps = <WorkflowStepResult>[];
  try {
    final buildStartedAt = DateTime.now().subtract(const Duration(seconds: 1));
    result = await runSelectedFlutterResult(
      environment: environment,
      arguments: arguments,
      workingDirectory: project,
      stdout: stdout,
      stderr: stderr,
      output: output,
      usage: usage,
    );
    effectiveExitCode = result.exitCode;
    if (effectiveExitCode != 0 && signingMaterial != null) {
      output.step('Signing generated unsigned OHOS HAP in current project');
      try {
        signedHaps = await signGeneratedUnsignedHaps(
          environment: environment,
          exampleDirectory: project,
          signingMaterial: signingMaterial,
          output: output,
          modifiedAfter: buildStartedAt,
          usage: usage,
        );
      } on Object catch (error) {
        steps.addAll(signingSteps);
        steps.add(
          _projectOhosDiagnosticStep(
            name: 'ohos-direct-sign',
            command: 'sign generated unsigned OHOS HAP',
            code: 'ohos.direct_sign_failed',
            message: 'Could not directly sign generated unsigned OHOS HAP.',
            reason: error.toString(),
            details: {
              ..._ohosSigningDetails(signingMaterial),
              ..._toolOutputDetails(result),
              'error': error.toString(),
            },
            nextCommand: 'fluoh build --platform ohos --auto-sign --json',
          ),
        );
        return WorkflowTargetResult.project(
          projectName: 'current',
          exitCode: 1,
          steps: steps,
          phase: '${invocation.kind}-$platform',
        );
      }
      if (signedHaps.isNotEmpty) {
        output.warning(
          'Flutter HAP build failed during Hvigor signing; '
          'fluoh signed the generated unsigned HAP directly.',
        );
        signingMode = 'direct-sign-fallback';
        effectiveExitCode = 0;
        postBuildSteps.add(
          WorkflowStepResult(
            name: 'ohos-direct-sign',
            path: '.',
            command: 'sign generated unsigned OHOS HAP',
            status: 'passed',
            exitCode: 0,
            details: {
              ..._ohosSigningDetails(signingMaterial),
              'signedHaps': _filePaths(signedHaps),
            },
          ),
        );
      }
    }
    if (effectiveExitCode == 0 && platform == 'ohos') {
      await stabilizeOhosResourceLayout(ohosDirectory);
      installableHaps = await findInstallableOhosHaps(
        exampleDirectory: project,
        modifiedAfter: buildStartedAt,
      );
    }
  } finally {
    if (signingSession != null) {
      await signingSession.restore();
      output.detail('Restored ohos/build-profile.json5');
    }
  }
  steps.addAll(signingSteps);
  steps.addAll(postBuildSteps);
  steps.add(
    _toolStep(
      name: 'project-${invocation.kind}-$platform',
      path: '.',
      flutter: true,
      arguments: arguments,
      result: SelectedToolResult(
        exitCode: effectiveExitCode,
        stdout: result.stdout,
        stderr: result.stderr,
      ),
      diagnosticCode: _projectPlatformDiagnosticCode(
        kind: invocation.kind,
        platform: platform,
      ),
      diagnosticMessage: _projectPlatformDiagnosticMessage(
        kind: invocation.kind,
        platform: platform,
      ),
      nextCommand: _projectPlatformNextCommand(invocation),
      extraDetails: {
        if (installableHaps.isNotEmpty)
          'installableHaps': _filePaths(installableHaps),
        if (signingMode.isNotEmpty) 'signingMode': signingMode,
      },
    ),
  );
  return WorkflowTargetResult.project(
    projectName: 'current',
    exitCode: effectiveExitCode,
    steps: steps,
    phase: '${invocation.kind}-$platform',
  );
}

Future<WorkflowTargetResult> _runProjectOhosWorkflow({
  required FluohEnvironment environment,
  required Directory project,
  required TerminalOutput output,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required String usage,
  required _ProjectWorkflowInvocation invocation,
  required Duration deviceTimeout,
  required Duration logDuration,
}) async {
  final buildResult = await _runProjectWorkflow(
    environment: environment,
    output: output,
    stdout: stdout,
    stderr: stderr,
    usage: usage,
    invocation: const _ProjectWorkflowInvocation.build(
      platform: 'ohos',
      debug: true,
      autoSign: true,
    ),
    deviceTimeout: deviceTimeout,
    logDuration: logDuration,
  );
  final steps = [...buildResult.steps];
  if (!buildResult.passed) {
    return WorkflowTargetResult.project(
      projectName: 'current',
      exitCode: buildResult.exitCode,
      steps: steps,
      phase: 'run-ohos',
    );
  }

  final haps = _installableHapsFromBuildResult(buildResult);
  final ohosDirectory = Directory('${project.path}/ohos');
  final runResult = await runOhosHapsOnDevice(
    environment: environment,
    ohosDirectory: ohosDirectory,
    haps: haps,
    output: output,
    deviceId: invocation.deviceId,
    startEmulator: invocation.startEmulator,
    emulatorName: invocation.emulatorName,
    deviceTimeout: deviceTimeout,
    logDuration: logDuration,
    usage: usage,
  );
  final reasonParts = [
    if (runResult.reason != null) runResult.reason!,
    if (runResult.logFile != null) 'hilog: ${runResult.logFile!.path}',
    if (runResult.findings.isNotEmpty)
      'findings: ${runResult.findings.join(' | ')}',
  ];
  steps.add(
    WorkflowStepResult(
      name: 'project-run-ohos',
      path: '.',
      command: [
        'hdc',
        if (invocation.deviceId != null &&
            invocation.deviceId!.trim().isNotEmpty)
          '-t ${invocation.deviceId}',
        'install -r',
        '<hap>',
        '&&',
        'hdc',
        'shell aa start',
      ].join(' '),
      status: runResult.passed ? 'passed' : 'failed',
      exitCode: runResult.exitCode,
      reason: reasonParts.isEmpty ? null : reasonParts.join('\n'),
      details: {
        if (runResult.targetId != null) 'targetId': runResult.targetId,
        if (runResult.launchInfo != null)
          'launchInfo': {
            'bundleName': runResult.launchInfo!.bundleName,
            'moduleName': runResult.launchInfo!.moduleName,
            'abilityName': runResult.launchInfo!.abilityName,
          },
        if (runResult.logFile != null) 'hilog': runResult.logFile!.path,
        if (runResult.findings.isNotEmpty) 'findings': runResult.findings,
      },
      diagnostics: runResult.diagnostics
          .map(
            (diagnostic) => WorkflowDiagnostic(
              code: diagnostic.code,
              severity: diagnostic.severity,
              message: diagnostic.message,
              details: diagnostic.details,
              nextCommand: _projectNextCommandForDiagnosticCode(
                diagnostic.code,
                invocation,
              ),
            ),
          )
          .toList(),
    ),
  );
  if (runResult.passed && await hasIntegrationTests(project)) {
    steps.add(
      _projectOhosManualAssistedIntegrationStep(
        logFile: runResult.logFile,
        targetId: runResult.targetId,
      ),
    );
    output.next(
      'Complete the OHOS interaction manually, then verify logs or app status before marking interaction evidence passed',
    );
  }

  return WorkflowTargetResult.project(
    projectName: 'current',
    exitCode: runResult.exitCode,
    steps: steps,
    phase: 'run-ohos',
  );
}

List<File> _installableHapsFromBuildResult(WorkflowTargetResult result) {
  for (final step in result.steps.reversed) {
    final value = step.details['installableHaps'];
    if (value is List) {
      return [
        for (final item in value)
          if (item is String && item.trim().isNotEmpty) File(item),
      ];
    }
  }
  return const [];
}

WorkflowStepResult _projectIntegrationDiscoveryStep({
  required String name,
  required String path,
}) {
  return WorkflowStepResult(
    name: name,
    path: path,
    command: 'flutter test integration_test -d <device>',
    status: 'skipped',
    reason: 'requires a platform run target',
    details: {
      'testDirectory': 'integration_test',
      'interactionEvidence': {
        'status': 'available',
        'method': 'integration_test',
        'execution': 'run fluoh run with a concrete platform and device',
      },
      'suggestedCommands': [
        'fluoh run --platform ohos --auto-emulator --json',
        'fluoh run --platform android --auto-emulator --json',
        'fluoh run --platform ios --auto-emulator --json',
        'fluoh run --platform macos --json',
        'fluoh run --platform web --device chrome --json',
      ],
      'manualAssistedFallback': {
        'when':
            'system UI, permissions, pickers, external apps, or OHOS runner gaps block automatic execution',
        'requiredEvidence':
            'record user steps plus tool-verified logs, session status, stable text, semantics, or app log markers',
      },
    },
  );
}

Future<int?> _appendProjectIntegrationRunSteps({
  required FluohEnvironment environment,
  required Directory project,
  required String platform,
  required String? targetId,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required TerminalOutput output,
  required String usage,
  required List<WorkflowStepResult> steps,
  required String nextCommand,
}) async {
  if (!await hasIntegrationTests(project)) {
    return null;
  }
  if (platform == 'web' && targetId == 'web-server') {
    const reason = 'web-server target does not run browser integration tests';
    steps.add(
      WorkflowStepResult(
        name: 'project-integration-web',
        path: '.',
        command: 'flutter test integration_test -d <browser-device>',
        status: 'skipped',
        reason: reason,
        details: {
          'platform': platform,
          'targetId': targetId,
          'requiredTargetKind': 'browser',
          'suggestedDevice': 'chrome',
          'suggestedCommand': 'fluoh run --platform web --device chrome --json',
        },
      ),
    );
    output.skipped(
      'Skipping web integration tests in current project: $reason',
    );
    return null;
  }
  if (targetId == null) {
    steps.add(
      WorkflowStepResult(
        name: 'project-integration-$platform',
        path: '.',
        command: 'flutter test integration_test -d <device>',
        status: 'skipped',
        reason: 'run target did not expose a device id',
        details: {
          'platform': platform,
          'interactionEvidence': {
            'status': 'blocked',
            'method': 'integration_test',
            'reason': 'missing target id',
          },
        },
      ),
    );
    output.skipped(
      'Skipping $platform integration tests in current project: missing target id',
    );
    return null;
  }
  final arguments = ['test', 'integration_test', '-d', targetId];
  output.step('Running flutter ${arguments.join(' ')} in current project');
  final result = await runSelectedFlutterResult(
    environment: environment,
    arguments: arguments,
    workingDirectory: project,
    stdout: stdout,
    stderr: stderr,
    output: output,
    usage: usage,
  );
  final command = 'flutter ${arguments.join(' ')}';
  steps.add(
    WorkflowStepResult(
      name: 'project-integration-$platform',
      path: '.',
      command: command,
      status: result.exitCode == 0 ? 'passed' : 'failed',
      exitCode: result.exitCode,
      details: {
        'platform': platform,
        'targetId': targetId,
        'interactionEvidence': {
          'method': 'integration_test',
          'status': result.exitCode == 0 ? 'passed' : 'failed',
          'testDirectory': 'integration_test',
        },
        ..._toolOutputDetails(result),
      },
      diagnostics: result.exitCode == 0
          ? const []
          : [
              WorkflowDiagnostic(
                code: _projectIntegrationDiagnosticCode(platform),
                message:
                    '${_platformLabel(platform)} integration tests failed.',
                details: {
                  'command': command,
                  'exitCode': result.exitCode,
                  ..._toolOutputDetails(result),
                },
                nextCommand: nextCommand,
              ),
            ],
    ),
  );
  if (result.exitCode != 0) {
    output.failure(
      '${_platformLabel(platform)} integration tests failed in current project',
    );
    return result.exitCode;
  }
  output.success(
    '${_platformLabel(platform)} integration tests passed in current project',
  );
  return null;
}

WorkflowStepResult _projectOhosManualAssistedIntegrationStep({
  File? logFile,
  String? targetId,
}) {
  return WorkflowStepResult(
    name: 'project-integration-ohos',
    path: '.',
    command: 'flutter test integration_test -d <ohos-device>',
    status: 'skipped',
    reason:
        'OHOS integration_test automation is not available; manual-assisted interaction evidence is required.',
    details: {
      'testDirectory': 'integration_test',
      'targetId': ?targetId,
      'hilog': ?logFile?.path,
      'interactionEvidence': {
        'status': 'manual-required',
        'method': 'manual-assisted',
        'platform': 'ohos',
        'requiredUserAction':
            'complete the integration scenario on the OHOS emulator or device',
        'verification':
            'after user action, verify app state through hilog, stable text, semantic labels, test keys, or structured app logs',
      },
      'reportMethod': 'manual-assisted',
      'reportRequirement':
          'write an Interaction Evidence row with result passed only after tool-readable evidence confirms the user-completed flow',
    },
  );
}

String _projectIntegrationDiagnosticCode(String platform) {
  return switch (platform) {
    'android' => 'android.integration_test_failed',
    'ios' => 'ios.integration_test_failed',
    'macos' => 'macos.integration_test_failed',
    'linux' => 'linux.integration_test_failed',
    'web' => 'web.integration_test_failed',
    'windows' => 'windows.integration_test_failed',
    _ => 'integration_test.failed',
  };
}

String _platformLabel(String platform) {
  return switch (platform) {
    'ios' => 'iOS',
    'macos' => 'macOS',
    'ohos' => 'OHOS',
    'web' => 'Web',
    'linux' => 'Linux',
    'windows' => 'Windows',
    _ => 'Android',
  };
}

List<String> _filePaths(List<File> files) {
  return [for (final file in files) file.path];
}

WorkflowStepResult _toolStep({
  required String name,
  required String path,
  required bool flutter,
  required List<String> arguments,
  required SelectedToolResult result,
  String? diagnosticCode,
  String? diagnosticMessage,
  String? nextCommand,
  Map<String, Object?> extraDetails = const {},
}) {
  final command = '${flutter ? 'flutter' : 'dart'} ${arguments.join(' ')}';
  return WorkflowStepResult(
    name: name,
    path: path,
    command: command,
    status: result.exitCode == 0 ? 'passed' : 'failed',
    exitCode: result.exitCode,
    details: {..._toolOutputDetails(result), ...extraDetails},
    diagnostics: result.exitCode == 0
        ? const []
        : [
            WorkflowDiagnostic(
              code: diagnosticCode ?? 'command.failed',
              message: diagnosticMessage ?? 'Command failed.',
              details: {
                'command': command,
                'exitCode': result.exitCode,
                ..._toolOutputDetails(result),
              },
              nextCommand: nextCommand ?? 'fluoh verify --json',
            ),
          ],
  );
}

WorkflowStepResult _projectOhosDiagnosticStep({
  required String name,
  required String command,
  required String code,
  required String message,
  required String reason,
  required String nextCommand,
  Map<String, Object?> details = const {},
}) {
  return WorkflowStepResult(
    name: name,
    path: '.',
    command: command,
    status: 'failed',
    exitCode: 1,
    reason: reason,
    diagnostics: [
      WorkflowDiagnostic(
        code: code,
        message: message,
        details: details,
        nextCommand: nextCommand,
      ),
    ],
  );
}

Map<String, Object?> _ohosSigningDetails(
  OhosDebugSigningMaterial signingMaterial,
) {
  final profile = signingMaterial.permissionProfile;
  return {
    'bundleName': profile.bundleName,
    'requestedPermissions': profile.requestedPermissions,
    'restrictedPermissions': profile.restrictedPermissions,
    'apl': profile.apl,
    'signingConfig': signingMaterial.signingConfig.name,
    'profile': signingMaterial.signingConfig.profile,
  };
}

Map<String, Object?> _toolOutputDetails(SelectedToolResult result) {
  return {
    if (result.stdout.trim().isNotEmpty) 'stdoutTail': result.stdout,
    if (result.stderr.trim().isNotEmpty) 'stderrTail': result.stderr,
    if (result.combinedOutput.trim().isNotEmpty)
      'outputTail': result.combinedOutput,
  };
}

String _projectBaselineDiagnosticCode(String stepName) {
  return switch (stepName) {
    'project-pub-get' => 'dart.pub_get_failed',
    'project-analyze' => 'dart.analysis_failed',
    'project-test' => 'dart.test_failed',
    _ => 'command.failed',
  };
}

String _projectBaselineDiagnosticMessage(String stepName) {
  return switch (stepName) {
    'project-pub-get' => 'Dependency resolution failed.',
    'project-analyze' => 'Static analysis failed.',
    'project-test' => 'Tests failed.',
    _ => 'Command failed.',
  };
}

String _projectPlatformDiagnosticCode({
  required String kind,
  required String platform,
}) {
  if (kind == 'run') {
    return switch (platform) {
      'ohos' => 'ohos.run_failed',
      'android' => 'android.run_failed',
      'ios' => 'ios.run_failed',
      'macos' => 'macos.run_failed',
      'linux' => 'linux.run_failed',
      'web' => 'web.run_failed',
      'windows' => 'windows.run_failed',
      _ => 'command.failed',
    };
  }
  return switch (platform) {
    'ohos' => 'ohos.hap_build_failed',
    'android' => 'android.apk_build_failed',
    'ios' => 'ios.build_failed',
    'macos' => 'macos.build_failed',
    'linux' => 'linux.build_failed',
    'web' => 'web.build_failed',
    'windows' => 'windows.build_failed',
    _ => 'command.failed',
  };
}

String _projectPlatformDiagnosticMessage({
  required String kind,
  required String platform,
}) {
  if (kind == 'run') {
    return switch (platform) {
      'ohos' => 'OHOS run failed.',
      'android' => 'Android run failed.',
      'ios' => 'iOS run failed.',
      'macos' => 'macOS run failed.',
      'linux' => 'Linux run failed.',
      'web' => 'Web run failed.',
      'windows' => 'Windows run failed.',
      _ => 'Command failed.',
    };
  }
  return switch (platform) {
    'ohos' => 'OHOS HAP build failed.',
    'android' => 'Android APK build failed.',
    'ios' => 'iOS build failed.',
    'macos' => 'macOS build failed.',
    'linux' => 'Linux build failed.',
    'web' => 'Web build failed.',
    'windows' => 'Windows build failed.',
    _ => 'Command failed.',
  };
}

String _projectPlatformNextCommand(_ProjectWorkflowInvocation invocation) {
  final platform = invocation.platform!;
  if (invocation.kind == 'run') {
    return _projectRunNextCommand(invocation);
  }
  return [
    'fluoh build --platform $platform',
    if (!invocation.debug) '--no-debug',
    if (invocation.autoSign) '--auto-sign',
    '--json',
  ].join(' ');
}

String? _projectNextCommandForDiagnosticCode(
  String code,
  _ProjectWorkflowInvocation invocation,
) {
  final platform = invocation.platform!;
  final runCommand = _projectPlatformNextCommand(invocation);
  final autoEmulatorRunCommand = _projectRunNextCommand(
    invocation,
    startEmulator: true,
  );
  return switch (code) {
    'ohos.hap_build_failed' ||
    'ohos.launch_timeout' ||
    'ohos.run_failed' ||
    'ohos.runtime_crash' ||
    'android.apk_build_failed' ||
    'android.launch_timeout' ||
    'android.run_failed' ||
    'android.runtime_crash' ||
    'ios.build_failed' ||
    'ios.launch_timeout' ||
    'ios.run_failed' ||
    'ios.runtime_crash' ||
    'macos.build_failed' ||
    'macos.launch_timeout' ||
    'macos.run_failed' ||
    'macos.runtime_crash' ||
    'linux.build_failed' ||
    'linux.launch_timeout' ||
    'linux.run_failed' ||
    'linux.runtime_crash' ||
    'web.build_failed' ||
    'web.launch_timeout' ||
    'web.run_failed' ||
    'web.runtime_crash' ||
    'windows.build_failed' ||
    'windows.launch_timeout' ||
    'windows.run_failed' ||
    'windows.runtime_crash' => runCommand,
    'ohos.devices_failed' ||
    'ohos.hdc_connection_failed' ||
    'ohos.hdc_targets_failed' ||
    'ohos.emulators_failed' ||
    'ohos.emulator_missing' ||
    'ohos.emulator_start_failed' ||
    'android.devices_failed' ||
    'android.emulators_failed' ||
    'android.emulator_missing' ||
    'android.emulator_start_failed' ||
    'ios.devices_failed' ||
    'ios.emulators_failed' ||
    'ios.emulator_missing' ||
    'ios.emulator_start_failed' ||
    'macos.devices_failed' ||
    'macos.emulators_failed' ||
    'macos.emulator_missing' ||
    'macos.emulator_start_failed' ||
    'linux.devices_failed' ||
    'linux.emulators_failed' ||
    'linux.emulator_missing' ||
    'linux.emulator_start_failed' ||
    'web.devices_failed' ||
    'web.emulators_failed' ||
    'web.emulator_missing' ||
    'web.emulator_start_failed' ||
    'windows.devices_failed' ||
    'windows.emulators_failed' ||
    'windows.emulator_missing' ||
    'windows.emulator_start_failed' =>
      'fluoh doctor --platform $platform --json',
    'ohos.device_not_found' ||
    'ohos.device_ambiguous' ||
    'ohos.hdc_target_unavailable' ||
    'android.device_not_found' ||
    'android.device_ambiguous' ||
    'ios.device_not_found' ||
    'ios.device_ambiguous' ||
    'macos.device_not_found' ||
    'macos.device_ambiguous' ||
    'linux.device_not_found' ||
    'linux.device_ambiguous' ||
    'web.device_not_found' ||
    'web.device_ambiguous' ||
    'windows.device_not_found' ||
    'windows.device_ambiguous' => 'fluoh devices --platform $platform',
    'ohos.device_missing' ||
    'android.device_missing' ||
    'ios.device_missing' => autoEmulatorRunCommand,
    'ohos.emulator_not_found' ||
    'ohos.emulator_ambiguous' ||
    'android.emulator_not_found' ||
    'android.emulator_ambiguous' ||
    'ios.emulator_not_found' ||
    'ios.emulator_ambiguous' ||
    'macos.device_missing' ||
    'macos.emulator_not_found' ||
    'macos.emulator_ambiguous' ||
    'linux.device_missing' ||
    'linux.emulator_not_found' ||
    'linux.emulator_ambiguous' ||
    'web.device_missing' ||
    'web.emulator_not_found' ||
    'web.emulator_ambiguous' ||
    'windows.device_missing' ||
    'windows.emulator_not_found' ||
    'windows.emulator_ambiguous' => runCommand,
    _ => null,
  };
}

String _projectRunNextCommand(
  _ProjectWorkflowInvocation invocation, {
  bool? startEmulator,
}) {
  final platform = invocation.platform!;
  final useDefaultWebServer =
      platform == 'web' &&
      invocation.deviceId == null &&
      invocation.emulatorName == null;
  return [
    'fluoh run --platform $platform',
    if (invocation.deviceId != null) '--device ${invocation.deviceId}',
    if (useDefaultWebServer) '--device web-server',
    if ((startEmulator ?? invocation.startEmulator) &&
        invocation.emulatorName == null &&
        !_isDesktopRunPlatform(platform))
      '--auto-emulator',
    if (invocation.emulatorName != null)
      '--emulator ${invocation.emulatorName}',
    '--json',
  ].join(' ');
}

bool _isDesktopRunPlatform(String platform) {
  return platform == 'macos' ||
      platform == 'linux' ||
      platform == 'web' ||
      platform == 'windows';
}

int _lastExitCode(List<WorkflowStepResult> steps) {
  return steps.last.exitCode ?? 1;
}

String _platformFromBuildOption(String? value) {
  return switch (value) {
    'ohos' ||
    'android' ||
    'ios' ||
    'macos' ||
    'linux' ||
    'web' ||
    'windows' => value!,
    _ => throw ArgumentError.value(value, 'platform', 'Unsupported platform.'),
  };
}

String _buildTargetForPlatform(String platform) {
  return switch (platform) {
    'ohos' => 'hap',
    'android' => 'apk',
    'ios' => 'ios',
    'macos' => 'macos',
    'linux' => 'linux',
    'web' => 'web',
    'windows' => 'windows',
    _ => throw ArgumentError.value(
      platform,
      'platform',
      'Unsupported platform.',
    ),
  };
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
