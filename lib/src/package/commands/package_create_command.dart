import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../sdk/sdk_manager.dart';
import '../../sdk/sdk_project_environment.dart';
import '../../sdk/sdk_release.dart';
import '../git/package_git.dart';
import '../manifest/package_manifest.dart';
import '../manifest/pubspec_package.dart';
import '../license_checker.dart';
import '../package_examples.dart';
import '../package_repository_docs.dart';
import '../repository_url.dart';

/// Initializes a FlutterOH package repository from an upstream package repo.
class PackageCreateCommand extends FluohCommand<int> {
  /// Creates the package repository initialization command.
  PackageCreateCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _stderr = stderr {
    _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr);
    argParser
      ..addMultiOption(
        'package-path',
        valueHelp: 'path',
        help: 'Package path inside the upstream repository. Can be repeated.',
      )
      ..addOption(
        'output',
        valueHelp: 'path',
        help: 'Destination path for the FlutterOH package repository.',
      )
      ..addOption(
        'sdk',
        valueHelp: 'version-or-series',
        help: 'Flutter OHOS SDK version or version series.',
      )
      ..addOption(
        'repository',
        abbr: 'r',
        valueHelp: 'url',
        help: 'Final FlutterOH package repository URL for origin and manifest.',
      )
      ..addOption(
        'git-author-name',
        valueHelp: 'name',
        help: 'Configure local Git user.name for adaptation commits.',
      )
      ..addOption(
        'git-author-email',
        valueHelp: 'email',
        help: 'Configure local Git user.email for adaptation commits.',
      );
  }

  /// Runtime environment for SDK, Git, and filesystem operations.
  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  late final TerminalOutput _output;

  @override
  String get name => 'create';

  @override
  String get description => 'Initialize a FlutterOH package repository.';

  @override
  String get invocation => 'fluoh package create <upstream>';

  @override
  String get usage => '$description\n\n$_usageWithoutDescription';

  @override
  void printUsage() {
    _output.write(usage);
  }

  @override
  Never usageException(String message) {
    throw UsageException(message, _usageWithoutDescription);
  }

  @override
  Future<int> run() async {
    final rest = expectArgumentCount(
      argResults!,
      1,
      'Expected <upstream>: Git URL or local Git repo path.',
      usageException,
    );

    final upstream = rest.single;
    final gitAuthor = _gitAuthorConfigFromOptions();
    _output.step('Resolving Flutter OHOS SDK');
    final release = await _resolveSdkRelease();
    final packagePaths = argResults!.multiOption('package-path');
    final destination = _packageCreateDestination(
      environment: environment,
      upstream: upstream,
      output: argResults!.option('output'),
    );

    if (await destination.exists()) {
      usageException('Destination already exists: ${destination.path}');
    }

    var shouldRollbackDestination = true;
    try {
      _output.step(
        'Cloning upstream repository into ${_output.style.path(destination.path)}...',
      );
      await runGit(['clone', '--quiet', upstream, destination.path]);

      var selectedPackages = await _selectPackages(
        repository: destination,
        packagePaths: packagePaths,
      );
      final publishedRefs = await _PublishedPackageRefResolver.load(
        destination,
      );
      selectedPackages = await _restoreLatestPublishedPackageRefs(
        repository: destination,
        selectedPackages: selectedPackages,
        publishedRefs: publishedRefs,
      );
      final packageCollection = await _isPackageCollectionRepository(
        repository: destination,
        selectedPackages: selectedPackages,
      );
      for (final selected in selectedPackages) {
        if (selected.path != '.') {
          _output.info(
            'Selected package ${selected.package.name} at ${selected.path}',
          );
        }
      }
      final docPackages = [
        for (final selected in selectedPackages)
          _docPackageForSelection(selectedPackage: selected),
      ];

      final repositoryUrl =
          argResults!.option('repository') ??
          defaultPackageRepositoryUrl(
            _defaultImplementationRepositoryName(
              upstream,
              selectedPackages,
              packageCollection: packageCollection,
            ),
          );
      await configurePackageRemotes(destination, repositoryUrl);
      if (gitAuthor != null) {
        await configurePackageGitAuthor(destination, gitAuthor);
        _output.info(
          'Configured local Git author: ${gitAuthor.name} <${gitAuthor.email}>',
        );
      }

      final upstreamBranch = await upstreamDefaultBranch(destination);
      final branch = flutterOhosBranchForSdk(release.tag);
      await runGit(['checkout', '-b', branch], workingDirectory: destination);
      final packageEnvironment = FluohEnvironment(
        homeDirectory: environment.homeDirectory,
        workingDirectory: destination,
        processEnvironment: environment.processEnvironment,
      );
      _output.blank();
      final sdkDirectory = SdkManager(
        packageEnvironment,
      ).sdkDirectory(release.tag);
      final sdkInstalled = await sdkDirectory.exists();
      if (sdkInstalled) {
        _output.info('Using installed Flutter OHOS SDK ${release.tag}');
      }
      final projectEnvironment = SdkProjectEnvironment(packageEnvironment);
      final configuredSdkDirectory = await _output.withProgress(
        sdkInstalled
            ? 'Configuring Flutter OHOS SDK ${release.tag}'
            : 'Installing Flutter OHOS SDK ${release.tag}; this may take a while.',
        () => projectEnvironment.configure(release, writeFluohConfig: false),
        showWhenPlain: !sdkInstalled,
      );
      _output.info(
        'Flutter OHOS SDK path: ${_output.style.path(configuredSdkDirectory.path)}',
      );
      await _warnForSelectedPackageSdkCompatibility(
        selectedPackages: selectedPackages,
        sdkDirectory: configuredSdkDirectory,
        publishedRefs: publishedRefs,
        output: _output,
      );
      final ideLink = await projectEnvironment.linkIdeSdk(
        configuredSdkDirectory,
      );
      _output.info('IDE Flutter SDK link: ${_output.style.path(ideLink.path)}');
      _output.next('Use this link as your IDE Flutter SDK path');
      _output.blank();
      await writePackageManifestFile(
        destination,
        PackageManifest(
          name: _defaultImplementationRepositoryName(
            upstream,
            selectedPackages,
            packageCollection: packageCollection,
          ),
          sdkVersion: release.tag,
          repositoryBranch: branch,
          upstreamUrl: upstream,
          upstreamBranch: upstreamBranch,
          repositoryUrl: repositoryUrl,
          packages: [
            for (final selected in selectedPackages)
              PackageManifestPackage(
                name: selected.package.name,
                upstreamVersion: selected.package.version,
                version: initialPackageReleaseVersion,
                repositoryPath: selected.path,
                upstreamPath: selected.path,
                upstreamRef: selected.upstreamRef,
                status: 'experimental',
              ),
          ],
        ),
      );
      await writeOrReplacePackageImplementationGuide(
        destination: destination,
        packages: docPackages,
      );
      await File('${destination.path}/FLUOH_CHANGELOG.md').writeAsString(
        packageFluohChangelogContent(
          packages: docPackages,
          sdkVersion: release.tag,
          releaseVersion: initialPackageReleaseVersion,
        ),
      );
      await writeOrReplacePackageAgentsInstructions(
        destination: destination,
        packages: docPackages,
      );
      await _writeClaudeInstructions(destination);
      final preparedExamples = <PackageExampleSetupResult>[];
      for (final selected in selectedPackages) {
        final result = await preparePackageExample(
          environment: packageEnvironment,
          repository: destination,
          package: PackageManifestPackage(
            name: selected.package.name,
            upstreamVersion: selected.package.version,
            version: initialPackageReleaseVersion,
            repositoryPath: selected.path,
            upstreamPath: selected.path,
            upstreamRef: selected.upstreamRef,
            status: 'experimental',
          ),
          sdkVersion: release.tag,
          sdkDirectory: configuredSdkDirectory,
          stdout: _stdout,
          stderr: _stderr,
          output: _output,
        );
        preparedExamples.add(result);
        if (!result.prepared && result.reason != null) {
          _output.skipped(
            'Skipping example OHOS setup for ${result.packageName}: '
            '${result.reason}',
          );
        }
      }
      await runGit([
        'add',
        '-f',
        'AGENTS.md',
        'CLAUDE.md',
        'FLUOH.md',
        'FLUOH_CHANGELOG.md',
        '.gitignore',
        'fluoh.yaml',
      ], workingDirectory: destination);
      for (final selected in selectedPackages.where(
        (selected) => selected.upstreamRef != null,
      )) {
        await runGit([
          'add',
          '-f',
          '-A',
          selected.path,
        ], workingDirectory: destination);
      }
      for (final result in preparedExamples.where(
        (result) => result.prepared,
      )) {
        await runGit([
          'add',
          '-A',
          packageRelativePath(destination, result.example),
        ], workingDirectory: destination);
      }

      final licenseWarnings = <String>[];
      for (final selected in selectedPackages) {
        licenseWarnings.addAll(
          await packageLicenseWarnings(
            repository: destination,
            packagePath: selected.path,
            packageName: selected.package.name,
          ),
        );
      }
      _output.blank();
      for (final warning in licenseWarnings) {
        _output.warningError(warning);
      }
      if (licenseWarnings.isNotEmpty) {
        _output.blank();
      }

      _output.success(
        'Created package repository at ${_output.style.path(destination.path)}',
      );
      _output.info('Package branch: $branch');
      _output.info('Origin: ${_output.style.url(repositoryUrl)}');
      _output.success('Configured Flutter OHOS SDK ${release.tag}');
      _output.next('See FLUOH.md and AGENTS.md for implementation steps');
      shouldRollbackDestination = false;
      return 0;
    } catch (_) {
      if (shouldRollbackDestination && await destination.exists()) {
        await destination.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<SdkRelease> _resolveSdkRelease() async {
    final manager = SdkManager(environment);
    final sdk = argResults!.option('sdk');
    if (sdk != null) {
      return manager.resolveRelease(sdk);
    }

    final releases = await manager.listReleases();
    if (releases.isEmpty) {
      usageException('No SDK versions found in configured sources.');
    }
    return SdkManager.latestRelease(releases, preferStable: true);
  }

  PackageGitAuthor? _gitAuthorConfigFromOptions() {
    final name = argResults!.option('git-author-name')?.trim();
    final email = argResults!.option('git-author-email')?.trim();
    final hasName = name != null && name.isNotEmpty;
    final hasEmail = email != null && email.isNotEmpty;
    if (!hasName && !hasEmail) {
      return null;
    }
    if (!hasName || !hasEmail) {
      usageException(
        'Pass both --git-author-name and --git-author-email, or omit both.',
      );
    }
    return PackageGitAuthor(name: name, email: email);
  }

  String get _usageWithoutDescription {
    return [
      'Usage: $invocation',
      'Upstream: Git URL or local Git repo path.',
      '',
      argParser.usage,
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }
}

Directory _packageCreateDestination({
  required FluohEnvironment environment,
  required String upstream,
  required String? output,
}) {
  final trimmedOutput = output?.trim();
  if (trimmedOutput != null && trimmedOutput.isNotEmpty) {
    final outputDirectory = Directory(trimmedOutput);
    final path = outputDirectory.isAbsolute
        ? trimmedOutput
        : '${environment.workingDirectory.path}/$trimmedOutput';
    return Directory(_normalizeDirectoryPath(path));
  }
  return Directory(
    _normalizeDirectoryPath(
      '${environment.workingDirectory.path}/${repositoryNameFromUpstream(upstream)}',
    ),
  );
}

String _normalizeDirectoryPath(String path) {
  final normalizedSeparators = path.replaceAll('\\', '/');
  final absolutePrefix = normalizedSeparators.startsWith('/') ? '/' : '';
  final segments = <String>[];
  for (final segment in normalizedSeparators.split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (segments.isNotEmpty && segments.last != '..') {
        segments.removeLast();
      } else if (absolutePrefix.isEmpty) {
        segments.add(segment);
      }
      continue;
    }
    segments.add(segment);
  }

  final normalized = '$absolutePrefix${segments.join('/')}';
  final nativePath = Platform.pathSeparator == '/'
      ? normalized
      : normalized.replaceAll('/', Platform.pathSeparator);
  if (nativePath.isNotEmpty) {
    return nativePath;
  }
  return absolutePrefix.isEmpty ? '.' : Platform.pathSeparator;
}

class _SelectedPackage {
  const _SelectedPackage({
    required this.package,
    required this.path,
    this.upstreamRef,
  });

  final PubspecPackage package;
  final String path;
  final String? upstreamRef;
}

Future<List<_SelectedPackage>> _selectPackages({
  required Directory repository,
  required List<String> packagePaths,
}) async {
  final paths = packagePaths.isEmpty ? const ['.'] : packagePaths;
  final selected = <_SelectedPackage>[];
  final seenPackages = <String>{};
  for (final path in paths) {
    final package = await _readSelectedPackage(
      repository: repository,
      packagePath: path,
    );
    if (!seenPackages.add(package.name)) {
      throw UsageException(
        'Package ${package.name} was selected more than once.',
        '',
      );
    }
    selected.add(_SelectedPackage(package: package, path: path));
  }
  return selected;
}

Future<List<_SelectedPackage>> _restoreLatestPublishedPackageRefs({
  required Directory repository,
  required List<_SelectedPackage> selectedPackages,
  required _PublishedPackageRefResolver publishedRefs,
}) async {
  final resolved = <_SelectedPackage>[];
  for (final selected in selectedPackages) {
    final releaseRef = await publishedRefs.latest(
      packageName: selected.package.name,
      packagePath: selected.path,
    );
    if (releaseRef == null) {
      resolved.add(selected);
      continue;
    }

    await runGit([
      'restore',
      '--source',
      releaseRef.ref,
      '--',
      selected.path,
    ], workingDirectory: repository);
    final package = await _readSelectedPackage(
      repository: repository,
      packagePath: selected.path,
    );
    if (package.name != selected.package.name) {
      throw UsageException(
        'Upstream ref ${releaseRef.ref} contains package ${package.name} at '
            '${selected.path}, expected ${selected.package.name}.',
        '',
      );
    }
    resolved.add(
      _SelectedPackage(
        package: package,
        path: selected.path,
        upstreamRef: releaseRef.ref,
      ),
    );
  }
  return resolved;
}

String? _packageVersionFromReleaseTag({
  required String tag,
  required String packageName,
  required bool rootPackage,
}) {
  final escapedPackage = RegExp.escape(packageName);
  final packageTagPatterns = [
    RegExp('^$escapedPackage-v(.+)\$'),
    RegExp('^$escapedPackage-(.+)\$'),
  ];
  final rootTagPatterns = rootPackage
      ? [RegExp(r'^v(.+)$'), RegExp(r'^(.+)$')]
      : const <RegExp>[];
  for (final pattern in [...packageTagPatterns, ...rootTagPatterns]) {
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

class _PublishedPackageRef {
  const _PublishedPackageRef({
    required this.ref,
    required this.version,
    required this.package,
  });

  final String ref;
  final Version version;
  final PubspecPackage package;
}

class _PublishedPackageRefResolver {
  _PublishedPackageRefResolver._({
    required this.repository,
    required this.tags,
  });

  final Directory repository;
  final List<String> tags;
  final Map<String, List<_PublishedPackageRef>> _cache = {};

  static Future<_PublishedPackageRefResolver> load(Directory repository) async {
    final tags = (await runGit([
      'tag',
      '--list',
    ], workingDirectory: repository)).stdout.toString().split('\n');
    return _PublishedPackageRefResolver._(
      repository: repository,
      tags: tags
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(),
    );
  }

  Future<_PublishedPackageRef?> latest({
    required String packageName,
    required String packagePath,
  }) async {
    final candidates = await refs(
      packageName: packageName,
      packagePath: packagePath,
    );
    return candidates.isEmpty ? null : candidates.last;
  }

  Future<_PublishedPackageRef?> latestCompatible({
    required String packageName,
    required String packagePath,
    required Version dartVersion,
  }) async {
    final candidates = await refs(
      packageName: packageName,
      packagePath: packagePath,
    );
    for (final candidate in candidates.reversed) {
      final constraint = _dartSdkConstraint(candidate.package);
      if (constraint == null || constraint.allows(dartVersion)) {
        return candidate;
      }
    }
    return null;
  }

  Future<List<_PublishedPackageRef>> refs({
    required String packageName,
    required String packagePath,
  }) async {
    final normalizedPath = _normalizePackagePath(packagePath);
    final cacheKey = '$packageName\n$normalizedPath';
    final cached = _cache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final candidates = <_PublishedPackageRef>[];
    for (final tag in tags) {
      final tagVersion = _packageVersionFromReleaseTag(
        tag: tag,
        packageName: packageName,
        rootPackage: normalizedPath == '.',
      );
      if (tagVersion == null) {
        continue;
      }
      final pubspec = await _packageAtRef(
        ref: tag,
        packagePath: normalizedPath,
      );
      if (pubspec == null || pubspec.name != packageName) {
        continue;
      }
      if (pubspec.version != tagVersion) {
        continue;
      }
      try {
        candidates.add(
          _PublishedPackageRef(
            ref: tag,
            version: Version.parse(pubspec.version),
            package: pubspec,
          ),
        );
      } on FormatException {
        continue;
      }
    }
    candidates.sort((a, b) {
      final version = a.version.compareTo(b.version);
      if (version != 0) {
        return version;
      }
      return a.ref.compareTo(b.ref);
    });
    _cache[cacheKey] = candidates;
    return candidates;
  }

  Future<PubspecPackage?> _packageAtRef({
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
}

Future<void> _warnForSelectedPackageSdkCompatibility({
  required List<_SelectedPackage> selectedPackages,
  required Directory sdkDirectory,
  required _PublishedPackageRefResolver publishedRefs,
  required TerminalOutput output,
}) async {
  final dartVersion = await _dartVersionForSdk(sdkDirectory);
  if (dartVersion == null) {
    return;
  }
  for (final selected in selectedPackages) {
    final constraint = _dartSdkConstraint(selected.package);
    if (constraint == null || constraint.allows(dartVersion)) {
      continue;
    }
    final compatibleRef = await publishedRefs.latestCompatible(
      packageName: selected.package.name,
      packagePath: selected.path,
      dartVersion: dartVersion,
    );
    final selectedRef = selected.upstreamRef ?? selected.package.version;
    output.warning(
      'Selected upstream $selectedRef for ${selected.package.name} requires '
      'Dart ${selected.package.sdkConstraint}, but the selected Flutter OHOS '
      'SDK provides Dart $dartVersion.',
    );
    if (compatibleRef != null && compatibleRef.ref != selected.upstreamRef) {
      output.next(
        'Latest compatible upstream tag: ${compatibleRef.ref} '
        '(${compatibleRef.package.version}). fluoh keeps the latest selected '
        'target; use this only if maintainers choose an older baseline.',
      );
    } else {
      output.next(
        'Keep adapting the selected upstream target, or choose another '
        'Flutter OHOS SDK that satisfies Dart ${selected.package.sdkConstraint}.',
      );
    }
  }
}

VersionConstraint? _dartSdkConstraint(PubspecPackage package) {
  final constraint = package.sdkConstraint?.trim();
  if (constraint == null || constraint.isEmpty) {
    return null;
  }
  try {
    return VersionConstraint.parse(constraint);
  } on FormatException {
    return null;
  }
}

Future<Version?> _dartVersionForSdk(Directory sdkDirectory) async {
  final dart = File('${sdkDirectory.path}/bin/dart');
  if (!await dart.exists()) {
    return null;
  }
  final result = await Process.run(dart.path, const ['--version']);
  final output = '${result.stdout}\n${result.stderr}';
  final match = RegExp(
    r'Dart SDK version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
  ).firstMatch(output);
  if (match == null) {
    return null;
  }
  try {
    return Version.parse(match.group(1)!);
  } on FormatException {
    return null;
  }
}

String _defaultImplementationRepositoryName(
  String upstream,
  List<_SelectedPackage> selectedPackages, {
  required bool packageCollection,
}) {
  if (!packageCollection &&
      selectedPackages.length == 1 &&
      selectedPackages.single.path == '.') {
    return selectedPackages.single.package.name;
  }
  return repositoryNameFromUpstream(upstream);
}

PackageRepositoryDocPackage _docPackageForSelection({
  required _SelectedPackage selectedPackage,
}) {
  return PackageRepositoryDocPackage(
    name: selectedPackage.package.name,
    version: selectedPackage.package.version,
    packagePath: selectedPackage.path,
  );
}

bool _isPackageCollectionSelection(List<_SelectedPackage> selectedPackages) {
  return selectedPackages.length > 1 ||
      selectedPackages.any((selected) => selected.path != '.');
}

Future<bool> _isPackageCollectionRepository({
  required Directory repository,
  required List<_SelectedPackage> selectedPackages,
}) async {
  if (_isPackageCollectionSelection(selectedPackages)) {
    return true;
  }

  final packagePaths = await _discoverRepositoryPackagePaths(repository);
  if (packagePaths.length > 1) {
    return true;
  }

  final selectedPaths = selectedPackages
      .map((selected) => _normalizePackagePath(selected.path))
      .toSet();
  return packagePaths.any((path) => !selectedPaths.contains(path));
}

Future<List<String>> _discoverRepositoryPackagePaths(
  Directory repository,
) async {
  final paths = <String>{};
  final pending = <Directory>[repository];
  while (pending.isNotEmpty) {
    final directory = pending.removeLast();
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is Directory) {
        final relativeDirectory = _relativeDirectoryPath(repository, entity);
        if (!_isIgnoredPackageScanDirectory(relativeDirectory)) {
          pending.add(entity);
        }
        continue;
      }
      if (entity is File && _pathName(entity.path) == 'pubspec.yaml') {
        final packagePath = _relativeDirectoryPath(repository, entity.parent);
        if (!_isIgnoredPackageScanDirectory(packagePath)) {
          paths.add(packagePath);
        }
      }
    }
  }
  return paths.toList()..sort();
}

bool _isIgnoredPackageScanDirectory(String path) {
  if (path == '.') {
    return false;
  }
  return _pathSegments(path).any(_ignoredPackageScanSegmentNames.contains);
}

const _ignoredPackageScanSegmentNames = {
  '.dart_tool',
  '.git',
  '.idea',
  'build',
  'coverage',
  'example',
  'examples',
  'fixture',
  'fixtures',
  'integration_test',
  'test',
  'tool',
  'tools',
};

String _relativeDirectoryPath(Directory root, Directory directory) {
  final rootPath = root.absolute.path;
  final directoryPath = directory.absolute.path;
  if (directoryPath == rootPath) {
    return '.';
  }
  if (directoryPath.startsWith('$rootPath/')) {
    return _normalizePackagePath(directoryPath.substring(rootPath.length + 1));
  }
  return _normalizePackagePath(directoryPath);
}

String _normalizePackagePath(String path) {
  final segments = _pathSegments(path);
  if (segments.isEmpty) {
    return '.';
  }
  return segments.join('/');
}

List<String> _pathSegments(String path) {
  return path
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty && segment != '.')
      .toList(growable: false);
}

String _pathName(String path) {
  final segments = _pathSegments(path);
  return segments.isEmpty ? path : segments.last;
}

Future<PubspecPackage> _readSelectedPackage({
  required Directory repository,
  required String packagePath,
}) async {
  final directory = packageDirectory(repository, packagePath);
  final pubspec = File('${directory.path}/pubspec.yaml');
  if (await pubspec.exists()) {
    return readPubspecPackage(directory);
  }

  if (packagePath == '.' || packagePath.isEmpty) {
    final candidates = await _packageSelectionCandidates(repository);
    final candidateHelp = _packageSelectionCandidateHelp(candidates);
    throw UsageException(
      'Missing pubspec.yaml at the upstream repository root. '
          'For packages below the root, select package paths with '
          '"--package-path <package-path>".'
          '$candidateHelp',
      '',
    );
  }
  throw UsageException(
    'Missing pubspec.yaml at package path $packagePath.',
    '',
  );
}

Future<List<_PackageSelectionCandidate>> _packageSelectionCandidates(
  Directory repository,
) async {
  final candidates = <_PackageSelectionCandidate>[];
  if (!await repository.exists()) {
    return candidates;
  }
  final publishedRefs = await _PublishedPackageRefResolver.load(repository);
  final pending = <Directory>[repository];
  while (pending.isNotEmpty) {
    final directory = pending.removeLast();
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is Directory) {
        final path = _relativeCandidatePath(repository, entity);
        if (!_shouldSkipCandidatePath(path)) {
          pending.add(entity);
        }
        continue;
      }
      if (entity is! File || !_isPubspecFile(entity)) {
        continue;
      }
      final path = _relativeCandidatePath(repository, entity.parent);
      if (_shouldSkipCandidatePath(path)) {
        continue;
      }
      try {
        final package = await readPubspecPackage(entity.parent);
        final latestRef = await publishedRefs.latest(
          packageName: package.name,
          packagePath: path,
        );
        candidates.add(
          _PackageSelectionCandidate(
            package: package,
            path: path,
            latestRef: latestRef,
          ),
        );
      } on Object {
        // Ignore malformed nested pubspec files while building selection help.
      }
    }
  }
  candidates.sort((a, b) => a.path.compareTo(b.path));
  return candidates;
}

String _relativeCandidatePath(Directory repository, Directory directory) {
  final root = repository.absolute.path;
  final path = directory.absolute.path;
  if (path == root) {
    return '.';
  }
  if (path.startsWith('$root${Platform.pathSeparator}')) {
    return _normalizePackagePath(path.substring(root.length + 1));
  }
  return _normalizePackagePath(path);
}

String _packageSelectionCandidateHelp(
  List<_PackageSelectionCandidate> candidates,
) {
  if (candidates.isEmpty) {
    return '';
  }
  final visible = candidates.take(20).map((candidate) {
    final package = candidate.package;
    return [
      '\n- ${package.name} ${package.version} at ${candidate.path}',
      if (package.sdkConstraint != null) ' (Dart ${package.sdkConstraint})',
      if (candidate.latestRef != null)
        ' [latest tag ${candidate.latestRef!.ref}]',
      ': --package-path ${candidate.path}',
    ].join();
  }).join();
  final hidden = candidates.length > 20
      ? '\n- ... ${candidates.length - 20} more package candidates'
      : '';
  return '\nCandidate packages:$visible$hidden';
}

bool _isPubspecFile(File file) {
  final normalized = file.path.replaceAll('\\', '/');
  return normalized.endsWith('/pubspec.yaml');
}

bool _shouldSkipCandidatePath(String path) {
  final segments = _pathSegments(path);
  return segments.any(
    (segment) => const {
      '.dart_tool',
      '.git',
      '.idea',
      'build',
      'example',
      'examples',
      'node_modules',
    }.contains(segment),
  );
}

class _PackageSelectionCandidate {
  const _PackageSelectionCandidate({
    required this.package,
    required this.path,
    required this.latestRef,
  });

  final PubspecPackage package;
  final String path;
  final _PublishedPackageRef? latestRef;
}

const _claudeAgentsImport = '@AGENTS.md';

Future<void> _writeClaudeInstructions(Directory destination) async {
  final file = File('${destination.path}/CLAUDE.md');
  if (!await file.exists()) {
    await file.writeAsString('$_claudeAgentsImport\n');
    return;
  }

  final existing = await file.readAsString();
  if (existing.trim().isEmpty) {
    await file.writeAsString('$_claudeAgentsImport\n');
    return;
  }
  if (_importsAgentsInstructions(existing)) {
    return;
  }

  final separator = existing.startsWith('\n') ? '' : '\n';
  await file.writeAsString('$_claudeAgentsImport\n$separator$existing');
}

bool _importsAgentsInstructions(String content) {
  return content.split('\n').any((line) => line.trim() == _claudeAgentsImport);
}
