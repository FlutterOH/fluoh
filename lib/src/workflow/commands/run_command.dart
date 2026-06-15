part of 'workflow_commands.dart';

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
        'device-id',
        abbr: 'd',
        valueHelp: 'id',
        help: 'Connected device id.',
      )
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
            'Write a Flutter run session JSON file with platform launch evidence.',
      )
      ..addOption(
        'ohos-permission-dialog-policy',
        allowed: ohosSystemPermissionDialogPolicyValues,
        defaultsTo: 'disabled',
        help:
            'OHOS integration_test system permission dialog policy. Use allow only for grant-path tests.',
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
  String get invocation =>
      '${runner?.executableName ?? 'fluoh'} run <platform> [arguments]';

  @override
  Future<int> run() async {
    final platform = _platformArgument(
      argResults!,
      usageException,
      allowed: _buildRunPlatforms,
      label: 'run',
    );
    final requestedAllPlatforms = platform == _allWorkflowPlatform;
    final packageName = _trimmedOption(argResults!, 'package');
    if (_trimmedOption(argResults!, 'device-id') != null &&
        _trimmedOption(argResults!, 'emulator') != null) {
      usageException('Use only one of --device-id or --emulator.');
    }
    if (_trimmedOption(argResults!, 'device-id') != null &&
        argResults!.flag('auto-emulator')) {
      usageException('Use only one of --device-id or --auto-emulator.');
    }
    if (_trimmedOption(argResults!, 'emulator') != null &&
        argResults!.flag('auto-emulator')) {
      usageException('Use only one of --emulator or --auto-emulator.');
    }
    final deviceTimeout = _durationOption('device-timeout');
    final logDuration = _durationOption('log-duration');
    final deviceId = _trimmedOption(argResults!, 'device-id');
    final emulatorName = _trimmedOption(argResults!, 'emulator');
    final autoEmulator = argResults!.flag('auto-emulator');
    final ohosPermissionDialogPolicy = parseOhosSystemPermissionDialogPolicy(
      argResults!.option('ohos-permission-dialog-policy'),
    );
    if (requestedAllPlatforms && deviceId != null) {
      usageException('Use --device-id with one run platform.');
    }
    if (requestedAllPlatforms && emulatorName != null) {
      usageException('Use --emulator with one run platform.');
    }
    final sessionFilePath = _trimmedOption(argResults!, 'session-file');
    if (sessionFilePath != null && requestedAllPlatforms) {
      usageException(
        'Use --session-file with one run platform and one run target at a time.',
      );
    }
    final platforms = await _workflowPlatformsFromArgument(
      platform,
      environment: environment,
      packageName: packageName,
      candidates: _buildRunPlatforms,
      usage: usage,
    );
    if (sessionFilePath != null &&
        platforms.any(
          (platform) => !platformWorkflowPolicy(platform).supportsSessionFile,
        )) {
      usageException(
        'Use --session-file only with run platforms that support session evidence.',
      );
    }
    final sessionFile = sessionFilePath == null
        ? null
        : _resolveOutputFile(environment.workingDirectory, sessionFilePath);
    final json = argResults!.flag('json');
    final output = _outputFor(json, _output);
    final stdout = json ? (_) {} : _stdout;
    final stderr = json ? (_) {} : _stderr;
    final startEmulator = autoEmulator || emulatorName != null;
    final results = <WorkflowTargetResult>[];
    for (final currentPlatform in platforms) {
      final policy = platformWorkflowPolicy(currentPlatform);
      final invocation = _PackageWorkflowInvocation(
        phase: '$currentPlatform-run',
        buildExampleTarget: policy.runPrebuildTarget,
        runExampleTarget: policy.buildTarget,
        debug: true,
        buildExampleForSimulator: policy.buildExampleForSimulator(
          deviceId: deviceId,
          startEmulator: startEmulator,
        ),
        autoSign: policy.supportsAutoSign,
        runExample: true,
        deviceId: deviceId,
        startEmulator: startEmulator,
        emulatorName: emulatorName,
        sessionFile: sessionFile,
        ohosPermissionDialogPolicy: ohosPermissionDialogPolicy,
      );
      results.addAll(
        await _runPackageOrProject(
          environment: environment,
          packageName: packageName,
          output: output,
          stdout: stdout,
          stderr: stderr,
          usage: usage,
          invocationForPackage: (_) => invocation,
          projectInvocation: _ProjectWorkflowInvocation.run(
            platform: currentPlatform,
            deviceId: deviceId,
            startEmulator: startEmulator,
            emulatorName: emulatorName,
            sessionFile: sessionFile,
            autoSign: policy.supportsAutoSign,
            ohosPermissionDialogPolicy: ohosPermissionDialogPolicy,
          ),
          deviceTimeout: deviceTimeout,
          logDuration: logDuration,
        ),
      );
    }
    final traceResult = await _printWorkflowJson(
      json: json,
      stdout: _stdout,
      environment: environment,
      command: 'run',
      arguments: argResults!.arguments,
      results: results,
      traceOptions: _traceOptionsFrom(argResults!),
      extraFields: {
        'workflowEvidence': _runSmokeEvidence(
          platforms: platforms,
          results: results,
          packageName: packageName,
          requestedAllPlatforms: requestedAllPlatforms,
          autoEmulator: autoEmulator,
        ),
      },
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
