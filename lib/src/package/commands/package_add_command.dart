import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../git/package_git.dart';
import '../manifest/package_manifest.dart';
import '../manifest/pubspec_package.dart';
import '../package_examples.dart';
import '../package_repository_docs.dart';

/// Creates another package adaptation branch in an existing repository.
class PackageAddCommand extends FluohCommand<int> {
  /// Creates the package add command.
  PackageAddCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _stderr = stderr,
       _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr) {
    argParser.addOption(
      'expected-package',
      valueHelp: 'name',
      help: 'Expected package name at <package-path>.',
    );
  }

  /// Runtime environment for repository and Flutter SDK operations.
  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  final TerminalOutput _output;

  @override
  String get name => 'add';

  @override
  String get description =>
      'Create another package adaptation branch in a FlutterOH repository.';

  @override
  String get invocation => 'fluoh package add <package-path>';

  @override
  Future<int> run() async {
    final rest = expectArgumentCount(
      argResults!,
      1,
      'Expected <package-path>.',
      usageException,
    );

    final repository = environment.workingDirectory;
    await ensureCleanWorkingTree(repository, 'Add package');
    final manifest = await readPackageManifest(repository);
    final startBranch = await currentBranch(repository);
    if (startBranch != manifest.branch) {
      usageException(
        'Current branch $startBranch does not match package branch '
        '${manifest.branch}.',
      );
    }
    final packagePath = rest.single;
    final selected = await _resolvePackageRef(
      repository: repository,
      packagePath: packagePath,
      upstreamBranch: manifest.upstreamBranch,
    );
    final expectedPackage = argResults!.option('expected-package');
    if (expectedPackage != null && selected.package.name != expectedPackage) {
      usageException(
        'Package at $packagePath is ${selected.package.name}, expected '
        '$expectedPackage.',
      );
    }

    final branch = flutterOhosPackageBranchForSdk(
      sdkVersion: manifest.sdkVersion,
      packageName: selected.package.name,
    );
    final existingBranch = await runGit(
      ['rev-parse', '--verify', branch],
      workingDirectory: repository,
      allowFailure: true,
    );
    if (existingBranch.exitCode == 0) {
      usageException('Package branch $branch already exists.');
    }

    var switchedBranches = false;
    var createdBranch = false;
    try {
      await runGit([
        'checkout',
        '--detach',
        selected.commit,
      ], workingDirectory: repository);
      switchedBranches = true;
      await runGit(['checkout', '-b', branch], workingDirectory: repository);
      createdBranch = true;

      final packageManifest = PackageManifest(
        sdkVersion: manifest.sdkVersion,
        repositoryBranch: branch,
        repositoryUrl: manifest.repositoryUrl,
        upstreamUrl: manifest.upstreamUrl,
        upstreamBranch: manifest.upstreamBranch,
        package: PackageManifestPackage(
          name: selected.package.name,
          path: packagePath,
          upstreamVersion: selected.package.version,
          upstreamRef: selected.ref,
          upstreamCommit: selected.commit,
          version: initialPackageReleaseVersion,
          status: 'experimental',
        ),
      );
      await writePackageManifestFile(repository, packageManifest);
      final docPackage = _docPackageForManifest(
        packageManifest.package,
        repositoryUrl: packageManifest.repositoryUrl,
      );
      await writeOrReplacePackageReadmeAdaptation(
        destination: repository,
        packages: [docPackage],
      );
      await writeOrReplacePackageImplementationGuide(
        destination: repository,
        packages: [docPackage],
      );
      await File('${repository.path}/FLUOH_CHANGELOG.md').writeAsString(
        packageFluohChangelogContent(
          packages: [docPackage],
          sdkVersion: manifest.sdkVersion,
          releaseVersion: initialPackageReleaseVersion,
        ),
      );
      await writeOrReplacePackageAgentsInstructions(
        destination: repository,
        packages: [docPackage],
      );

      final exampleSetupResult = await preparePackageExample(
        environment: environment,
        repository: repository,
        package: packageManifest.package,
        sdkVersion: manifest.sdkVersion,
        stdout: _stdout,
        stderr: _stderr,
        output: _output,
      );
      if (!exampleSetupResult.prepared && exampleSetupResult.reason != null) {
        _output.skipped(
          'Skipping example OHOS setup for ${exampleSetupResult.packageName}: '
          '${exampleSetupResult.reason}',
        );
      }

      await runGit([
        'add',
        '-f',
        'fluoh.yaml',
        'README.md',
        'FLUOH.md',
        'FLUOH_CHANGELOG.md',
        'AGENTS.md',
      ], workingDirectory: repository);
      if (exampleSetupResult.prepared) {
        await runGit([
          'add',
          '-A',
          packageRelativePath(repository, exampleSetupResult.example),
        ], workingDirectory: repository);
      }

      _output.success(
        'Created package branch $branch for ${selected.package.name}',
      );
      _output.next(
        'Implement OHOS support for ${selected.package.name}, then check it with '
        '"fluoh package check" and release it with "fluoh package release"',
      );
      return 0;
    } catch (_) {
      if (switchedBranches) {
        await _rollbackFailedPackageAdd(
          repository: repository,
          startBranch: startBranch,
          createdBranch: createdBranch ? branch : null,
        );
      }
      rethrow;
    }
  }
}

Future<void> _rollbackFailedPackageAdd({
  required Directory repository,
  required String startBranch,
  required String? createdBranch,
}) async {
  final status = await runGit(
    ['status', '--short'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (status.exitCode == 0 && status.stdout.toString().trim().isNotEmpty) {
    await runGit(['reset', '--hard'], workingDirectory: repository);
    await runGit(['clean', '-fd'], workingDirectory: repository);
  }
  await runGit(['checkout', startBranch], workingDirectory: repository);
  if (createdBranch != null) {
    await runGit(
      ['branch', '-D', createdBranch],
      workingDirectory: repository,
      allowFailure: true,
    );
  }
}

class _ResolvedPackageRef {
  const _ResolvedPackageRef({
    required this.package,
    required this.commit,
    this.ref,
  });

  final PubspecPackage package;
  final String commit;
  final String? ref;
}

Future<_ResolvedPackageRef> _resolvePackageRef({
  required Directory repository,
  required String packagePath,
  required String upstreamBranch,
}) async {
  final branchPackage = await _packageAtRef(
    repository: repository,
    ref: upstreamBranch,
    packagePath: packagePath,
  );
  if (branchPackage == null) {
    throw UsageException(
      'Missing pubspec.yaml at package path $packagePath on $upstreamBranch.',
      '',
    );
  }
  final tags = (await runGit([
    'tag',
    '--list',
  ], workingDirectory: repository)).stdout.toString().split('\n');
  final candidates = <_ResolvedPackageTag>[];
  for (final tag
      in tags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty)) {
    final pubspec = await _packageAtRef(
      repository: repository,
      ref: tag,
      packagePath: packagePath,
    );
    if (pubspec == null || pubspec.name != branchPackage.name) {
      continue;
    }
    if (_packageVersionFromReleaseTag(tag, pubspec.name) != pubspec.version) {
      continue;
    }
    try {
      candidates.add(
        _ResolvedPackageTag(
          package: pubspec,
          ref: tag,
          commit: await _revParseCommit(repository, tag),
          version: Version.parse(pubspec.version),
        ),
      );
    } on FormatException {
      continue;
    }
  }
  candidates.sort((a, b) {
    final version = a.version.compareTo(b.version);
    return version == 0 ? a.ref.compareTo(b.ref) : version;
  });
  if (candidates.isNotEmpty) {
    final latest = candidates.last;
    return _ResolvedPackageRef(
      package: latest.package,
      ref: latest.ref,
      commit: latest.commit,
    );
  }
  return _ResolvedPackageRef(
    package: branchPackage,
    commit: await _revParseCommit(repository, upstreamBranch),
  );
}

class _ResolvedPackageTag {
  const _ResolvedPackageTag({
    required this.package,
    required this.ref,
    required this.commit,
    required this.version,
  });

  final PubspecPackage package;
  final String ref;
  final String commit;
  final Version version;
}

Future<PubspecPackage?> _packageAtRef({
  required Directory repository,
  required String ref,
  required String packagePath,
}) async {
  final pubspecPath = packagePath == '.'
      ? 'pubspec.yaml'
      : '${_normalizePackagePath(packagePath)}/pubspec.yaml';
  final result = await runGit(
    ['show', '$ref:$pubspecPath'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (result.exitCode != 0) {
    return null;
  }
  try {
    return PubspecPackage.fromYaml(result.stdout.toString());
  } on FormatException {
    return null;
  }
}

String? _packageVersionFromReleaseTag(String tag, String packageName) {
  final escapedPackage = RegExp.escape(packageName);
  for (final pattern in [
    RegExp('^$escapedPackage-v(.+)\$'),
    RegExp('^$escapedPackage-(.+)\$'),
  ]) {
    final match = pattern.firstMatch(tag);
    if (match == null) {
      continue;
    }
    final version = match.group(1)!;
    try {
      Version.parse(version);
      return version;
    } on FormatException {
      continue;
    }
  }
  return null;
}

Future<String> _revParseCommit(Directory repository, String ref) async {
  final result = await runGit([
    'rev-parse',
    '$ref^{commit}',
  ], workingDirectory: repository);
  return result.stdout.toString().trim();
}

String _normalizePackagePath(String path) {
  final segments = path
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty && segment != '.')
      .toList(growable: false);
  return segments.isEmpty ? '.' : segments.join('/');
}

PackageRepositoryDocPackage _docPackageForManifest(
  PackageManifestPackage package, {
  required String repositoryUrl,
}) {
  return PackageRepositoryDocPackage(
    name: package.name,
    version: package.upstreamVersion,
    packagePath: package.path,
    repositoryUrl: repositoryUrl,
  );
}
