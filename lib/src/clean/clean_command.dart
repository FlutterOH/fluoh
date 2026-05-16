import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/argument_validation.dart';
import '../cli/fluoh_command_runner.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import '../pub/manifest/pub_manifest.dart';
import '../pub/manifest/pubspec_package.dart';
import '../sdk/flutter_runner.dart';
import '../testing/test_workspace.dart';

class CleanCommand extends Command<int> {
  CleanCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
    bool inheritStdio = false,
  }) : _stdout = stdout,
       _stderr = stderr,
       _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr),
       _inheritStdio = inheritStdio;

  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  final TerminalOutput _output;
  final bool _inheritStdio;

  @override
  String get name => 'clean';

  @override
  String get description =>
      'Clean FlutterOH project build output and fluoh_test artifacts.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    for (final packageDirectory in await _primaryPackageDirectories()) {
      _output.step(
        'Running flutter clean in ${_relativePath(packageDirectory)}',
      );
      final cleanResult = await runSelectedFlutter(
        environment: environment,
        arguments: const ['clean'],
        workingDirectory: packageDirectory,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
        inheritStdio: _inheritStdio,
        usage: usage,
      );
      if (cleanResult != 0) {
        _output.failure('flutter clean failed.');
        return cleanResult;
      }
    }

    final summary = await _cleanFluohTestArtifacts(
      environment.workingDirectory,
    );
    for (final path in summary.skippedTracked) {
      _output.warning('Skipped tracked fluoh_test artifact: $path.');
    }
    if (summary.removed.isNotEmpty) {
      _output.success(
        'Removed ${summary.removed.length} fluoh_test '
        'artifact${_s(summary.removed.length)}.',
      );
      for (final path in summary.removed) {
        _output.detail(path);
      }
      return 0;
    }

    if (summary.missingFluohTest) {
      _output.skipped('No fluoh_test directory found.');
    } else {
      _output.skipped('No fluoh_test artifacts found.');
    }
    return 0;
  }

  Future<List<Directory>> _primaryPackageDirectories() async {
    try {
      final manifest = await readPubManifest(environment.workingDirectory);
      return [
        for (final package in manifest.packages)
          packageDirectory(
            environment.workingDirectory,
            package.dependencyPath,
          ),
      ];
    } on UsageException catch (error) {
      if (!_isProjectFluohConfig(error)) {
        rethrow;
      }
    }
    return [environment.workingDirectory];
  }

  bool _isProjectFluohConfig(UsageException error) {
    final message = error.message;
    return const {
          'Missing fluoh.yaml.',
          'fluoh.yaml missing "repository".',
          'fluoh.yaml missing "packages".',
          'fluoh.yaml missing "upstream".',
          'Expected "name" to be a non-empty string.',
          'Expected fluoh.yaml repository.git to be a YAML object.',
        }.contains(message) ||
        message.contains('must not contain "dependencyPolicy"');
  }

  String _relativePath(Directory directory) {
    final rawRoot = environment.workingDirectory.path;
    final rawPath = directory.path;
    if (rawPath == rawRoot) {
      return '.';
    }
    if (rawPath.startsWith('$rawRoot${Platform.pathSeparator}')) {
      return rawPath.substring(rawRoot.length + 1);
    }

    final root = environment.workingDirectory.absolute.path;
    final path = directory.absolute.path;
    if (path == root) {
      return '.';
    }
    if (path.startsWith('$root${Platform.pathSeparator}')) {
      return path.substring(root.length + 1);
    }
    return path;
  }
}

class _CleanSummary {
  const _CleanSummary({
    required this.missingFluohTest,
    required this.removed,
    required this.skippedTracked,
  });

  final bool missingFluohTest;
  final List<String> removed;
  final List<String> skippedTracked;
}

Future<_CleanSummary> _cleanFluohTestArtifacts(Directory repository) async {
  final artifactRoots = await _fluohTestArtifactRoots(repository);
  if (!await Directory(_join(repository.path, 'fluoh_test')).exists()) {
    return const _CleanSummary(
      missingFluohTest: true,
      removed: [],
      skippedTracked: [],
    );
  }

  final tracked = await _trackedFiles(repository);
  final removed = <String>[];
  final skippedTracked = <String>[];
  for (final artifactRoot in artifactRoots) {
    for (final artifact in _fluohTestArtifactPaths) {
      final relativePath = '$artifactRoot/$artifact';
      final path = _join(repository.path, relativePath);
      if (!await _exists(path)) {
        continue;
      }
      if (_containsTrackedFile(tracked, relativePath)) {
        skippedTracked.add(relativePath);
        continue;
      }
      await _delete(path);
      removed.add(relativePath);
    }
  }

  return _CleanSummary(
    missingFluohTest: false,
    removed: removed,
    skippedTracked: skippedTracked,
  );
}

Future<List<String>> _fluohTestArtifactRoots(Directory repository) async {
  final directories = await fluohTestWorkspaceDirectories(repository);
  final roots = <String>[];
  final seen = <String>{};
  for (final directory in directories) {
    if (directory.path.endsWith('${Platform.pathSeparator}example')) {
      continue;
    }
    final relativePath = _relativePath(repository, directory);
    if (relativePath.startsWith('fluoh_test') && seen.add(relativePath)) {
      roots.add(relativePath);
    }
  }
  if (roots.isEmpty) {
    roots.add('fluoh_test');
  }
  return roots;
}

const _fluohTestArtifactPaths = [
  '.dart_tool',
  '.flutter-plugins',
  '.flutter-plugins-dependencies',
  '.packages',
  '.pub',
  '.pub-cache',
  'build',
  'coverage',
  'local.properties',
  'example/.dart_tool',
  'example/.flutter-plugins',
  'example/.flutter-plugins-dependencies',
  'example/.packages',
  'example/.pub',
  'example/.pub-cache',
  'example/build',
  'example/coverage',
  'example/local.properties',
];

Future<Set<String>> _trackedFiles(Directory repository) async {
  try {
    final result = await Process.run('git', [
      'ls-files',
      '--',
      'fluoh_test',
    ], workingDirectory: repository.path);
    if (result.exitCode != 0) {
      return const {};
    }
    return result.stdout
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toSet();
  } on ProcessException {
    return const {};
  }
}

bool _containsTrackedFile(Set<String> trackedFiles, String relativePath) {
  return trackedFiles.any(
    (path) => path == relativePath || path.startsWith('$relativePath/'),
  );
}

Future<bool> _exists(String path) async {
  return await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;
}

Future<void> _delete(String path) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  switch (type) {
    case FileSystemEntityType.directory:
      await Directory(path).delete(recursive: true);
    case FileSystemEntityType.file:
      await File(path).delete();
    case FileSystemEntityType.link:
      await Link(path).delete();
    case FileSystemEntityType.notFound:
      return;
    case FileSystemEntityType.pipe:
      await File(path).delete();
    case FileSystemEntityType.unixDomainSock:
      await File(path).delete();
  }
}

String _join(String root, String relativePath) {
  return [root, ...relativePath.split('/')].join(Platform.pathSeparator);
}

String _relativePath(Directory rootDirectory, Directory directory) {
  final root = rootDirectory.absolute.path;
  final path = directory.absolute.path;
  if (path == root) {
    return '.';
  }
  if (path.startsWith('$root${Platform.pathSeparator}')) {
    return path.substring(root.length + 1);
  }
  return path;
}

String _s(int count) => count == 1 ? '' : 's';
