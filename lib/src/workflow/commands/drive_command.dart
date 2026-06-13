part of 'workflow_commands.dart';

/// Runs mobile scenarios for project and package targets.
class DriveCommand extends FluohCommand<int> {
  /// Creates the drive command.
  DriveCommand({
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
  String get name => 'drive';

  @override
  String get description =>
      'Run mobile scenario automation and collect evidence.';

  @override
  String get invocation =>
      '${runner?.executableName ?? 'fluoh'} drive <platform> [arguments]';

  @override
  Future<int> run() async {
    final platform = _platformArgument(
      argResults!,
      usageException,
      allowed: _drivePlatforms,
      label: 'drive',
    );
    final requestedAllPlatforms = platform == _allWorkflowPlatform;
    final packageName = _trimmedOption(argResults!, 'package');
    final deviceId = _trimmedOption(argResults!, 'device-id');
    final emulatorName = _trimmedOption(argResults!, 'emulator');
    final autoEmulator = deviceId == null && argResults!.flag('auto-emulator');
    if (deviceId != null && emulatorName != null) {
      usageException('Use only one of --device-id or --emulator.');
    }
    if (deviceId != null && requestedAllPlatforms) {
      usageException('Use --device-id with one drive platform.');
    }
    if (emulatorName != null && requestedAllPlatforms) {
      usageException('Use --emulator with one drive platform.');
    }
    final platforms = await _workflowPlatformsFromArgument(
      platform,
      environment: environment,
      packageName: packageName,
      candidates: _drivePlatforms,
      usage: usage,
    );
    final deviceTimeout = _durationOption('device-timeout');
    final logDuration = _durationOption('log-duration');
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
    );
    final plan = _automationPlan(
      platforms: platforms,
      packageName: packageName,
      requestedAllPlatforms: requestedAllPlatforms,
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
          command: 'drive',
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
      final platformScenarios = _automationScenariosForPlatform(
        scenarios,
        platform,
      );
      final platformResults = await _runPackageOrProject(
        environment: environment,
        packageName: packageName,
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
          scenarios: platformScenarios,
          platform: platform,
          environment: environment,
          output: output,
          packageName: packageName,
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
      command: 'drive',
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
