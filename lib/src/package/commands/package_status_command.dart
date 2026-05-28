import 'dart:io';

import 'package:args/command_runner.dart';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../git/package_git.dart';
import '../manifest/package_manifest.dart';
import '../manifest/pubspec_package.dart';
import '../package_examples.dart';
import '../release_validator.dart';

class PackageStatusCommand extends FluohCommand<int> {
  PackageStatusCommand({
    required this.environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _output = output ?? TerminalOutput(stdout: stdout) {
    argParser
      ..addOption(
        'package',
        valueHelp: 'name',
        help: 'Package to inspect when fluoh.yaml registers multiple packages.',
      )
      ..addFlag(
        'all',
        negatable: false,
        help: 'Inspect every package registered in fluoh.yaml.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print package status as JSON.',
      );
  }

  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final TerminalOutput _output;

  @override
  String get name => 'status';

  @override
  String get description => 'Summarize package release readiness.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    if (argResults!.flag('all') &&
        (argResults!.option('package')?.trim().isNotEmpty ?? false)) {
      usageException('Use only one of --all or --package.');
    }

    final repository = environment.workingDirectory;
    final manifest = await readPackageManifest(repository);
    final packages = argResults!.flag('all')
        ? manifest.packages
        : [manifest.packageForName(argResults!.option('package'))];
    final branch = await currentBranch(repository);
    final dirtyFiles = await _dirtyFiles(repository);
    final localPathFiles = await _trackedFilesContaining(
      repository,
      environment.homeDirectory.path,
    );
    final packageStatuses = <_PackageStatus>[];
    for (final package in packages) {
      packageStatuses.add(
        await _statusForPackage(
          repository: repository,
          manifest: manifest,
          package: package,
        ),
      );
    }

    final result = {
      'branch': branch,
      'expectedBranch': manifest.branch,
      'branchMatches': branch == manifest.branch,
      'workingTreeClean': dirtyFiles.isEmpty,
      'dirtyFiles': dirtyFiles,
      'localPathFiles': localPathFiles,
      'packages': packageStatuses.map((status) => status.toJson()).toList(),
      'ready':
          branch == manifest.branch &&
          dirtyFiles.isEmpty &&
          localPathFiles.isEmpty &&
          packageStatuses.every((status) => status.ready),
    };

    if (argResults!.flag('json')) {
      writeMachineOutput(
        _stdout,
        command: 'package status',
        ok: result['ready'] == true,
        exitCode: 0,
        fields: result,
      );
      return 0;
    }

    _printStatus(result, packageStatuses);
    return 0;
  }

  Future<_PackageStatus> _statusForPackage({
    required Directory repository,
    required PackageManifest manifest,
    required PackageManifestPackage package,
  }) async {
    final checks = <_PackageStatusCheck>[];
    final tag = package.releaseTag(manifest.sdkVersion);
    checks.add(
      package.status == null || package.status == 'compatible'
          ? const _PackageStatusCheck.ok(
              'release-status',
              'Package is marked compatible',
            )
          : _PackageStatusCheck.warning(
              'release-status',
              'Package status is ${package.status}; remove status only when release-ready.',
            ),
    );

    final metadataChecks = <_PackageStatusCheck>[];
    try {
      await validatePackageReleaseMetadata(
        repository: repository,
        manifest: manifest,
        package: package,
        tag: tag,
      );
    } on UsageException catch (error) {
      metadataChecks.add(
        _PackageStatusCheck.warning('release-metadata', error.message),
      );
    } on FormatException catch (error) {
      metadataChecks.add(
        _PackageStatusCheck.warning('release-metadata', error.message),
      );
    }

    final metadataWarnings = await packageReleaseMetadataWarnings(
      repository: repository,
      manifest: manifest,
      package: package,
      tag: tag,
    );
    metadataChecks.addAll(
      metadataWarnings.map(
        (warning) => _PackageStatusCheck.warning('release-metadata', warning),
      ),
    );
    if (metadataChecks.isEmpty) {
      checks.add(
        const _PackageStatusCheck.ok(
          'release-metadata',
          'Release metadata is present',
        ),
      );
    } else {
      checks.addAll(metadataChecks);
    }

    final packageRoot = packageDirectory(repository, package.repositoryPath);
    if (await hasPackageTests(packageRoot)) {
      checks.add(
        const _PackageStatusCheck.ok('package-tests', 'Package tests exist'),
      );
    } else {
      checks.add(
        const _PackageStatusCheck.warning(
          'package-tests',
          'No package tests were found',
        ),
      );
    }

    final example = Directory('${packageRoot.path}/example');
    final examplePubspec = File('${example.path}/pubspec.yaml');
    if (!await examplePubspec.exists()) {
      checks.add(
        const _PackageStatusCheck.skipped(
          'example',
          'No top-level Flutter example was found',
        ),
      );
    } else if (!await isFlutterPackageDirectory(example)) {
      checks.add(
        const _PackageStatusCheck.skipped(
          'example',
          'Top-level example is not a Flutter project',
        ),
      );
    } else {
      checks.add(
        const _PackageStatusCheck.ok('example', 'Flutter example exists'),
      );
      final ohos = Directory('${example.path}/ohos');
      checks.add(
        await ohos.exists()
            ? const _PackageStatusCheck.ok(
                'example-ohos',
                'Example OHOS platform exists',
              )
            : const _PackageStatusCheck.warning(
                'example-ohos',
                'Example is missing the OHOS platform directory',
              ),
      );
      checks.add(
        await hasPackageTests(example)
            ? const _PackageStatusCheck.ok(
                'example-tests',
                'Example tests exist',
              )
            : const _PackageStatusCheck.warning(
                'example-tests',
                'No example tests were found',
              ),
      );
    }

    return _PackageStatus(packageName: package.name, tag: tag, checks: checks);
  }

  void _printStatus(
    Map<String, Object?> result,
    List<_PackageStatus> packageStatuses,
  ) {
    _output.heading('Package release status');
    final branchMatches = result['branchMatches'] == true;
    final workingTreeClean = result['workingTreeClean'] == true;
    if (branchMatches) {
      _output.success('Branch matches ${result['expectedBranch']}');
    } else {
      _output.warning(
        'Current branch ${result['branch']} does not match ${result['expectedBranch']}.',
      );
    }
    if (workingTreeClean) {
      _output.success('Working tree is clean');
    } else {
      _output.warning('Working tree has uncommitted changes');
    }
    final localPathFiles = result['localPathFiles'] as List<String>;
    if (localPathFiles.isEmpty) {
      _output.success('No tracked files contain the local fluoh home path');
    } else {
      _output.warning(
        'Tracked files contain local fluoh home paths: ${localPathFiles.join(', ')}.',
      );
    }

    for (final package in packageStatuses) {
      _output.blank();
      _output.section('${package.packageName}: ${package.tag}');
      for (final check in package.checks) {
        switch (check.status) {
          case 'ok':
            _output.success(check.message);
            break;
          case 'warning':
            _output.warning(check.message);
            break;
          case 'skipped':
            _output.skipped(check.message);
            break;
        }
      }
    }

    if (result['ready'] == true) {
      _output.success('Package repository appears ready for release');
    } else {
      _output.next(
        'Resolve warnings, run fluoh verify, commit, then run fluoh package release.',
      );
    }
  }
}

Future<List<String>> _dirtyFiles(Directory repository) async {
  final result = await runGit(
    ['status', '--porcelain'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (result.exitCode != 0) {
    return const ['<git status failed>'];
  }
  return result.stdout
      .toString()
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

Future<List<String>> _trackedFilesContaining(
  Directory repository,
  String needle,
) async {
  if (needle.isEmpty) {
    return const [];
  }
  final result = await runGit(
    ['ls-files'],
    workingDirectory: repository,
    allowFailure: true,
  );
  if (result.exitCode != 0) {
    return const [];
  }
  final matches = <String>[];
  for (final path in result.stdout.toString().split('\n')) {
    if (path.trim().isEmpty) {
      continue;
    }
    final file = File('${repository.path}/$path');
    try {
      if (await file.exists() && (await file.readAsString()).contains(needle)) {
        matches.add(path);
      }
    } on FormatException {
      // Binary or non-UTF8 tracked files are ignored by this lightweight scan.
    } on FileSystemException {
      // Files can disappear while status is being checked.
    }
  }
  return matches;
}

class _PackageStatus {
  const _PackageStatus({
    required this.packageName,
    required this.tag,
    required this.checks,
  });

  final String packageName;
  final String tag;
  final List<_PackageStatusCheck> checks;

  bool get ready => checks.every((check) => check.status != 'warning');

  Map<String, Object?> toJson() {
    return {
      'package': packageName,
      'tag': tag,
      'ready': ready,
      'checks': checks.map((check) => check.toJson()).toList(),
    };
  }
}

class _PackageStatusCheck {
  const _PackageStatusCheck.ok(this.name, this.message) : status = 'ok';

  const _PackageStatusCheck.warning(this.name, this.message)
    : status = 'warning';

  const _PackageStatusCheck.skipped(this.name, this.message)
    : status = 'skipped';

  final String name;
  final String status;
  final String message;

  Map<String, Object?> toJson() {
    return {'name': name, 'status': status, 'message': message};
  }
}
