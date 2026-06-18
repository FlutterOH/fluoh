import 'dart:io';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../task/task_workspace.dart';
import '../git/package_git.dart';
import '../manifest/package_manifest.dart';

/// Summarizes the current package support branch for AI handoff.
class PackageHandoffCommand extends FluohCommand<int> {
  /// Creates the package handoff command.
  PackageHandoffCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser
      ..addOption(
        'package',
        valueHelp: 'name',
        help: 'Package to summarize. Defaults to the current package branch.',
      )
      ..addFlag('json', negatable: false, help: 'Print handoff as JSON.');
  }

  /// Runtime environment.
  final FluohEnvironment environment;

  /// JSON output writer.
  final OutputWriter stdout;

  final TerminalOutput _output;

  @override
  String get name => 'handoff';

  @override
  String get description => 'Summarize package branch state for AI handoff.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final manifest = await readPackageManifest(environment.workingDirectory);
    final package = manifest.packageForName(argResults!.option('package'));
    final task = await TaskWorkspace(environment).resolveOrCreate(
      type: 'packageSupport',
      scopeName: package.name,
      packageName: package.name,
    );
    final branch = await currentBranch(environment.workingDirectory);
    final status = await runGit(
      ['status', '--short'],
      workingDirectory: environment.workingDirectory,
      allowFailure: true,
    );
    final latestTrace = await _latestTrace(task);
    final traceDir =
        '${task.relativePath(environment.workingDirectory)}/traces/support';
    final reports = await _reportFiles(task);
    final handoff = {
      'handoffSchema': 1,
      'kind': 'fluoh.packageHandoff',
      'repository': environment.workingDirectory.path,
      'branch': branch,
      'manifestBranch': manifest.branch,
      'branchMatchesManifest': branch == manifest.branch,
      'dirty': status.stdout.trim().isNotEmpty,
      'statusShort': [
        for (final line in status.stdout.toString().split('\n'))
          if (line.trim().isNotEmpty) line,
      ],
      'sdk': {'version': manifest.sdkVersion},
      'package': {
        'name': package.name,
        'path': package.path,
        'upstreamVersion': package.upstreamVersion,
        'upstreamRef': package.upstreamRef,
        'upstreamCommit': package.upstreamCommit,
        'releaseVersion': package.version,
        'releaseStatus': package.status,
      },
      'repositoryGit': {'url': manifest.repositoryUrl},
      'evidence': {
        'task': task.toJson(environment.workingDirectory),
        if (latestTrace != null) 'latestTrace': latestTrace.path,
        'traceDir': traceDir,
        'reports': [for (final file in reports) file.path],
        if (reports.isNotEmpty) 'latestReport': reports.first.path,
      },
      'nextCommands': _nextCommands(
        package.name,
        packageRoot: _packageRoot(environment.workingDirectory, package.path),
        traceDir: traceDir,
        dirty: status.stdout.trim().isNotEmpty,
        manifestBranch: manifest.branch,
        branchMatchesManifest: branch == manifest.branch,
        reportPath: reports.isEmpty ? null : reports.first.path,
      ),
    };
    if (argResults!.flag('json')) {
      writeMachineOutput(
        stdout,
        command: 'package handoff',
        ok: true,
        exitCode: 0,
        fields: handoff,
      );
    } else {
      _output.success('Package handoff');
      _output.info('Package: ${package.name}');
      _output.info('Branch: $branch');
      _output.info('Dirty: ${status.stdout.trim().isNotEmpty}');
      for (final command in handoff['nextCommands'] as List<Object?>) {
        _output.next(command as String);
      }
    }
    return 0;
  }
}

List<String> _nextCommands(
  String packageName, {
  required Directory packageRoot,
  required String traceDir,
  required bool dirty,
  required String manifestBranch,
  required bool branchMatchesManifest,
  required String? reportPath,
}) {
  if (!branchMatchesManifest) {
    return ['git switch $manifestBranch'];
  }
  if (dirty) {
    return ['git status --short', 'git diff --check'];
  }
  return [
    'fluoh package next --package $packageName --json',
    'fluoh verify --package $packageName --json --trace-dir $traceDir',
    ..._ohosCommands(packageName, traceDir),
    ..._driveCommands('ohos', packageName, traceDir),
    ..._examplePlatformCommands(
      packageName,
      packageRoot: packageRoot,
      traceDir: traceDir,
    ),
    if (reportPath == null) ...[
      'fluoh report create --scope $packageName --package $packageName --trace-dir $traceDir --json',
      'python3 <skill-dir>/scripts/check_report.py <report-path>',
    ] else
      'python3 <skill-dir>/scripts/check_report.py ${_shellQuote(reportPath)}',
    'fluoh package check --package $packageName --report ${_shellQuote(reportPath ?? '<report-path>')} --json',
  ];
}

List<String> _ohosCommands(String packageName, String traceDir) {
  return [
    'fluoh doctor --platform ohos --project --json --strict',
    'fluoh build ohos --package $packageName --auto-sign --json --trace-dir $traceDir',
    'fluoh devices --platform ohos --json',
    'fluoh emulators --platform ohos --json',
    'fluoh run ohos --package $packageName --auto-emulator --json --trace-dir $traceDir',
    'fluoh package next --package $packageName --json',
  ];
}

Directory _packageRoot(Directory repository, String packagePath) {
  if (packagePath == '.' || packagePath.isEmpty) {
    return repository;
  }
  return Directory('${repository.path}/$packagePath');
}

List<String> _examplePlatformCommands(
  String packageName, {
  required Directory packageRoot,
  required String traceDir,
}) {
  final example = Directory('${packageRoot.path}/example');
  final commands = <String>[];
  for (final platform in const [
    'android',
    'ios',
    'macos',
    'linux',
    'web',
    'windows',
  ]) {
    if (!Directory('${example.path}/$platform').existsSync() ||
        !_hostSupportsRegressionPlatform(platform)) {
      continue;
    }
    commands
      ..add('fluoh doctor --platform $platform --json --strict')
      ..add(_regressionCommand(platform, packageName, traceDir));
    if (_hostSupportsDrivePlatform(platform)) {
      commands.addAll(_driveCommands(platform, packageName, traceDir));
    }
  }
  return commands;
}

String _regressionCommand(
  String platform,
  String packageName,
  String traceDir,
) {
  if (platform == 'linux' || platform == 'windows') {
    return 'fluoh build $platform --package $packageName --json --trace-dir $traceDir';
  }
  final autoEmulator = platform == 'android' || platform == 'ios'
      ? ' --auto-emulator'
      : '';
  return 'fluoh run $platform --package $packageName$autoEmulator --json --trace-dir $traceDir';
}

String _driveCommand(String platform, String packageName, String traceDir) {
  return 'fluoh drive $platform --package $packageName --json --trace-dir $traceDir';
}

List<String> _driveCommands(
  String platform,
  String packageName,
  String traceDir,
) {
  return [
    'fluoh drive $platform --package $packageName --dry-run --json --trace-dir $traceDir',
    _driveCommand(platform, packageName, traceDir),
  ];
}

bool _hostSupportsDrivePlatform(String platform) {
  if (platform == 'android') {
    return true;
  }
  if (platform == 'ios') {
    return Platform.isMacOS;
  }
  return false;
}

bool _hostSupportsRegressionPlatform(String platform) {
  if (platform == 'ios' || platform == 'macos') {
    return Platform.isMacOS;
  }
  if (platform == 'linux') {
    return Platform.isLinux;
  }
  if (platform == 'windows') {
    return Platform.isWindows;
  }
  return true;
}

String _shellQuote(String value) {
  if (value.startsWith('<') && value.endsWith('>')) {
    return value;
  }
  if (RegExp(r'^[A-Za-z0-9_./:=@%+-]+$').hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", "'\"'\"'")}'";
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
    final modified = b.lastModifiedSync().compareTo(a.lastModifiedSync());
    if (modified != 0) {
      return modified;
    }
    return b.path.compareTo(a.path);
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
  final integer = RegExp(r'^report-(\d+)\.md$').firstMatch(name);
  return int.tryParse(integer?.group(1) ?? '') ?? 0;
}
