import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../cli/argument_validation.dart';
import '../cli/fluoh_command_runner.dart';
import '../cli/machine_output.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import '../platform/ohos/build_profile_signing.dart';
import '../platform/ohos/debug_signer.dart';
import '../platform/ohos/device_runner.dart';
import '../package/manifest/package_manifest.dart';
import '../package/flutter_example_runner.dart';
import '../package/package_workflow_runner.dart';
import '../package/package_examples.dart';
import '../schema/yaml_utils.dart';
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
        allowed: const ['ohos', 'android', 'ios', 'macos'],
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
        autoSign: platform == 'ohos' && argResults!.flag('auto-sign'),
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
        allowed: const ['ohos', 'android', 'ios', 'macos'],
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
        startEmulator: emulatorName != null,
        emulatorName: emulatorName,
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
        deviceTimeout: deviceTimeout,
        logDuration: logDuration,
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
      autoSign = false,
      deviceId = null,
      startEmulator = false,
      emulatorName = null;

  const _ProjectWorkflowInvocation.build({
    required this.platform,
    required this.debug,
    required this.autoSign,
  }) : kind = 'build',
       deviceId = null,
       startEmulator = false,
       emulatorName = null;

  const _ProjectWorkflowInvocation.run({
    required this.platform,
    required this.deviceId,
    required this.startEmulator,
    required this.emulatorName,
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
    return WorkflowTargetResult.project(
      projectName: 'current',
      exitCode: runResult.exitCode,
      steps: steps,
      phase: 'run-$platform',
    );
  }

  final signingSteps = <WorkflowStepResult>[];
  OhosBuildProfileSigningSession? signingSession;
  OhosDebugSigningMaterial? signingMaterial;
  var signingMode = '';
  if (invocation.autoSign) {
    final ohosDirectory = Directory('${project.path}/ohos');
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
      _ => 'command.failed',
    };
  }
  return switch (platform) {
    'ohos' => 'ohos.hap_build_failed',
    'android' => 'android.apk_build_failed',
    'ios' => 'ios.build_failed',
    'macos' => 'macos.build_failed',
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
      _ => 'Command failed.',
    };
  }
  return switch (platform) {
    'ohos' => 'OHOS HAP build failed.',
    'android' => 'Android APK build failed.',
    'ios' => 'iOS build failed.',
    'macos' => 'macOS build failed.',
    _ => 'Command failed.',
  };
}

String _projectPlatformNextCommand(_ProjectWorkflowInvocation invocation) {
  final platform = invocation.platform!;
  if (invocation.kind == 'run') {
    return [
      'fluoh run --platform $platform',
      if (invocation.deviceId != null) '--device ${invocation.deviceId}',
      if (invocation.emulatorName != null)
        '--emulator ${invocation.emulatorName}',
      '--json',
    ].join(' ');
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
    'macos.runtime_crash' => runCommand,
    'ohos.devices_failed' ||
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
    'macos.emulator_start_failed' => 'fluoh doctor --platform $platform --json',
    'ohos.device_not_found' ||
    'ohos.device_ambiguous' ||
    'android.device_not_found' ||
    'android.device_ambiguous' ||
    'ios.device_not_found' ||
    'ios.device_ambiguous' ||
    'macos.device_not_found' ||
    'macos.device_ambiguous' => 'fluoh devices --platform $platform',
    'ohos.device_missing' ||
    'ohos.emulator_not_found' ||
    'ohos.emulator_ambiguous' ||
    'android.device_missing' ||
    'android.emulator_not_found' ||
    'android.emulator_ambiguous' ||
    'ios.device_missing' ||
    'ios.emulator_not_found' ||
    'ios.emulator_ambiguous' ||
    'macos.device_missing' ||
    'macos.emulator_not_found' ||
    'macos.emulator_ambiguous' => runCommand,
    _ => null,
  };
}

int _lastExitCode(List<WorkflowStepResult> steps) {
  return steps.last.exitCode ?? 1;
}

String _platformFromBuildOption(String? value) {
  return switch (value) {
    'ohos' || 'android' || 'ios' || 'macos' => value!,
    _ => throw ArgumentError.value(value, 'platform', 'Unsupported platform.'),
  };
}

String _buildTargetForPlatform(String platform) {
  return switch (platform) {
    'ohos' => 'hap',
    'android' => 'apk',
    'ios' => 'ios',
    'macos' => 'macos',
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
