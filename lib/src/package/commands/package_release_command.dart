import 'dart:io';

import 'package:args/command_runner.dart';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../sdk/sdk_manager.dart';
import '../../workflow/workflow_result.dart';
import '../certification_report.dart';
import '../git/package_git.dart';
import '../manifest/package_manifest.dart';
import '../package_workflow_runner.dart';
import '../release_validator.dart';

/// Selects whether the shared release command implementation checks or releases.
///
/// `check` runs the release gate without creating tags. `release` runs the same
/// validation path and then creates the release tag, optionally pushing it.
enum PackageReleaseCommandKind {
  /// Validate the package without creating release tags.
  check,

  /// Validate the package, create a release tag, and optionally push it.
  release,
}

/// Runs package release validation or completes a package release.
///
/// The command is intentionally shared between `fluoh package check` and
/// `fluoh package release` so both paths use the same validation, workflow, and
/// JSON output contract. Only the `release` kind creates or pushes Git tags.
class PackageReleaseCommand extends FluohCommand<int> {
  /// Creates a package check or release command.
  PackageReleaseCommand({
    required this.kind,
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
        help: kind == PackageReleaseCommandKind.check
            ? 'Package to check. Defaults to the current package branch.'
            : 'Package to release. Defaults to the current package branch.',
      )
      ..addFlag('json', negatable: false, help: 'Print the result as JSON.')
      ..addOption(
        'report',
        valueHelp: 'path',
        help: kind == PackageReleaseCommandKind.check
            ? 'Require a completed fluoh AI certification report before passing the check.'
            : 'Require a completed fluoh AI certification report before release.',
      )
      ..addFlag(
        'require-ohos-run',
        negatable: false,
        help:
            'Require OHOS run evidence in the certification report. '
            'Use with --report.',
      );
    if (kind != PackageReleaseCommandKind.check) {
      argParser.addFlag(
        'push',
        negatable: false,
        help: 'Push the release tag to origin after creating it.',
      );
    }
  }

  /// Command behavior mode.
  final PackageReleaseCommandKind kind;

  /// Runtime environment used for repository, SDK, and process access.
  final FluohEnvironment environment;

  final OutputWriter _stdout;
  final OutputWriter _stderr;
  late final TerminalOutput _output;

  @override
  String get name {
    return switch (kind) {
      PackageReleaseCommandKind.check => 'check',
      PackageReleaseCommandKind.release => 'release',
    };
  }

  @override
  String get description {
    return switch (kind) {
      PackageReleaseCommandKind.check =>
        'Run package release checks without creating tags.',
      PackageReleaseCommandKind.release =>
        'Complete a FlutterOH package release.',
    };
  }

  @override
  Future<int> run() async {
    final dryRun = kind == PackageReleaseCommandKind.check;
    final json = argResults!.flag('json');
    final validations = <_PackageReleaseValidationResult>[];
    final tags = <String>[];
    var pushed = false;

    try {
      expectNoArguments(argResults!, usageException);
      final certificationReport = _trimmedOption('report');
      final requireOhosRun = argResults!.flag('require-ohos-run');
      if (requireOhosRun && certificationReport == null) {
        usageException('Use --require-ohos-run with --report <path>.');
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
      await ensureCleanWorkingTree(
        environment.workingDirectory,
        _cleanTreeLabel,
      );
      await _ensureSdkVersionExists(manifest.sdkVersion);
      final packages = [manifest.packageForName(argResults!.option('package'))];
      for (final package in packages) {
        final result = await _validateAndTestPackage(
          manifest: manifest,
          package: package,
          certificationReport: certificationReport,
          requireOhosRun: requireOhosRun,
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
      if (_pushRequested) {
        if (dryRun) {
          output.skipped(
            'Would push ${tags.length} release tag${_s(tags.length)}',
          );
        } else {
          await _pushReleaseTags(tags, output: output);
          pushed = true;
        }
      }
      if (kind == PackageReleaseCommandKind.check) {
        output.success(
          'Package release check passed for ${packages.length} package${_s(packages.length)}',
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
    required String? certificationReport,
    required bool requireOhosRun,
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
    final certification = await _certificationResult(
      package: package,
      certificationReport: certificationReport,
      requireOhosRun: requireOhosRun,
    );
    if (certificationReport == null) {
      output.warning(
        'No certification report provided; release will use baseline checks only.',
      );
    } else if (!certification.ok) {
      usageException(
        [
          'Certification report did not pass for ${package.name}.',
          ...certification.errors,
        ].join('\n'),
      );
    } else {
      output.success('Certification report passed for ${package.name}');
      for (final warning in certification.warnings) {
        output.warning(warning);
      }
    }
    await _ensureReleaseTagIsUsable(tag: tag, package: package);

    output.step('Running fluoh verify as package release verification');
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
        certification: certification,
        verification: verificationResult,
      );
    }
    await ensureCleanWorkingTree(environment.workingDirectory, _cleanTreeLabel);
    return _PackageReleaseValidationResult(
      tag: tag,
      warnings: warnings,
      certification: certification,
      verification: verificationResult,
    );
  }

  Future<PackageCertificationReportResult> _certificationResult({
    required PackageManifestPackage package,
    required String? certificationReport,
    required bool requireOhosRun,
  }) async {
    if (certificationReport == null) {
      return PackageCertificationReportResult(
        reportPath: '',
        requiredReport: false,
        certified: false,
        ok: true,
        recommendation: null,
        commandRows: 0,
        passedCommandRows: 0,
        coveragePolicyStatus: null,
        readyForAutomation: null,
        qualityGateSummary: null,
        automationCoverageRows: 0,
        readyAutomationCoverageRows: 0,
        interactionRows: 0,
        passedInteractionRows: 0,
        passedMobileRunOrDrive: false,
        postLaunchVisualEvidence: false,
        errors: const [],
        warnings: const [
          'No certification report provided; baseline release checks only.',
        ],
      );
    }
    return validatePackageCertificationReport(
      report: _resolveReportFile(certificationReport),
      packageName: package.name,
      requireOhosRun: requireOhosRun,
    );
  }

  File _resolveReportFile(String path) {
    final file = File(path);
    if (file.isAbsolute) {
      return file;
    }
    return File('${environment.workingDirectory.path}/$path');
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
        'Run fluoh package version --package ${package.name} before '
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
      command: 'package $name',
      ok: passed,
      exitCode: resolvedExitCode,
      fields: result,
    );
  }

  String? _trimmedOption(String name) {
    final value = argResults!.option(name)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  bool get _pushRequested {
    return kind != PackageReleaseCommandKind.check &&
        argResults!.wasParsed('push') &&
        argResults!.flag('push');
  }

  String get _cleanTreeLabel {
    return kind == PackageReleaseCommandKind.check
        ? 'Package check'
        : 'Release';
  }
}

String _s(int count) => count == 1 ? '' : 's';

class _PackageReleaseValidationResult {
  const _PackageReleaseValidationResult({
    required this.tag,
    required this.warnings,
    required this.certification,
    required this.verification,
  });

  final String tag;
  final List<String> warnings;
  final PackageCertificationReportResult certification;
  final WorkflowTargetResult verification;

  Map<String, Object?> toJson() {
    return {
      'package': verification.targetName,
      'tag': tag,
      'warnings': warnings,
      'certification': certification.toJson(),
      'verification': verification.toJson(),
    };
  }
}
