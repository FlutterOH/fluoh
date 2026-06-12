part of 'workflow_commands.dart';

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
