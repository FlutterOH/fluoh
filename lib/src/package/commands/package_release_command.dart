import 'package:args/command_runner.dart';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../sdk/sdk_manager.dart';
import '../git/package_git.dart';
import '../manifest/package_manifest.dart';
import '../package_checker.dart';
import '../release_validator.dart';

class PackageReleaseCommand extends Command<int> {
  PackageReleaseCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _stderr = stderr {
    _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr);
    argParser
      ..addOption(
        'package',
        valueHelp: 'name',
        help: 'Package to release when fluoh.yaml registers multiple packages.',
      )
      ..addFlag(
        'all',
        negatable: false,
        help: 'Release every package registered in fluoh.yaml.',
      )
      ..addFlag(
        'push',
        negatable: false,
        help: 'Push the release tag to origin after creating or validating it.',
      );
  }

  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  late final TerminalOutput _output;

  @override
  String get name => 'release';

  @override
  String get description => 'Check and tag FlutterOH package releases.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    if (argResults!.flag('all') &&
        (argResults!.option('package')?.trim().isNotEmpty ?? false)) {
      usageException('Use only one of --all or --package.');
    }

    final manifest = await readPackageManifest(environment.workingDirectory);
    final branch = await currentBranch(environment.workingDirectory);
    if (branch != manifest.branch) {
      usageException(
        'Current branch $branch does not match package branch '
        '${manifest.branch}.',
      );
    }
    await ensureCleanWorkingTree(environment.workingDirectory, 'Release');
    await _ensureSdkVersionExists(manifest.sdkVersion);
    final packages = argResults!.flag('all')
        ? manifest.packages
        : [manifest.packageForName(argResults!.option('package'))];
    for (final package in packages) {
      final result = await _validateAndTestPackage(
        manifest: manifest,
        package: package,
      );
      if (result != 0) {
        return result;
      }
    }
    final tags = <String>[];
    for (final package in packages) {
      tags.add(await _createReleaseTag(manifest: manifest, package: package));
    }
    if (argResults!.flag('push')) {
      await _pushReleaseTags(tags);
    }
    if (argResults!.flag('all')) {
      _output.success(
        'Released ${packages.length} package${_s(packages.length)}.',
      );
    }
    return 0;
  }

  Future<int> _validateAndTestPackage({
    required PackageManifest manifest,
    required PackageManifestPackage package,
  }) async {
    final tag = package.releaseTag(manifest.sdkVersion);
    await validatePackageReleaseMetadata(
      repository: environment.workingDirectory,
      manifest: manifest,
      package: package,
      tag: tag,
    );
    final warnings = await packageReleaseMetadataWarnings(
      repository: environment.workingDirectory,
      manifest: manifest,
      package: package,
      tag: tag,
    );
    for (final warning in warnings) {
      _output.warningError(warning);
    }
    await _ensureReleaseTagIsUsable(tag: tag, package: package);

    final checkCommand = manifest.packages.length == 1
        ? 'fluoh package check'
        : 'fluoh package check --package ${package.name}';
    _output.step('Running $checkCommand before release.');
    final checkResult = await checkPackage(
      environment: environment,
      manifest: manifest,
      package: package,
      stdout: _stdout,
      stderr: _stderr,
      output: _output,
      usage: usage,
    );
    if (!checkResult.passed) {
      return checkResult.exitCode;
    }
    await ensureCleanWorkingTree(environment.workingDirectory, 'Release');
    return 0;
  }

  Future<String> _createReleaseTag({
    required PackageManifest manifest,
    required PackageManifestPackage package,
  }) async {
    final tag = package.releaseTag(manifest.sdkVersion);
    final existsAtHead = await _ensureReleaseTagIsUsable(
      tag: tag,
      package: package,
    );
    if (existsAtHead) {
      _output.skipped('Release tag already exists: $tag.');
      return tag;
    }

    await runGit(['tag', tag], workingDirectory: environment.workingDirectory);
    _output.success('Created release tag $tag.');
    return tag;
  }

  Future<void> _pushReleaseTags(List<String> tags) async {
    if (tags.length == 1) {
      final tag = tags.single;
      await runGit([
        'push',
        'origin',
        tag,
      ], workingDirectory: environment.workingDirectory);
      _output.success('Pushed release tag $tag.');
      return;
    }

    await runGit([
      'push',
      '--atomic',
      'origin',
      ...tags,
    ], workingDirectory: environment.workingDirectory);
    _output.success('Pushed ${tags.length} release tags.');
  }

  Future<bool> _ensureReleaseTagIsUsable({
    required String tag,
    required PackageManifestPackage package,
  }) async {
    final existing = (await runGit(
      ['tag', '--list', tag],
      workingDirectory: environment.workingDirectory,
    )).stdout.toString().trim();
    if (existing != tag) {
      return false;
    }

    final tagCommit = (await runGit(
      ['rev-parse', '$tag^{}'],
      workingDirectory: environment.workingDirectory,
    )).stdout.toString().trim();
    final headCommit = await currentHead(environment.workingDirectory);
    if (tagCommit != headCommit) {
      usageException(
        'Release tag $tag already exists on a different commit. '
        'Update fluoh.yaml release.version for ${package.name} before '
        'releasing new changes.',
      );
    }
    return true;
  }

  Future<void> _ensureSdkVersionExists(String sdkVersion) async {
    final releases = await SdkManager(environment).listReleases();
    if (!releases.any((release) => release.tag == sdkVersion)) {
      usageException(
        'SDK version $sdkVersion was not found in configured sources.',
      );
    }
  }
}

String _s(int count) => count == 1 ? '' : 's';
