import 'dart:io';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../git/package_git.dart';
import '../manifest/package_manifest.dart';

/// Summarizes the current package adaptation branch for AI handoff.
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
    final branch = await currentBranch(environment.workingDirectory);
    final status = await runGit(
      ['status', '--short'],
      workingDirectory: environment.workingDirectory,
      allowFailure: true,
    );
    final latestTrace = await _latestTrace(
      environment.workingDirectory,
      package.name,
    );
    final traceDir = _traceCommandDirectory(
      environment.workingDirectory,
      package.name,
      latestTrace,
    );
    final reports = await _reportFiles(
      environment.workingDirectory,
      package.name,
    );
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
        if (latestTrace != null) 'latestTrace': latestTrace.path,
        'traceDir': traceDir,
        'reports': [for (final file in reports) file.path],
      },
      'nextCommands': _nextCommands(
        package.name,
        traceDir: traceDir,
        dirty: status.stdout.trim().isNotEmpty,
        manifestBranch: manifest.branch,
        branchMatchesManifest: branch == manifest.branch,
        hasReport: reports.isNotEmpty,
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
  required String traceDir,
  required bool dirty,
  required String manifestBranch,
  required bool branchMatchesManifest,
  required bool hasReport,
}) {
  if (!branchMatchesManifest) {
    return ['git switch $manifestBranch'];
  }
  if (dirty) {
    return ['git status --short', 'git diff --check'];
  }
  return [
    'fluoh verify --package $packageName --json --trace-dir $traceDir',
    'fluoh drive all --package $packageName --json --trace-dir $traceDir',
    if (!hasReport)
      'fluoh report create --scope $packageName --package $packageName --trace-dir $traceDir --json',
    'fluoh package check --package $packageName --json',
  ];
}

Future<File?> _latestTrace(Directory root, String packageName) async {
  final traces = Directory('${root.path}/.fluoh/traces/$packageName');
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

String _traceCommandDirectory(
  Directory root,
  String packageName,
  File? latestTrace,
) {
  if (latestTrace == null) {
    return '.fluoh/traces/$packageName/adaptation';
  }
  return _relativePath(root, latestTrace.parent);
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

Future<List<File>> _reportFiles(Directory root, String packageName) async {
  final reports = Directory('${root.path}/.fluoh/reports/$packageName');
  if (!await reports.exists()) {
    return const [];
  }
  final files = <File>[];
  await for (final entity in reports.list()) {
    if (entity is File && entity.path.endsWith('.md')) {
      files.add(entity);
    }
  }
  files.sort((a, b) => b.path.compareTo(a.path));
  return files;
}
