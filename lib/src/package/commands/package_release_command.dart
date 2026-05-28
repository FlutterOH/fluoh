import 'package:args/command_runner.dart';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../sdk/sdk_manager.dart';
import '../../workflow/workflow_result.dart';
import '../git/package_git.dart';
import '../manifest/package_manifest.dart';
import '../package_workflow_runner.dart';
import '../release_validator.dart';

class PackageReleaseCommand extends FluohCommand<int> {
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
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Validate and test the release without creating or pushing tags.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the release result as JSON.',
      );
  }

  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  late final TerminalOutput _output;

  @override
  String get name => 'release';

  @override
  String get description => 'Validate and tag FlutterOH package releases.';

  @override
  Future<int> run() async {
    final dryRun = argResults!.flag('dry-run');
    final json = argResults!.flag('json');
    final validations = <_PackageReleaseValidationResult>[];
    final tags = <String>[];
    var pushed = false;

    try {
      expectNoArguments(argResults!, usageException);
      if (argResults!.flag('all') &&
          (argResults!.option('package')?.trim().isNotEmpty ?? false)) {
        usageException('Use only one of --all or --package.');
      }
      final output = json
          ? TerminalOutput(stdout: (_) {}, stderr: (_) {})
          : _output;
      final OutputWriter stdout = json ? (_) {} : _stdout;
      final OutputWriter stderr = json ? (_) {} : _stderr;

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
          stdout: stdout,
          stderr: stderr,
          output: output,
        );
        validations.add(result);
        if (!result.verification.passed) {
          _printJsonIfRequested(
            json: json,
            dryRun: dryRun,
            pushed: false,
            validations: validations,
            tags: const [],
          );
          return result.verification.exitCode;
        }
      }
      if (dryRun) {
        for (final validation in validations) {
          tags.add(validation.tag);
          output.skipped('Would create release tag ${validation.tag}');
        }
      } else {
        for (final package in packages) {
          tags.add(
            await _createReleaseTag(
              manifest: manifest,
              package: package,
              output: output,
            ),
          );
        }
      }
      if (argResults!.flag('push')) {
        if (dryRun) {
          output.skipped(
            'Would push ${tags.length} release tag${_s(tags.length)}',
          );
        } else {
          await _pushReleaseTags(tags, output: output);
          pushed = true;
        }
      }
      if (dryRun) {
        output.success(
          'Release dry run passed for ${packages.length} package${_s(packages.length)}',
        );
      } else if (argResults!.flag('all')) {
        output.success(
          'Released ${packages.length} package${_s(packages.length)}',
        );
      }
      _printJsonIfRequested(
        json: json,
        dryRun: dryRun,
        pushed: pushed,
        validations: validations,
        tags: tags,
      );
      return 0;
    } on UsageException catch (error) {
      if (!json) {
        rethrow;
      }
      _printJsonIfRequested(
        json: true,
        dryRun: dryRun,
        pushed: pushed,
        validations: validations,
        tags: tags,
        exitCode: 64,
        errorType: 'usage',
        error: error.message,
      );
      return 64;
    } on FormatException catch (error) {
      if (!json) {
        rethrow;
      }
      _printJsonIfRequested(
        json: true,
        dryRun: dryRun,
        pushed: pushed,
        validations: validations,
        tags: tags,
        exitCode: 64,
        errorType: 'format',
        error: error.message,
      );
      return 64;
    }
  }

  Future<_PackageReleaseValidationResult> _validateAndTestPackage({
    required PackageManifest manifest,
    required PackageManifestPackage package,
    required OutputWriter stdout,
    required OutputWriter stderr,
    required TerminalOutput output,
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
      output.warningError(warning);
    }
    await _ensureReleaseTagIsUsable(tag: tag, package: package);

    final verifyCommand = manifest.packages.length == 1
        ? 'fluoh verify'
        : 'fluoh verify --package ${package.name}';
    output.step('Running $verifyCommand before release');
    final verificationResult = await runPackageWorkflow(
      environment: environment,
      manifest: manifest,
      package: package,
      stdout: stdout,
      stderr: stderr,
      output: output,
      usage: usage,
    );
    if (!verificationResult.passed) {
      return _PackageReleaseValidationResult(
        tag: tag,
        warnings: warnings,
        verification: verificationResult,
      );
    }
    await ensureCleanWorkingTree(environment.workingDirectory, 'Release');
    return _PackageReleaseValidationResult(
      tag: tag,
      warnings: warnings,
      verification: verificationResult,
    );
  }

  Future<String> _createReleaseTag({
    required PackageManifest manifest,
    required PackageManifestPackage package,
    required TerminalOutput output,
  }) async {
    final tag = package.releaseTag(manifest.sdkVersion);
    final existsAtHead = await _ensureReleaseTagIsUsable(
      tag: tag,
      package: package,
    );
    if (existsAtHead) {
      output.skipped('Release tag already exists: $tag');
      return tag;
    }

    await runGit(['tag', tag], workingDirectory: environment.workingDirectory);
    output.success('Created release tag $tag');
    return tag;
  }

  Future<void> _pushReleaseTags(
    List<String> tags, {
    required TerminalOutput output,
  }) async {
    if (tags.length == 1) {
      final tag = tags.single;
      await runGit([
        'push',
        'origin',
        tag,
      ], workingDirectory: environment.workingDirectory);
      output.success('Pushed release tag $tag');
      return;
    }

    await runGit([
      'push',
      '--atomic',
      'origin',
      ...tags,
    ], workingDirectory: environment.workingDirectory);
    output.success('Pushed ${tags.length} release tags');
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

  void _printJsonIfRequested({
    required bool json,
    required bool dryRun,
    required bool pushed,
    required List<_PackageReleaseValidationResult> validations,
    required List<String> tags,
    int? exitCode,
    String? errorType,
    String? error,
  }) {
    if (!json) {
      return;
    }
    final resolvedExitCode =
        exitCode ??
        validations
            .map((result) => result.verification.exitCode)
            .firstWhere((exitCode) => exitCode != 0, orElse: () => 0);
    final passed = resolvedExitCode == 0 && error == null;
    final result = {
      'passed': passed,
      'dryRun': dryRun,
      'pushed': pushed,
      'tags': tags,
      'packages': validations.map((result) => result.toJson()).toList(),
    };
    if (error != null) {
      result['error'] = {'type': errorType ?? 'error', 'message': error};
    }
    writeMachineOutput(
      _stdout,
      command: 'package release',
      ok: passed,
      exitCode: resolvedExitCode,
      fields: result,
    );
  }
}

String _s(int count) => count == 1 ? '' : 's';

class _PackageReleaseValidationResult {
  const _PackageReleaseValidationResult({
    required this.tag,
    required this.warnings,
    required this.verification,
  });

  final String tag;
  final List<String> warnings;
  final WorkflowTargetResult verification;

  Map<String, Object?> toJson() {
    return {
      'package': verification.targetName,
      'tag': tag,
      'warnings': warnings,
      'verification': verification.toJson(),
    };
  }
}
