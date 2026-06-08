import 'dart:io';

import 'package:args/command_runner.dart';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../schema/yaml_utils.dart' show parseYamlMap;
import '../git/package_git.dart';
import '../manifest/package_manifest.dart';
import '../manifest/pubspec_package.dart';
import '../package_discovery.dart';
import '../package_examples.dart';
import '../release_validator.dart';

/// Reports release readiness for package repository entries.
class PackageStatusCommand extends FluohCommand<int> {
  /// Creates the package status command.
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
        help: 'Package to inspect. Defaults to the current package branch.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print package status as JSON.',
      );
  }

  /// Runtime environment for repository checks.
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

    final repository = environment.workingDirectory;
    final manifest = await readPackageManifest(repository);
    final packages = [manifest.packageForName(argResults!.option('package'))];
    final branch = await currentBranch(repository);
    final dirtyFiles = await _dirtyFiles(repository);
    final localPathFiles = await _trackedFilesContaining(
      repository,
      environment.homeDirectory.path,
    );
    final discovery = await discoverPackageAdaptationCandidates(
      repository: repository,
      missingPlatform: 'ohos',
      includeExistingPlatform: true,
    );
    final packageStatuses = <_PackageStatus>[];
    for (final package in packages) {
      packageStatuses.add(
        await _statusForPackage(
          repository: repository,
          manifest: manifest,
          package: package,
          discovery: discovery,
        ),
      );
    }
    final readinessBlockers = [
      ..._repositoryReadinessBlockers(
        branch: branch,
        expectedBranch: manifest.branch,
        dirtyFiles: dirtyFiles,
        localPathFiles: localPathFiles,
      ),
      for (final status in packageStatuses) ...status.blockers,
    ];

    final result = {
      'branch': branch,
      'expectedBranch': manifest.branch,
      'branchMatches': branch == manifest.branch,
      'workingTreeClean': dirtyFiles.isEmpty,
      'dirtyFiles': dirtyFiles,
      'localPathFiles': localPathFiles,
      'readinessBlockers': readinessBlockers
          .map((blocker) => blocker.toJson())
          .toList(),
      'packages': packageStatuses.map((status) => status.toJson()).toList(),
      'ready':
          branch == manifest.branch &&
          dirtyFiles.isEmpty &&
          localPathFiles.isEmpty &&
          readinessBlockers.isEmpty &&
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
    required PackageDiscovery discovery,
  }) async {
    final checks = <_PackageStatusCheck>[];
    final blockers = <_PackageReadinessBlocker>[];
    final tag = package.releaseTag(manifest.sdkVersion);
    if (package.status == null || package.status == 'compatible') {
      checks.add(
        const _PackageStatusCheck.ok(
          'release-status',
          'Package is marked compatible',
        ),
      );
    } else {
      checks.add(
        _PackageStatusCheck.warning(
          'release-status',
          'Package status is ${package.status}; keep it until platform '
              'implementation, verification, OHOS run evidence, and interaction '
              'evidence are complete.',
        ),
      );
      blockers.addAll([
        _PackageReadinessBlocker(
          scope: 'package',
          packageName: package.name,
          code: 'package.status.${package.status}',
          message:
              'Package is marked ${package.status}; it is not release-ready.',
          nextCommand:
              'fluoh package version --package ${package.name} '
              '--status compatible',
        ),
        _PackageReadinessBlocker(
          scope: 'package',
          packageName: package.name,
          code: 'evidence.ohos_run_missing',
          message: 'Missing passed OHOS run evidence.',
          nextCommand:
              'fluoh run --platform ohos --package ${package.name} '
              '--auto-emulator --json',
        ),
        _PackageReadinessBlocker(
          scope: 'package',
          packageName: package.name,
          code: 'evidence.interaction_missing',
          message:
              'Missing functional interaction evidence or an explicit '
              'no-interaction-required reason.',
          nextCommand:
              'python3 <skill-dir>/scripts/new_scenario.py . --platform ohos '
              '--package ${package.name}',
        ),
      ]);
    }

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
      blockers.add(
        _PackageReadinessBlocker(
          scope: 'package',
          packageName: package.name,
          code: 'release.metadata_invalid',
          message: error.message,
          nextCommand: 'fluoh package check --package ${package.name} --json',
        ),
      );
    } on FormatException catch (error) {
      metadataChecks.add(
        _PackageStatusCheck.warning('release-metadata', error.message),
      );
      blockers.add(
        _PackageReadinessBlocker(
          scope: 'package',
          packageName: package.name,
          code: 'release.metadata_invalid',
          message: error.message,
          nextCommand: 'fluoh package check --package ${package.name} --json',
        ),
      );
    }

    final metadataWarnings = await packageReleaseMetadataWarnings(
      repository: repository,
      manifest: manifest,
      package: package,
      tag: tag,
    );
    for (final warning in metadataWarnings) {
      blockers.add(
        _PackageReadinessBlocker(
          scope: 'package',
          packageName: package.name,
          code: 'release.metadata_warning',
          message: warning,
          nextCommand: 'fluoh package check --package ${package.name} --json',
        ),
      );
    }
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

    final implementationRecommendation =
        _federatedOhosImplementationRecommendation(
          discovery: discovery,
          package: package,
        );
    if (implementationRecommendation != null) {
      checks.add(
        _PackageStatusCheck.warning(
          'platform-structure',
          'Federated app-facing package is missing '
              '${implementationRecommendation.platform}.default_package: '
              '${implementationRecommendation.implementationPackageName}',
        ),
      );
      blockers.add(
        _PackageReadinessBlocker(
          scope: 'package',
          packageName: package.name,
          code: 'platform.ohos_default_package_missing',
          message:
              'Create ${implementationRecommendation.implementationPackageName} '
              'at ${implementationRecommendation.implementationPackagePath}, '
              'add ${implementationRecommendation.platform}.default_package: '
              '${implementationRecommendation.implementationPackageName}, and '
              'add dependency path '
              '${implementationRecommendation.implementationDependencyPath}.',
          details: implementationRecommendation.toJson(),
        ),
      );
    }
    final defaultPackageBlocker = await _federatedOhosDefaultPackageBlocker(
      repository: repository,
      discovery: discovery,
      package: package,
    );
    if (defaultPackageBlocker != null) {
      checks.add(
        _PackageStatusCheck.warning(
          'platform-structure',
          defaultPackageBlocker.message,
        ),
      );
      blockers.add(defaultPackageBlocker);
    }

    final packageRoot = packageDirectory(repository, package.path);
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
      if (!await ohos.exists()) {
        blockers.add(
          _PackageReadinessBlocker(
            scope: 'package',
            packageName: package.name,
            code: 'platform.ohos_missing',
            message: 'Example is missing the OHOS platform directory.',
            nextCommand: 'fluoh doctor --platform ohos --project --json',
          ),
        );
      }
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

    _addGenericWarningBlockers(
      blockers: blockers,
      checks: checks,
      packageName: package.name,
    );
    return _PackageStatus(
      packageName: package.name,
      tag: tag,
      checks: checks,
      blockers: blockers,
    );
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
      if (package.blockers.isNotEmpty) {
        _output.blank();
        _output.warning('Release blockers');
        for (final blocker in package.blockers) {
          _output.detail('${blocker.code}: ${blocker.message}');
          if (blocker.nextCommand != null) {
            _output.next(blocker.nextCommand!);
          }
        }
      }
    }

    if (result['ready'] == true) {
      _output.success('Package repository appears ready for release');
    } else {
      _output.next(
        'Resolve warnings, run fluoh verify, commit, then run fluoh package check and fluoh package release.',
      );
    }
  }
}

PackageImplementationRecommendation?
_federatedOhosImplementationRecommendation({
  required PackageDiscovery discovery,
  required PackageManifestPackage package,
}) {
  final candidate = _discoveryCandidateForPackage(
    discovery: discovery,
    package: package,
  );
  return candidate?.implementationRecommendation('ohos');
}

Future<_PackageReadinessBlocker?> _federatedOhosDefaultPackageBlocker({
  required Directory repository,
  required PackageDiscovery discovery,
  required PackageManifestPackage package,
}) async {
  final candidate = _discoveryCandidateForPackage(
    discovery: discovery,
    package: package,
  );
  final defaultPackage = candidate?.platformDefaultPackages['ohos'];
  if (defaultPackage == null || defaultPackage == package.name) {
    return null;
  }

  final dependency = await _directDependencyForPackage(
    repository: repository,
    package: package,
    dependencyName: defaultPackage,
  );
  final dependencyPresent = dependency != null;
  final dependencyPath = dependency?.path;
  final dependencyPackagePath = dependencyPath == null
      ? null
      : _dependencyPackagePath(
          packagePath: package.path,
          dependencyPath: dependencyPath,
        );
  final dependencyPathInsideRepository =
      dependencyPath == null || dependencyPackagePath != null;
  final implementationCandidateByName = _discoveryCandidateByName(
    discovery: discovery,
    name: defaultPackage,
  );
  final implementationCandidateAtDependencyPath = dependencyPackagePath == null
      ? null
      : _discoveryCandidateByNameAndPath(
          discovery: discovery,
          name: defaultPackage,
          path: dependencyPackagePath,
        );
  final implementationPackagePresent = implementationCandidateByName != null;
  final implementationPackageAtDependencyPathPresent =
      implementationCandidateAtDependencyPath != null;
  final implementationDeclaresOhos =
      implementationCandidateByName?.declaresPlatform('ohos') ?? false;
  final implementationAtDependencyPathDeclaresOhos =
      implementationCandidateAtDependencyPath?.declaresPlatform('ohos') ??
      false;
  if (dependencyPresent &&
      dependencyPathInsideRepository &&
      implementationAtDependencyPathDeclaresOhos) {
    return null;
  }

  final problems = [
    if (!dependencyPresent)
      'dependency $defaultPackage is missing from ${package.name}',
    if (dependencyPresent && dependencyPath == null)
      'dependency $defaultPackage does not declare a path from ${package.name}',
    if (dependencyPath != null && !dependencyPathInsideRepository)
      'dependency path $dependencyPath leaves the repository',
    if (dependencyPackagePath != null &&
        !implementationPackageAtDependencyPathPresent)
      'dependency path $dependencyPath does not resolve to implementation package $defaultPackage',
    if (!implementationPackagePresent)
      'implementation package $defaultPackage was not found',
    if (implementationPackageAtDependencyPathPresent &&
        !implementationAtDependencyPathDeclaresOhos)
      'implementation package $defaultPackage does not declare ohos',
  ];
  return _PackageReadinessBlocker(
    scope: 'package',
    packageName: package.name,
    code: 'platform.ohos_default_package_incomplete',
    message:
        'OHOS default_package $defaultPackage is declared for '
        '${package.name}, but ${problems.join(' and ')}.',
    details: {
      'kind': 'federated_default_package_validation',
      'platform': 'ohos',
      'defaultPackage': defaultPackage,
      'dependencyPresent': dependencyPresent,
      'dependencyPath': ?dependencyPath,
      'dependencyResolvedPath': ?dependencyPackagePath,
      'dependencyPathInsideRepository': dependencyPathInsideRepository,
      'implementationPackagePresent': implementationPackagePresent,
      'implementationPackageAtDependencyPathPresent':
          implementationPackageAtDependencyPathPresent,
      'implementationDeclaresOhos': implementationDeclaresOhos,
      'implementationAtDependencyPathDeclaresOhos':
          implementationAtDependencyPathDeclaresOhos,
      'requiredEdits': [
        if (!implementationPackagePresent)
          {
            'target': 'implementationPackage',
            'action': 'create',
            'package': defaultPackage,
          },
        if (implementationPackageAtDependencyPathPresent &&
            !implementationAtDependencyPathDeclaresOhos)
          {
            'target': 'implementationPackagePubspec',
            'action': 'add_platform',
            'platform': 'ohos',
          },
        if (!dependencyPresent)
          {
            'target': 'appFacingPubspec',
            'action': 'add_dependency',
            'package': defaultPackage,
          },
        if (dependencyPresent &&
            (dependencyPath == null ||
                !dependencyPathInsideRepository ||
                !implementationPackageAtDependencyPathPresent))
          {
            'target': 'appFacingPubspec',
            'action': 'update_dependency_path',
            'package': defaultPackage,
          },
      ],
    },
  );
}

Future<_PackageDependency?> _directDependencyForPackage({
  required Directory repository,
  required PackageManifestPackage package,
  required String dependencyName,
}) async {
  final pubspec = File(
    '${packageDirectory(repository, package.path).path}/pubspec.yaml',
  );
  try {
    final yaml = parseYamlMap(
      await pubspec.readAsString(),
      label: '${package.path}/pubspec.yaml',
    );
    final dependencies = yaml['dependencies'];
    if (dependencies is! Map<String, Object?> ||
        !dependencies.containsKey(dependencyName)) {
      return null;
    }
    final dependency = dependencies[dependencyName];
    String? path;
    if (dependency is Map<String, Object?>) {
      final value = dependency['path'];
      if (value is String && value.trim().isNotEmpty) {
        path = value.trim();
      }
    }
    return _PackageDependency(path: path);
  } on FormatException {
    return null;
  } on IOException {
    return null;
  }
}

String? _dependencyPackagePath({
  required String packagePath,
  required String dependencyPath,
}) {
  final dependency = dependencyPath.replaceAll('\\', '/').trim();
  if (dependency.isEmpty || dependency.startsWith('/')) {
    return null;
  }
  final normalized = <String>[];
  for (final segment in [
    ..._packagePathSegments(packagePath),
    ...dependency.split('/'),
  ]) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (normalized.isEmpty) {
        return null;
      }
      normalized.removeLast();
      continue;
    }
    normalized.add(segment);
  }
  return normalized.isEmpty ? '.' : normalized.join('/');
}

List<String> _packagePathSegments(String path) {
  return path
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty && segment != '.')
      .toList(growable: false);
}

PackageDiscoveryCandidate? _discoveryCandidateForPackage({
  required PackageDiscovery discovery,
  required PackageManifestPackage package,
}) {
  for (final candidate in discovery.candidates) {
    if (candidate.name == package.name && candidate.path == package.path) {
      return candidate;
    }
  }
  return null;
}

PackageDiscoveryCandidate? _discoveryCandidateByName({
  required PackageDiscovery discovery,
  required String name,
}) {
  for (final candidate in discovery.candidates) {
    if (candidate.name == name) {
      return candidate;
    }
  }
  return null;
}

PackageDiscoveryCandidate? _discoveryCandidateByNameAndPath({
  required PackageDiscovery discovery,
  required String name,
  required String path,
}) {
  for (final candidate in discovery.candidates) {
    if (candidate.name == name && candidate.path == path) {
      return candidate;
    }
  }
  return null;
}

class _PackageDependency {
  const _PackageDependency({this.path});

  final String? path;
}

void _addGenericWarningBlockers({
  required List<_PackageReadinessBlocker> blockers,
  required List<_PackageStatusCheck> checks,
  required String packageName,
}) {
  final existingMessages = blockers.map((blocker) => blocker.message).toSet();
  for (final check in checks.where((check) => check.status == 'warning')) {
    if (_hasStructuredBlocker(check.name)) {
      continue;
    }
    if (existingMessages.contains(check.message)) {
      continue;
    }
    blockers.add(
      _PackageReadinessBlocker(
        scope: 'package',
        packageName: packageName,
        code: check.name,
        message: check.message,
        nextCommand: 'fluoh package check --package $packageName --json',
      ),
    );
  }
}

bool _hasStructuredBlocker(String checkName) {
  return const {'release-status', 'platform-structure'}.contains(checkName);
}

List<_PackageReadinessBlocker> _repositoryReadinessBlockers({
  required String branch,
  required String expectedBranch,
  required List<String> dirtyFiles,
  required List<String> localPathFiles,
}) {
  return [
    if (branch != expectedBranch)
      _PackageReadinessBlocker(
        scope: 'repository',
        code: 'repository.branch_mismatch',
        message: 'Current branch $branch does not match $expectedBranch.',
        nextCommand: 'git switch $expectedBranch',
      ),
    if (dirtyFiles.isNotEmpty)
      const _PackageReadinessBlocker(
        scope: 'repository',
        code: 'repository.dirty',
        message: 'Working tree has uncommitted changes.',
        nextCommand: 'git status --short',
      ),
    if (localPathFiles.isNotEmpty)
      _PackageReadinessBlocker(
        scope: 'repository',
        code: 'repository.local_paths',
        message: 'Tracked files contain local fluoh home paths.',
        nextCommand: 'git status --short --ignored=matching',
      ),
  ];
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
    required this.blockers,
  });

  final String packageName;
  final String tag;
  final List<_PackageStatusCheck> checks;
  final List<_PackageReadinessBlocker> blockers;

  bool get ready =>
      blockers.isEmpty && checks.every((check) => check.status != 'warning');

  Map<String, Object?> toJson() {
    return {
      'package': packageName,
      'tag': tag,
      'ready': ready,
      'readinessBlockers': blockers.map((blocker) => blocker.toJson()).toList(),
      'checks': checks.map((check) => check.toJson()).toList(),
    };
  }
}

class _PackageReadinessBlocker {
  const _PackageReadinessBlocker({
    required this.scope,
    required this.code,
    required this.message,
    this.packageName,
    this.nextCommand,
    this.details,
  });

  final String scope;
  final String? packageName;
  final String code;
  final String message;
  final String? nextCommand;
  final Map<String, Object?>? details;

  Map<String, Object?> toJson() {
    return {
      'scope': scope,
      if (packageName != null) 'package': packageName,
      'code': code,
      'message': message,
      if (nextCommand != null) 'nextCommand': nextCommand,
      if (details != null) 'details': details,
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
