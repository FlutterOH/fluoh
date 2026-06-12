part of 'workflow_commands.dart';

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
  String get invocation =>
      '${runner?.executableName ?? 'fluoh'} build <platform> [arguments]';

  @override
  Future<int> run() async {
    final platform = _platformArgument(
      argResults!,
      usageException,
      allowed: _buildRunPlatforms,
      label: 'build',
    );
    _validatePackageSelection(argResults!, usageException);
    final policy = platformWorkflowPolicy(platform);
    if (argResults!.flag('auto-sign') && !policy.supportsAutoSign) {
      usageException(
        'Use --auto-sign only with platforms that support automatic signing.',
      );
    }
    final json = argResults!.flag('json');
    final output = _outputFor(json, _output);
    final stdout = json ? (_) {} : _stdout;
    final stderr = json ? (_) {} : _stderr;
    final invocation = _PackageWorkflowInvocation(
      phase: '$platform-build',
      buildExampleTarget: policy.buildTarget,
      debug: argResults!.flag('debug'),
      autoSign: policy.supportsAutoSign && argResults!.flag('auto-sign'),
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
        autoSign: policy.supportsAutoSign && argResults!.flag('auto-sign'),
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
