import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../cli/argument_validation.dart';
import '../cli/fluoh_command_runner.dart';
import '../cli/machine_output.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import '../package/manifest/package_manifest.dart';
import '../package/package_workflow_runner.dart';
import '../package/package_examples.dart';
import '../sdk/flutter_runner.dart';
import 'workflow_result.dart';

class VerifyCommand extends FluohCommand<int> {
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
  }

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
    _printWorkflowJson(
      json: json,
      stdout: _stdout,
      command: 'verify',
      results: results,
    );
    final exitCode = _firstFailure(results);
    if (exitCode == 0 && !json) {
      output.success(_passedMessage('Verification', results.length));
    }
    return exitCode;
  }
}

class BuildCommand extends FluohCommand<int> {
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
        allowed: const ['ohos', 'android', 'ios'],
        mandatory: true,
        help: 'Platform to build.',
      )
      ..addFlag('debug', defaultsTo: true, help: 'Build a debug artifact.')
      ..addFlag(
        'auto-sign',
        negatable: false,
        help:
            'Generate temporary OHOS debug signing when building a package example.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the build result as JSON.',
      );
    _addPackageSelectionOptions(argParser);
  }

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
      ),
    );
    _printWorkflowJson(
      json: json,
      stdout: _stdout,
      command: 'build',
      results: results,
    );
    final exitCode = _firstFailure(results);
    if (exitCode == 0 && !json) {
      output.success(_passedMessage('Build', results.length));
    }
    return exitCode;
  }
}

class RunCommand extends FluohCommand<int> {
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
        allowed: const ['ohos', 'android', 'ios'],
        mandatory: true,
        help: 'Platform to run.',
      )
      ..addOption('device', valueHelp: 'id', help: 'Connected device id.')
      ..addOption(
        'emulator',
        valueHelp: 'name',
        help: 'Local emulator or simulator to start before running.',
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
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the run result as JSON.',
      );
    _addPackageSelectionOptions(argParser);
  }

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
    final deviceTimeout = _durationOption('device-timeout');
    final logDuration = _durationOption('log-duration');
    final platform = _platformFromBuildOption(argResults!.option('platform'));
    final deviceId = _trimmedOption(argResults!, 'device');
    final emulatorName = _trimmedOption(argResults!, 'emulator');
    final json = argResults!.flag('json');
    final output = _outputFor(json, _output);
    final stdout = json ? (_) {} : _stdout;
    final stderr = json ? (_) {} : _stderr;
    final invocation = _PackageWorkflowInvocation(
      phase: '$platform-run',
      buildExampleTarget: _buildTargetForPlatform(platform),
      debug: true,
      autoSign: platform == 'ohos',
      runExample: true,
      deviceId: deviceId,
      startEmulator: emulatorName != null,
      emulatorName: emulatorName,
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
      ),
      deviceTimeout: deviceTimeout,
      logDuration: logDuration,
    );
    _printWorkflowJson(
      json: json,
      stdout: _stdout,
      command: 'run',
      results: results,
    );
    final exitCode = _firstFailure(results);
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

void _addPackageSelectionOptions(ArgParser parser) {
  parser
    ..addOption(
      'package',
      valueHelp: 'name',
      help: 'Package to use when fluoh.yaml registers multiple packages.',
    )
    ..addFlag(
      'all',
      negatable: false,
      help: 'Run for every package registered in fluoh.yaml.',
    );
}

void _validatePackageSelection(ArgResults results, UsageError usageException) {
  if (results.flag('all') &&
      (results.option('package')?.trim().isNotEmpty ?? false)) {
    usageException('Use only one of --all or --package.');
  }
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
      ),
    ];
  }

  final packages = all
      ? manifest.packages
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
      autoSignExample: invocation.autoSign,
      runExample: invocation.runExample,
      deviceId: invocation.deviceId,
      startEmulator: invocation.startEmulator,
      emulatorName: invocation.emulatorName,
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
  return readPackageManifest(environment.workingDirectory);
}

class _PackageWorkflowInvocation {
  const _PackageWorkflowInvocation({
    required this.phase,
    this.buildExampleTarget,
    this.debug = false,
    this.autoSign = false,
    this.runExample = false,
    this.deviceId,
    this.startEmulator = false,
    this.emulatorName,
  });

  final String phase;
  final String? buildExampleTarget;
  final bool debug;
  final bool autoSign;
  final bool runExample;
  final String? deviceId;
  final bool startEmulator;
  final String? emulatorName;

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
      deviceId = null;

  const _ProjectWorkflowInvocation.build({
    required this.platform,
    required this.debug,
  }) : kind = 'build',
       deviceId = null;

  const _ProjectWorkflowInvocation.run({
    required this.platform,
    required this.deviceId,
  }) : kind = 'run',
       debug = true;

  final String kind;
  final String? platform;
  final bool debug;
  final String? deviceId;
}

Future<WorkflowTargetResult> _runProjectWorkflow({
  required FluohEnvironment environment,
  required TerminalOutput output,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required String usage,
  required _ProjectWorkflowInvocation invocation,
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
  final arguments = invocation.kind == 'build'
      ? [
          'build',
          _buildTargetForPlatform(platform),
          if (invocation.debug) '--debug',
          if (platform == 'ios') '--no-codesign',
        ]
      : [
          'run',
          if (invocation.deviceId != null) ...['-d', invocation.deviceId!],
          '--debug',
        ];
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
  steps.add(
    _toolStep(
      name: 'project-${invocation.kind}-$platform',
      path: '.',
      flutter: true,
      arguments: arguments,
      result: result,
    ),
  );
  return WorkflowTargetResult.project(
    projectName: 'current',
    exitCode: result.exitCode,
    steps: steps,
    phase: '${invocation.kind}-$platform',
  );
}

WorkflowStepResult _toolStep({
  required String name,
  required String path,
  required bool flutter,
  required List<String> arguments,
  required SelectedToolResult result,
}) {
  final command = '${flutter ? 'flutter' : 'dart'} ${arguments.join(' ')}';
  return WorkflowStepResult(
    name: name,
    path: path,
    command: command,
    status: result.exitCode == 0 ? 'passed' : 'failed',
    exitCode: result.exitCode,
    details: {
      if (result.stdout.trim().isNotEmpty) 'stdoutTail': result.stdout,
      if (result.stderr.trim().isNotEmpty) 'stderrTail': result.stderr,
      if (result.combinedOutput.trim().isNotEmpty)
        'outputTail': result.combinedOutput,
    },
    diagnostics: result.exitCode == 0
        ? const []
        : [
            WorkflowDiagnostic(
              code: 'command.failed',
              message: 'Command failed',
              details: {'command': command, 'exitCode': result.exitCode},
              nextCommand: 'fluoh verify --json',
            ),
          ],
  );
}

int _lastExitCode(List<WorkflowStepResult> steps) {
  return steps.last.exitCode ?? 1;
}

String _platformFromBuildOption(String? value) {
  return switch (value) {
    'ohos' || 'android' || 'ios' => value!,
    _ => throw ArgumentError.value(value, 'platform', 'Unsupported platform.'),
  };
}

String _buildTargetForPlatform(String platform) {
  return switch (platform) {
    'ohos' => 'hap',
    'android' => 'apk',
    'ios' => 'ios',
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

void _printWorkflowJson({
  required bool json,
  required OutputWriter stdout,
  required String command,
  required List<WorkflowTargetResult> results,
}) {
  if (!json) {
    return;
  }
  final exitCode = _firstFailure(results);
  writeMachineOutput(
    stdout,
    command: command,
    ok: exitCode == 0,
    exitCode: exitCode,
    fields: {'targets': results.map((result) => result.toJson()).toList()},
  );
}
