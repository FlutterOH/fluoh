import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/argument_validation.dart';
import '../cli/command_usage.dart';
import '../cli/fluoh_command_runner.dart';
import '../cli/terminal_output.dart';
import '../config/fluoh_config.dart';
import '../context/fluoh_environment.dart';
import '../pub/git/pub_git.dart';
import '../schema/schema.dart';
import 'source_runtime.dart';
import 'source_sync.dart';

class SourceCommand extends Command<int> {
  SourceCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    addSubcommand(
      SourceListCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(SourceInitCommand(stdout: stdout, output: _output));
    addSubcommand(
      SourceSyncCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      SourceAddCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      SourceRemoveCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      SourceUpdateCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
  }

  final TerminalOutput _output;

  @override
  String get name => 'source';

  @override
  String get description => 'Manage FlutterOH data sources.';

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

  String get _usageWithoutDescription {
    return [
      'Usage: $invocation',
      argParser.usage,
      '',
      formatCommandUsage(
        subcommands,
        sections: _sourceCommandSections,
        isSubcommand: true,
        lineLength: argParser.usageLineLength,
        style: _output.style,
      ),
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }
}

const _sourceCommandSections = [
  CommandUsageSection('Use configured sources:', [
    'list',
    'add',
    'remove',
    'update',
  ]),
  CommandUsageSection('Maintain source repositories:', ['init', 'sync']),
];

class SourceListCommand extends Command<int> {
  SourceListCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout);

  final FluohEnvironment environment;
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'list';

  @override
  String get description => 'List configured data sources.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final config = await FluohConfigStore(environment).load();
    if (config.sources.isEmpty) {
      _output.warning('No sources configured.');
      return 0;
    }

    final sources = config.sources.entries.toList(growable: false);
    if (_output.style.capabilities.decorated) {
      _output.table(
        columns: const [
          TerminalTableColumn('#', style: TerminalTableCellStyle.muted),
          TerminalTableColumn('Name', style: TerminalTableCellStyle.value),
          TerminalTableColumn('Source', style: TerminalTableCellStyle.path),
        ],
        rows: [
          for (var index = 0; index < sources.length; index += 1)
            [
              '${index + 1}',
              sources[index].key,
              sources[index].value.displayValue,
            ],
        ],
      );
      return 0;
    }

    var index = 1;
    for (final entry in sources) {
      stdout('[$index] ${entry.key} ${entry.value.displayValue}');
      index += 1;
    }
    return 0;
  }
}

class SourceInitCommand extends Command<int> {
  SourceInitCommand({required OutputWriter stdout, TerminalOutput? output})
    : _output = output ?? TerminalOutput(stdout: stdout);

  final TerminalOutput _output;

  @override
  String get name => 'init';

  @override
  String get description => 'Create a local source repository template.';

  @override
  String get invocation => 'fluoh source init <path>';

  @override
  Future<int> run() async {
    final rest = expectArgumentCount(
      argResults!,
      1,
      'Expected a local source path.',
      usageException,
    );
    final source = Directory(rest.single);
    final metadata = File('${source.path}/fluoh.yaml');
    final exampleManifest = File('${source.path}/manifests/example/fluoh.yaml');
    final readme = File('${source.path}/README.md');
    final existed =
        await metadata.exists() ||
        await exampleManifest.exists() ||
        await readme.exists();

    await exampleManifest.parent.create(recursive: true);
    if (!await metadata.exists()) {
      await source.create(recursive: true);
      await metadata.writeAsString(_localSourceMetadata(source));
    }
    if (!await exampleManifest.exists()) {
      await exampleManifest.writeAsString(_localSourceManifestTemplate());
    }
    if (!await readme.exists()) {
      await readme.writeAsString(_localSourceReadme());
    }

    if (existed) {
      _output.skipped(
        'Local source template already exists at ${_output.style.path(source.path)}.',
      );
    } else {
      _output.success(
        'Created local source template at ${_output.style.path(source.path)}.',
      );
    }
    _output.next(
      'Edit manifest files directly, or sync released packages with:',
    );
    _output.next('  fluoh source sync ${_output.style.path(source.path)}');
    _output.next(
      'Add it with: fluoh source add <name> ${_output.style.path(source.path)}',
    );
    return 0;
  }
}

class SourceSyncCommand extends Command<int> {
  SourceSyncCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout);

  final FluohEnvironment environment;
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'sync';

  @override
  String get description =>
      'Sync released FlutterOH pub repositories into a source repository.';

  @override
  String get invocation => 'fluoh source sync [path]';

  @override
  Future<int> run() async {
    final rest = expectArgumentCountAtMost(
      argResults!,
      1,
      'Expected zero or one source path.',
      usageException,
    );

    final source = rest.isEmpty
        ? environment.workingDirectory
        : Directory(rest.single);
    if (!await source.exists()) {
      usageException('Source path does not exist: ${source.path}');
    }

    final config = await FluohConfigStore(environment).loadIfExists();
    final configuredSource = config == null
        ? null
        : _configuredSnapshotSource(config, source);
    Directory? tempSource;
    final workingSource = configuredSource == null
        ? source
        : tempSource = await Directory.systemTemp.createTemp(
            'fluoh_source_sync_',
          );
    var repositories = const <_SourceManifestRepository>[];
    try {
      if (configuredSource != null) {
        await copySourceSnapshot(source, workingSource);
      }

      repositories = await _manifestRepositories(source);
      final syncPackages = <_SourceSyncPackage>[];
      for (final repository in repositories) {
        syncPackages.addAll(await _releasedSourcePackages(repository));
      }

      var synced = 0;
      var skipped = 0;
      final results = <_SourceSyncResult>[];
      for (final syncPackage in syncPackages) {
        final repository = syncPackage.repository;
        final manifest = syncPackage.manifest;
        final package = syncPackage.package;
        final result = await _writeSourcePackageMetadata(
          source: workingSource,
          manifestName: syncPackage.sourceManifestName,
          packageName: package.name,
          packageUrl: manifest.repositoryUrl,
          packagePath: package.repositoryPath,
          upstreamGitUrl: manifest.upstreamUrl,
          upstreamBranch: manifest.upstreamBranch,
          upstreamPath: package.upstreamPath,
          upstreamVersion: package.upstreamVersion,
          sdkVersion: manifest.sdkVersion,
          releaseVersion: package.releaseVersion,
          releaseStatus: package.status ?? 'compatible',
          usageException: usageException,
        );
        if (result.skippedFrozen) {
          skipped += 1;
        } else {
          synced += 1;
        }
        results.add(_SourceSyncResult(repository: repository, result: result));
      }

      if (configuredSource != null) {
        await SourceRuntime(environment).saveConfigAndRebuildLock(
          config!,
          snapshots: {configuredSource.key: workingSource},
          output: _output.style.capabilities.decorated ? _output : null,
        );
      }

      for (final item in results) {
        final result = item.result;
        if (result.skippedFrozen) {
          _output.skipped(
            'Skipped source metadata update for ${result.packageName} because '
            'maintenance.status is frozen.',
          );
          if (result.frozenReason != null) {
            _output.next(result.frozenReason!);
          }
        } else {
          _output.success(
            'Synced source metadata for ${result.packageName} from '
            '${_output.style.path(item.repository.path)}.',
          );
        }
      }

      if (synced == 0 && skipped == 0) {
        _output.skipped('No packages were synced.');
      } else {
        _output.next(
          'Synced $synced package${_s(synced)}'
          '${skipped == 0 ? '' : '; skipped $skipped frozen package${_s(skipped)}'}.',
        );
      }
    } finally {
      for (final repository in repositories) {
        await repository.cleanup();
      }
      if (tempSource != null) {
        await deleteIfExists(tempSource);
      }
    }
    return 0;
  }

  Future<List<_SourceManifestRepository>> _manifestRepositories(
    Directory source,
  ) async {
    final root = await _readSourceRootManifest(
      source,
      usageException: usageException,
    );
    if (root.manifests.isEmpty) {
      usageException(
        'Source ${source.path} does not declare any manifest routes.',
      );
    }
    final repositories = <_SourceManifestRepository>[];
    for (final route in root.manifests) {
      final manifest = await _readSourceManifest(source, route.name);
      repositories.add(
        await _sourceManifestRepository(
          name: route.name,
          source: source,
          url: manifest.repositoryGitUrl,
        ),
      );
    }
    repositories.sort((a, b) => a.name.compareTo(b.name));
    return repositories;
  }

  Future<_SourceManifestRepository> _sourceManifestRepository({
    required String name,
    required Directory source,
    required String url,
  }) async {
    final local = localSourceDirectoryFromUrl(url);
    if (local != null) {
      final directory = local.isAbsolute
          ? local
          : Directory('${source.path}/${local.path}');
      await _ensureLocalPubRepository(directory, url);
      return _SourceManifestRepository(name: name, path: directory);
    }

    final directory = Directory(url);
    if (directory.isAbsolute) {
      await _ensureLocalPubRepository(directory, url);
      return _SourceManifestRepository(name: name, path: directory);
    }

    if (!_looksLikeRemoteGitUrl(url)) {
      final sourceRelative = Directory('${source.path}/$url');
      await _ensureLocalPubRepository(sourceRelative, url);
      return _SourceManifestRepository(name: name, path: sourceRelative);
    }

    final temp = await Directory.systemTemp.createTemp('fluoh_pub_repo_');
    try {
      await git(['clone', '--quiet', url, temp.path]);
      return _SourceManifestRepository(name: name, path: temp, temporary: true);
    } catch (_) {
      await deleteIfExists(temp);
      rethrow;
    }
  }

  Future<List<_SourceSyncPackage>> _releasedSourcePackages(
    _SourceManifestRepository repository,
  ) async {
    final tags = await _releaseTags(repository.path);
    final packages = <_SourceSyncPackage>[];
    for (final tag in tags) {
      final manifest = await _readTaggedPubManifest(repository.path, tag);
      if (manifest == null) {
        continue;
      }
      for (final package in manifest.packages) {
        final String expectedTag;
        try {
          expectedTag = package.releaseTag(manifest.sdkVersion);
        } on FormatException catch (error) {
          usageException(
            'Could not read pub repository ${repository.path.path} at tag $tag: '
            '${error.message}',
          );
        }
        if (expectedTag != tag) {
          continue;
        }
        packages.add(
          _SourceSyncPackage(
            sourceManifestName: repository.name,
            repository: repository.path,
            manifest: manifest,
            package: package,
          ),
        );
      }
    }
    if (packages.isEmpty) {
      usageException(
        'No released Package fluoh.yaml records found in ${repository.path.path}. '
        'Run "fluoh pub release" first or fetch tags before syncing.',
      );
    }
    return packages;
  }

  Future<List<String>> _releaseTags(Directory repository) async {
    final result = await runGit(
      ['tag', '--list'],
      workingDirectory: repository,
      allowFailure: true,
    );
    if (result.exitCode != 0) {
      usageException(
        'Could not list release tags in ${repository.path}: ${result.stderr}',
      );
    }
    final tags =
        result.stdout
            .toString()
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.contains('-ohos-'))
            .toList(growable: false)
          ..sort();
    return tags;
  }

  Future<PubManifest?> _readTaggedPubManifest(
    Directory repository,
    String tag,
  ) async {
    final result = await runGit(
      ['show', '$tag:fluoh.yaml'],
      workingDirectory: repository,
      allowFailure: true,
    );
    if (result.exitCode != 0) {
      return null;
    }
    try {
      return PubRepositoryManifest.parse(result.stdout.toString());
    } on FormatException catch (error) {
      usageException(
        'Could not read pub repository ${repository.path} at tag $tag: '
        '${error.message}',
      );
    }
  }

  Future<SourceManifest> _readSourceManifest(
    Directory source,
    String name,
  ) async {
    final manifestPath = 'manifests/$name/fluoh.yaml';
    final file = File('${source.path}/$manifestPath');
    try {
      return parseSourceManifest(
        content: await file.readAsString(),
        label: manifestPath,
      );
    } on FormatException catch (error) {
      usageException(error.message);
    } on FileSystemException catch (error) {
      usageException(
        'Could not read source manifest $manifestPath: ${fileSystemMessage(error)}',
      );
    }
  }

  Future<void> _ensureLocalPubRepository(
    Directory directory,
    String url,
  ) async {
    if (!await directory.exists()) {
      usageException('Pub repository path does not exist for $url.');
    }
    if (!await File('${directory.path}/fluoh.yaml').exists()) {
      usageException('Pub repository ${directory.path} is missing fluoh.yaml.');
    }
  }
}

class _SourceManifestRepository {
  const _SourceManifestRepository({
    required this.name,
    required this.path,
    this.temporary = false,
  });

  final String name;
  final Directory path;
  final bool temporary;

  Future<void> cleanup() async {
    if (temporary) {
      await deleteIfExists(path);
    }
  }
}

class _SourceSyncResult {
  const _SourceSyncResult({required this.repository, required this.result});

  final Directory repository;
  final _SourcePackageMetadataResult result;
}

class _SourceSyncPackage {
  const _SourceSyncPackage({
    required this.sourceManifestName,
    required this.repository,
    required this.manifest,
    required this.package,
  });

  final String sourceManifestName;
  final Directory repository;
  final PubManifest manifest;
  final PubManifestPackage package;
}

class _SourcePackageMetadataResult {
  const _SourcePackageMetadataResult({
    required this.packageName,
    required this.repositoryPath,
    required this.skippedFrozen,
    this.frozenReason,
  });

  final String packageName;
  final String repositoryPath;
  final bool skippedFrozen;
  final String? frozenReason;
}

Future<_SourcePackageMetadataResult> _writeSourcePackageMetadata({
  required Directory source,
  required String manifestName,
  required String packageName,
  required String packageUrl,
  required String packagePath,
  required String upstreamGitUrl,
  required String upstreamBranch,
  required String upstreamPath,
  required String upstreamVersion,
  required String sdkVersion,
  required String releaseVersion,
  required String releaseStatus,
  required Never Function(String message) usageException,
}) async {
  if (!const {'compatible', 'experimental', 'broken'}.contains(releaseStatus)) {
    usageException(
      'Expected release status to be compatible, experimental, or broken.',
    );
  }
  try {
    validateReleaseVersion(releaseVersion);
  } on FormatException catch (error) {
    usageException(error.message);
  }
  final sourceManifest = await _readSourceRootManifest(
    source,
    usageException: usageException,
  );
  manifestName = _validatedSourceName(manifestName);
  final manifestPath = 'manifests/$manifestName';
  final manifestFile = File('${source.path}/$manifestPath/fluoh.yaml');
  final packageTemplate = SourceManifestPackageTemplate(
    name: packageName,
    repositoryPath: packagePath,
    upstreamPath: upstreamPath,
    upstreamVersion: upstreamVersion,
    version: releaseVersion,
    sdkLine: sdkLineFromSdkVersion(sdkVersion),
    status: releaseStatus,
  );

  final _SourceManifestUpdate manifestUpdate;
  try {
    manifestUpdate = await _updatedSourceManifest(
      manifestFile: manifestFile,
      manifestName: manifestName,
      repositoryUrl: packageUrl,
      upstreamGitUrl: upstreamGitUrl,
      upstreamBranch: upstreamBranch,
      package: packageTemplate,
      usageException: usageException,
    );
  } on FormatException catch (error) {
    usageException(error.message);
  }

  final nextSourceManifest = SourceRootManifestTemplate(
    name: sourceManifest.name,
    description: sourceManifest.description,
    repositoryGitUrl: sourceManifest.repositoryGitUrl,
    fluohConstraint: sourceManifest.fluohConstraint,
    sdkRepository: sourceManifest.sdkRepository,
    sdkReleases: sourceManifest.sdkReleases,
    manifests: _updatedManifestRoutes(
      sourceManifest.manifests,
      manifestName: manifestName,
    ),
  );
  final rootFile = File('${source.path}/fluoh.yaml');
  final writes = <File, String>{
    rootFile: sourceRootManifestContent(nextSourceManifest),
  };
  if (!manifestUpdate.skippedFrozen) {
    writes[manifestFile] = sourceManifestToContent(manifestUpdate.manifest);
  }
  try {
    await _writeFilesAtomically(writes);
  } on FileSystemException catch (error) {
    usageException(
      'Could not write source metadata: ${fileSystemMessage(error)}',
    );
  }

  return _SourcePackageMetadataResult(
    packageName: packageName,
    repositoryPath: manifestPath,
    skippedFrozen: manifestUpdate.skippedFrozen,
    frozenReason: manifestUpdate.frozenReason,
  );
}

Future<SourceRootManifest> _readSourceRootManifest(
  Directory source, {
  required Never Function(String message) usageException,
}) async {
  final file = File('${source.path}/fluoh.yaml');
  if (!await file.exists()) {
    usageException(
      'Missing fluoh.yaml. Run "fluoh source init ${source.path}" first.',
    );
  }
  try {
    return parseSourceRootManifest(await file.readAsString());
  } on FormatException catch (error) {
    usageException(error.message);
  }
}

Future<void> _writeFilesAtomically(Map<File, String> writes) async {
  if (writes.isEmpty) {
    return;
  }

  final suffix = DateTime.now().microsecondsSinceEpoch;
  final temps = <File, File>{};
  final backups = <File, File?>{};
  final replacedTargets = <File>[];
  try {
    for (final entry in writes.entries) {
      final target = entry.key;
      await target.parent.create(recursive: true);
      final temp = File('${target.path}.fluoh-next-$suffix');
      await temp.writeAsString(entry.value);
      temps[target] = temp;
    }

    for (final target in writes.keys) {
      final temp = temps[target]!;
      if (await target.exists()) {
        final backup = File('${target.path}.fluoh-previous-$suffix');
        await target.rename(backup.path);
        backups[target] = backup;
      } else {
        backups[target] = null;
      }
      await temp.rename(target.path);
      replacedTargets.add(target);
    }
  } catch (_) {
    for (final target in replacedTargets.reversed) {
      if (await target.exists()) {
        await target.delete();
      }
    }
    for (final entry in backups.entries) {
      final backup = entry.value;
      if (backup != null && await backup.exists()) {
        await backup.rename(entry.key.path);
      }
    }
    rethrow;
  } finally {
    for (final temp in temps.values) {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
    for (final backup in backups.values) {
      if (backup != null && await backup.exists()) {
        await backup.delete();
      }
    }
  }
}

Future<_SourceManifestUpdate> _updatedSourceManifest({
  required File manifestFile,
  required String manifestName,
  required String repositoryUrl,
  required String upstreamGitUrl,
  required String upstreamBranch,
  required SourceManifestPackageTemplate package,
  required Never Function(String message) usageException,
}) async {
  if (!await manifestFile.exists()) {
    return _SourceManifestUpdate(
      manifest: parseSourceManifest(
        content: sourceManifestContent(
          SourceManifestTemplate(
            name: manifestName,
            repositoryGitUrl: repositoryUrl,
            upstreamGitUrl: upstreamGitUrl,
            upstreamBranch: upstreamBranch,
            packages: [package],
          ),
        ),
        label: manifestFile.path,
      ),
    );
  }

  final existing = parseSourceManifest(
    content: await manifestFile.readAsString(),
    label: manifestFile.path,
  );
  if (existing.repositoryGitUrl != repositoryUrl) {
    usageException(
      'Manifest ${existing.name} already uses git URL '
      '${existing.repositoryGitUrl}.',
    );
  }
  if (existing.upstreamGitUrl != upstreamGitUrl) {
    usageException(
      'Manifest ${existing.name} already uses upstream '
      '${existing.upstreamGitUrl}.',
    );
  }

  final packages = {...existing.packages};
  final currentPackage = packages[package.name];
  if (currentPackage?.maintenance?.status == 'frozen') {
    return _SourceManifestUpdate(
      manifest: existing,
      skippedFrozen: true,
      frozenReason: currentPackage!.maintenance!.reason,
    );
  }
  final release = SourceManifestRelease(
    version: package.version,
    upstreamVersion: package.upstreamVersion,
    status: package.status,
  );
  final sdk = SourceManifestSdk(sdkLine: package.sdkLine, releases: [release]);

  if (currentPackage == null) {
    packages[package.name] = SourceManifestPackage(
      name: package.name,
      repositoryPath: package.repositoryPath,
      upstreamPath: package.upstreamPath,
      sdks: {package.sdkLine: sdk},
    );
  } else {
    if (currentPackage.repositoryPath != package.repositoryPath) {
      usageException(
        'Package ${package.name} already uses path '
        '${currentPackage.repositoryPath}.',
      );
    }
    if (currentPackage.upstreamPath != package.upstreamPath) {
      usageException(
        'Package ${package.name} already uses upstream path '
        '${currentPackage.upstreamPath}.',
      );
    }
    final sdks = {...currentPackage.sdks};
    final currentSdk = sdks[package.sdkLine];
    sdks[package.sdkLine] = currentSdk == null
        ? sdk
        : SourceManifestSdk(
            sdkLine: currentSdk.sdkLine,
            releases: _upsertManifestRelease(currentSdk.releases, release),
          );
    packages[package.name] = SourceManifestPackage(
      name: currentPackage.name,
      repositoryPath: currentPackage.repositoryPath,
      upstreamPath: currentPackage.upstreamPath,
      maintenance: currentPackage.maintenance,
      advisory: currentPackage.advisory,
      sdks: sdks,
    );
  }

  return _SourceManifestUpdate(
    manifest: SourceManifest(
      schemaVersion: existing.schemaVersion,
      name: existing.name,
      repositoryGitUrl: existing.repositoryGitUrl,
      repositoryPath: existing.repositoryPath,
      upstreamGitUrl: existing.upstreamGitUrl,
      upstreamBranch: upstreamBranch,
      upstreamPath: existing.upstreamPath,
      packages: packages,
    ),
  );
}

class _SourceManifestUpdate {
  const _SourceManifestUpdate({
    required this.manifest,
    this.skippedFrozen = false,
    this.frozenReason,
  });

  final SourceManifest manifest;
  final bool skippedFrozen;
  final String? frozenReason;
}

List<SourceManifestRelease> _upsertManifestRelease(
  List<SourceManifestRelease> releases,
  SourceManifestRelease release,
) {
  final next = releases.toList(growable: true);
  final index = next.indexWhere(
    (existing) =>
        existing.version == release.version &&
        existing.upstreamVersion == release.upstreamVersion,
  );
  if (index == -1) {
    next.add(release);
  } else {
    next[index] = release;
  }
  return next;
}

class SourceAddCommand extends Command<int> {
  SourceAddCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser.addOption(
      'priority',
      valueHelp: 'int',
      help: 'Source priority. Higher values win when indexes overlap.',
      defaultsTo: '$defaultSourcePriority',
    );
  }

  final FluohEnvironment environment;
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'add';

  @override
  String get description => 'Add a data source.';

  @override
  String get invocation => 'fluoh source add <name> <url-or-path>';

  @override
  Future<int> run() async {
    final rest = expectArgumentCount(
      argResults!,
      2,
      'Expected a source name and URL or path.',
      usageException,
    );

    final name = rest[0];
    _ensureValidSourceName(name);
    if (name == defaultSourceName) {
      usageException('Cannot replace the official source.');
    }
    final urlOrPath = rest[1];
    final priority = int.tryParse(argResults!.option('priority') ?? '');
    if (priority == null) {
      usageException('Expected --priority to be an integer.');
    }
    final localUrlDirectory = localSourceDirectoryFromUrl(urlOrPath);
    final localSource = localUrlDirectory ?? Directory(urlOrPath);
    final isLocalSource = await localSource.exists();
    if (localUrlDirectory != null && !isLocalSource) {
      usageException('Source path does not exist: ${localSource.path}');
    }
    if (!isLocalSource && !_looksLikeGitSource(urlOrPath)) {
      usageException('Source path does not exist: $urlOrPath');
    }

    final store = FluohConfigStore(environment);
    final config = await store.load();
    final cachePath = '${environment.homeDirectory.path}/sources/$name';
    final updated = localUrlDirectory == null && isLocalSource
        ? config.addSource(name, cachePath, priority: priority)
        : config.addGitSource(name, urlOrPath, cachePath, priority: priority);
    Directory? snapshot;
    try {
      snapshot = isLocalSource
          ? await prepareLocalSourceSnapshot(name, localSource)
          : await prepareGitSourceSnapshot(
              name,
              SourceConfig(path: cachePath, url: urlOrPath),
            );
      await SourceRuntime(environment).saveConfigAndRebuildLock(
        updated,
        snapshots: {name: snapshot},
        output: _output.style.capabilities.decorated ? _output : null,
      );
    } finally {
      if (snapshot != null) {
        await deleteIfExists(snapshot);
      }
    }
    _output.success('Added source $name: ${_output.style.path(urlOrPath)}');
    return 0;
  }
}

class SourceRemoveCommand extends Command<int> {
  SourceRemoveCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout);

  final FluohEnvironment environment;
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'remove';

  @override
  String get description => 'Remove a non-official data source.';

  @override
  String get invocation => 'fluoh source remove <name>';

  @override
  Future<int> run() async {
    final rest = expectArgumentCount(
      argResults!,
      1,
      'Expected a source name.',
      usageException,
    );

    final name = rest.single;
    _ensureValidSourceName(name);
    final store = FluohConfigStore(environment);
    final config = await store.load();
    try {
      await SourceRuntime(environment).saveConfigAndRebuildLock(
        config.removeSource(name),
        output: _output.style.capabilities.decorated ? _output : null,
      );
    } on ArgumentError catch (error) {
      usageException(error.message);
    }
    _output.success('Removed source $name.');
    return 0;
  }
}

class SourceUpdateCommand extends Command<int> {
  SourceUpdateCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout);

  final FluohEnvironment environment;
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'update';

  @override
  String get description => 'Validate and refresh configured data sources.';

  @override
  String get invocation => 'fluoh source update [name]';

  @override
  Future<int> run() async {
    final rest = expectArgumentCountAtMost(
      argResults!,
      1,
      'Expected zero or one source name.',
      usageException,
    );
    final config = await FluohConfigStore(environment).load();

    final sources = rest.isEmpty
        ? config.sources.entries.toList(growable: false)
        : [_sourceEntry(config, _validatedSourceName(rest.single))];
    if (sources.isEmpty) {
      usageException('No sources configured.');
    }

    final snapshots = <String, Directory>{};
    try {
      for (final entry in sources) {
        final sourceConfig = entry.value;
        if (sourceConfig.url != null) {
          final localSource = localSourceDirectoryFromUrl(sourceConfig.url);
          snapshots[entry.key] = localSource == null
              ? await prepareGitSourceSnapshot(
                  entry.key,
                  sourceConfig,
                  output: _output,
                )
              : await prepareLocalSourceSnapshot(entry.key, localSource);
        } else {
          await validateSource(entry.key, sourceConfig);
        }
      }

      await SourceRuntime(environment).saveConfigAndRebuildLock(
        config,
        snapshots: snapshots,
        output: _output.style.capabilities.decorated ? _output : null,
      );
    } finally {
      for (final snapshot in snapshots.values) {
        await deleteIfExists(snapshot);
      }
    }

    for (final entry in sources) {
      _output.success('Updated source ${entry.key}.');
    }
    return 0;
  }
}

MapEntry<String, SourceConfig> _sourceEntry(FluohConfig config, String name) {
  final source = config.sources[name];
  if (source == null) {
    throw UsageException('Unknown source "$name".', '');
  }
  return MapEntry(name, source);
}

MapEntry<String, SourceConfig>? _configuredSnapshotSource(
  FluohConfig config,
  Directory source,
) {
  final sourcePath = source.absolute.path;
  for (final entry in config.sources.entries) {
    if (entry.value.directory.absolute.path == sourcePath) {
      return entry;
    }
  }
  return null;
}

String _validatedSourceName(String name) {
  final error = sourceNameValidationError(name);
  if (error != null) {
    throw UsageException('Invalid source name "$name": $error', '');
  }
  return name;
}

void _ensureValidSourceName(String name) {
  _validatedSourceName(name);
}

bool _looksLikeGitSource(String value) {
  return value.startsWith('file:') ||
      _looksLikeRemoteGitUrl(value) ||
      value.endsWith('.git');
}

bool _looksLikeRemoteGitUrl(String value) {
  return value.contains('://') ||
      RegExp(r'^[^@\s]+@[^:\s]+:.+').hasMatch(value);
}

String _s(int count) => count == 1 ? '' : 's';

String _localSourceReadme() {
  return '''
# FlutterOH Source

Maintain SDK versions and package adaptation metadata in this directory, then register it with:

```sh
fluoh source add <name> .
```

Sync released pub repositories with:

```sh
fluoh source sync .
```

Root `fluoh.yaml` declares SDK versions and package routing.
`manifests/example/fluoh.yaml` contains a commented Manifest template.
Copy or rename it when adding package routing, or let `fluoh source sync`
create released package metadata from Manifest repository URLs.
Edit Manifest files directly for advisory and maintenance notes.

The `pub` repository can be maintained as a source and add scheduled workflows on top of these files.
''';
}

String _localSourceMetadata(Directory source) {
  return [
    'schema: 1',
    'kind: source',
    'name: "Local FlutterOH source"',
    'description: "Local FlutterOH source maintained by fluoh users."',
    '',
    'repository:',
    '  git:',
    '    url: ${_yamlScalar('file:${source.path}')}',
    '',
    'environment:',
    '  fluoh: ">=0.1.0"',
    '',
    '# Uncomment to publish Flutter OHOS SDK versions from this source.',
    '# sdk:',
    '#   git:',
    '#     url: "https://github.com/openharmony-sig/flutter_flutter.git"',
    '#   versions:',
    '#     - 3.35.8-ohos-0.0.3',
    '',
    '# Uncomment after editing manifests/example/fluoh.yaml, or run:',
    '# fluoh source sync .',
    '# manifests:',
    '#   - name: example',
    '',
  ].join('\n');
}

String _localSourceManifestTemplate() {
  return [
    '# schema: 1',
    '# kind: manifest',
    '# name: example',
    '#',
    '# repository:',
    '#   git:',
    '#     url: "https://github.com/FlutterOH/example.git"',
    '#',
    '# upstream:',
    '#   git:',
    '#     url: "https://github.com/example/upstream.git"',
    '#     branch: main',
    '#',
    '# packages:',
    '#   example_package:',
    '#     repository:',
    '#       path: .',
    '#     upstream:',
    '#       path: .',
    '#     # maintenance:',
    '#     #   status: frozen',
    '#     #   reason: Upstream now supports OHOS natively.',
    '#     # advisory:',
    '#     #   message: Prefer upstream example_package for new projects.',
    '#     sdks:',
    '#       "3.35":',
    '#         releases:',
    '#           - version: "0.1.0"',
    '#             upstreamVersion: "1.0.0"',
    '#             # status: experimental',
    '',
  ].join('\n');
}

List<SourceManifestRoute> _updatedManifestRoutes(
  List<SourceManifestRoute> routes, {
  required String manifestName,
}) {
  if (routes.any((route) => route.name == manifestName)) {
    return routes;
  }
  return [...routes, SourceManifestRoute(name: manifestName)];
}

String _yamlScalar(String value) {
  if (!_shouldQuoteYamlScalar(value)) {
    return value;
  }
  final escaped = value
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\t', '\\t');
  return '"$escaped"';
}

bool _shouldQuoteYamlScalar(String value) {
  if (value.isEmpty) {
    return true;
  }
  if (value.startsWith(RegExp(r'''[-?:,[\]{}#&*!|>@`"']'''))) {
    return true;
  }
  if (value.contains(RegExp(r'[\s:]'))) {
    return true;
  }
  if (const {'true', 'false', 'null', '~'}.contains(value.toLowerCase())) {
    return true;
  }
  return false;
}
