import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../schema/version_rules.dart';
import '../git/package_git.dart';
import '../manifest/package_manifest.dart';

/// Updates package release version metadata in `fluoh.yaml`.
///
/// This command is the maintainer-facing version bump step for FlutterOH
/// package adaptations. It changes only release metadata and leaves tag
/// creation to `fluoh package release`.
class PackageVersionCommand extends FluohCommand<int> {
  /// Creates the `fluoh package version` command.
  PackageVersionCommand({
    required this.environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _output = output ?? TerminalOutput(stdout: stdout) {
    argParser
      ..addOption(
        'package',
        valueHelp: 'name',
        help: 'Package to update. Defaults to the current package branch.',
      )
      ..addOption(
        'bump',
        allowed: const ['major', 'minor', 'patch'],
        help: 'Bump the FlutterOH adaptation package release version.',
      )
      ..addOption(
        'set',
        valueHelp: 'version',
        help: 'Set the FlutterOH adaptation package release version.',
      )
      ..addOption(
        'status',
        allowed: const ['experimental', 'compatible', 'broken'],
        help:
            'Set release status. compatible removes the status field from fluoh.yaml.',
      )
      ..addFlag(
        'dry-run',
        abbr: 'n',
        negatable: false,
        help: 'Print the planned version metadata change without writing.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the version metadata result as JSON.',
      );
  }

  /// Runtime environment used to locate and update the package repository.
  final FluohEnvironment environment;

  final OutputWriter _stdout;
  final TerminalOutput _output;

  @override
  String get name => 'version';

  @override
  String get description => 'Update package release version metadata.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final bump = _trimmedOption('bump');
    final set = _trimmedOption('set');
    final status = _trimmedOption('status');
    if (bump != null && set != null) {
      usageException('Use only one of --bump or --set.');
    }
    if (bump == null && set == null && status == null) {
      usageException('Pass --bump, --set, or --status.');
    }

    final manifest = await readPackageManifest(environment.workingDirectory);
    final package = manifest.packageForName(argResults!.option('package'));
    final nextVersion =
        set ?? (bump == null ? null : _bumped(package.version, bump));
    if (nextVersion != null) {
      validateReleaseVersion(nextVersion, label: '--set');
    }
    final nextStatus = status == 'compatible' ? null : status ?? package.status;
    final changes = <String, Object?>{};
    if (nextVersion != null && nextVersion != package.version) {
      changes['version'] = {'from': package.version, 'to': nextVersion};
    }
    if (status != null && nextStatus != package.status) {
      changes['status'] = {
        'from': package.status ?? 'compatible',
        'to': status,
      };
    }
    final dryRun = argResults!.flag('dry-run');
    final json = argResults!.flag('json');
    if (!dryRun && changes.isNotEmpty) {
      final branch = await currentBranch(environment.workingDirectory);
      if (branch != manifest.branch) {
        usageException(
          'Current branch $branch does not match package branch '
          '${manifest.branch}.',
        );
      }
      await ensureCleanWorkingTree(
        environment.workingDirectory,
        'Package version',
      );
      await writePackageManifestFile(
        environment.workingDirectory,
        updatePackageManifestRelease(
          manifest: manifest,
          packageName: package.name,
          version: nextVersion,
          status: status,
        ),
      );
    }

    if (json) {
      writeMachineOutput(
        _stdout,
        command: 'package version',
        ok: true,
        exitCode: 0,
        fields: {
          'package': package.name,
          'dryRun': dryRun,
          'changed': changes.isNotEmpty,
          'changes': changes,
          'version': nextVersion ?? package.version,
          'status': nextStatus,
        },
      );
      return 0;
    }

    if (changes.isEmpty) {
      _output.skipped('Package version metadata is already current');
      return 0;
    }
    final action = dryRun ? 'Would update' : 'Updated';
    if (changes.containsKey('version')) {
      final change = changes['version'] as Map<String, Object?>;
      _output.info(
        '$action ${package.name} version ${change['from']} -> ${change['to']}',
      );
    }
    if (changes.containsKey('status')) {
      final change = changes['status'] as Map<String, Object?>;
      _output.info(
        '$action ${package.name} status ${change['from']} -> ${change['to']}',
      );
    }
    if (!dryRun) {
      _output.next(
        'Update FLUOH_CHANGELOG.md, review fluoh.yaml, commit release metadata, then run '
        'fluoh package check --package ${package.name}',
      );
    }
    return 0;
  }

  String _bumped(String version, String bump) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(version);
    if (match == null) {
      usageException('Current package version $version is not semantic X.Y.Z.');
    }
    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    final patch = int.parse(match.group(3)!);
    return switch (bump) {
      'major' => '${major + 1}.0.0',
      'minor' => '$major.${minor + 1}.0',
      'patch' => '$major.$minor.${patch + 1}',
      _ => throw StateError('Unsupported bump $bump'),
    };
  }

  String? _trimmedOption(String name) {
    final value = argResults!.option(name)?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}
