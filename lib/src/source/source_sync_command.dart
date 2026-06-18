part of 'source_commands.dart';

/// Synchronizes Source manifests from package release tags.
class SourceSyncCommand extends FluohCommand<int> {
  /// Creates the Source sync command.
  SourceSyncCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the source sync result as JSON.',
      )
      ..addMultiOption(
        'manifest',
        valueHelp: 'name',
        help:
            'Limit sync to a Source manifest route. May be passed more than '
            'once.',
      )
      ..addMultiOption(
        'package',
        valueHelp: 'name',
        help: 'Limit sync to a package name. May be passed more than once.',
      )
      ..addOption(
        'concurrency',
        valueHelp: 'count',
        defaultsTo: '4',
        help: 'Maximum repository tag discovery operations to run in parallel.',
      );
  }

  /// Runtime environment used to resolve repository paths.
  final FluohEnvironment environment;

  /// Writer used for JSON output.
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'sync';

  @override
  String get description =>
      'Import later releases for packages already routed by a Source repository.';

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
    final json = argResults!.flag('json');
    final manifestFilters = _multiOptionSet(argResults!, 'manifest');
    final packageFilters = _multiOptionSet(argResults!, 'package');
    final concurrency = _positiveIntOption(
      argResults!,
      'concurrency',
      defaultValue: 4,
    );

    final source = rest.isEmpty
        ? environment.workingDirectory
        : _resolveUserSourceDirectory(
            environment.workingDirectory,
            Directory(rest.single),
          );
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
    var plan = const <_SourceSyncRoutePlan>[];
    try {
      if (configuredSource != null) {
        await copySourceSnapshot(source, workingSource);
      }

      plan = await _sourceSyncPlan(
        source,
        manifestFilters: manifestFilters,
        packageFilters: packageFilters,
        concurrency: concurrency,
      );
      final openedRepositories = <_SourceManifestRepository>[];
      repositories = openedRepositories;
      final tagsByRepository = <String, Set<String>>{};
      for (final item in plan) {
        if (item.tagsToSync.isEmpty) {
          continue;
        }
        tagsByRepository
            .putIfAbsent(item.resolvedRepository, () => <String>{})
            .addAll(item.tagsToSync);
      }
      final repositoryCache = <String, _SourceManifestRepository>{};
      final syncPackages = <_SourceSyncPackage>[];
      for (var index = 0; index < plan.length; index += 1) {
        final item = plan[index];
        if (item.tagsToSync.isEmpty) {
          continue;
        }
        var repository = repositoryCache[item.resolvedRepository];
        if (repository == null) {
          final tagsToFetch =
              tagsByRepository[item.resolvedRepository]!.toList()..sort();
          repository = await _sourceManifestRepository(
            url: item.resolvedRepository,
            displayPath: _syncRepositoryDisplayPath(item),
            tags: tagsToFetch,
          );
          repositoryCache[item.resolvedRepository] = repository;
          openedRepositories.add(repository);
        }
        final released = await _releasedSourcePackages(
          repository,
          sourceManifestName: item.manifestName,
          tags: item.tagsToSync,
          packageFilters: packageFilters,
          expectedPackagePath: item.packagePath,
        );
        syncPackages.addAll(released.packages);
        if (released.skippedTags.isNotEmpty) {
          plan[index] = item.withAdditionalSkippedTags(released.skippedTags);
        }
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
          packagePath: package.path,
          originKind: manifest.originKind,
          upstreamGitUrl: manifest.upstreamUrl,
          upstreamVersion: package.upstreamVersion,
          upstreamRef: package.upstreamRef,
          upstreamCommit: package.upstreamCommit,
          sdkVersion: manifest.sdkVersion,
          releaseVersion: package.releaseVersion,
          releaseTag: syncPackage.releaseTag,
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
          output: json
              ? null
              : _output.style.capabilities.decorated
              ? _output
              : null,
        );
      }

      if (json) {
        writeMachineOutput(
          stdout,
          command: 'source sync',
          ok: true,
          exitCode: 0,
          fields: {
            'source': source.path,
            'configuredSource': configuredSource?.key,
            'synced': synced,
            'skipped': skipped,
            'skippedTags': plan.fold<int>(
              0,
              (count, item) => count + item.skippedTags.length,
            ),
            'plan': plan.map((item) => item.toJson()).toList(),
            'packages': results.map((result) => result.toJson()).toList(),
          },
        );
      } else {
        for (final item in plan) {
          for (final tag in item.skippedTags) {
            _output.skipped(_sourceSyncSkippedTagMessage(tag));
          }
        }
        for (final item in results) {
          final result = item.result;
          if (result.skippedFrozen) {
            _output.skipped(
              'Skipped source metadata update for ${result.packageName} because '
              'maintenance.frozen is true',
            );
            if (result.frozenReason != null) {
              _output.next(result.frozenReason!);
            }
          } else {
            _output.success(
              'Synced source metadata for ${result.packageName} from '
              '${_output.style.path(item.repository)}',
            );
          }
        }

        if (synced == 0 && skipped == 0) {
          _output.skipped('No packages were synced');
        } else {
          _output.next(
            'Synced $synced package${_s(synced)}'
            '${skipped == 0 ? '' : '; skipped $skipped frozen package${_s(skipped)}'}',
          );
        }
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

  Future<List<_SourceSyncRoutePlan>> _sourceSyncPlan(
    Directory source, {
    required Set<String> manifestFilters,
    required Set<String> packageFilters,
    required int concurrency,
  }) async {
    final root = await _readSourceRootManifest(
      source,
      usageException: usageException,
    );
    if (root.manifests.isEmpty) {
      return const [];
    }
    final supportedSdkLines = _supportedSdkLines(root);
    final routes = root.manifests
        .where(
          (route) =>
              manifestFilters.isEmpty || manifestFilters.contains(route.name),
        )
        .toList(growable: false);
    if (routes.isEmpty) {
      return const [];
    }
    final plan = List<_SourceSyncRoutePlan?>.filled(routes.length, null);
    final tagDiscovery = <String, Future<Set<String>>>{};
    var nextIndex = 0;

    Future<void> worker() async {
      while (nextIndex < routes.length) {
        final index = nextIndex;
        nextIndex += 1;
        final route = routes[index];
        final manifest = await _readSourceManifest(source, route.name);
        final routePackageName = manifest.package.name;
        final routePackageFilters = packageFilters.isEmpty
            ? {routePackageName}
            : packageFilters.intersection({routePackageName});
        final resolvedRepository = _resolveSyncRepositoryUrl(
          source,
          manifest.repositoryGitUrl,
        );
        final discoveredTags = await tagDiscovery.putIfAbsent(
          resolvedRepository,
          () => _lsRemoteReleaseTags(resolvedRepository, source: source),
        );
        final knownTags = routePackageFilters.isEmpty
            ? <String>{}
            : _declaredReleaseTags(
                manifest,
                packageFilters: routePackageFilters,
              );
        final selectedTags = routePackageFilters.isEmpty
            ? <String>[]
            : _filterTagsForPackages(
                discoveredTags,
                packageFilters: routePackageFilters,
              );
        final newTags = selectedTags
            .where((tag) => !knownTags.contains(tag))
            .toList(growable: false);
        final skippedTags = _skippedTagsForUnsupportedSdkLines(
          newTags,
          supportedSdkLines: supportedSdkLines,
        );
        final skippedTagNames = {
          for (final skippedTag in skippedTags) skippedTag.tag,
        };
        final tagsToSync =
            newTags.where((tag) => !skippedTagNames.contains(tag)).toList()
              ..sort();
        final knownTagList = knownTags.toList(growable: false)..sort();
        final discoveredTagList = selectedTags.toList(growable: false)..sort();
        plan[index] = _SourceSyncRoutePlan(
          manifestName: route.name,
          packageName: routePackageName,
          packagePath: manifest.package.path,
          repository: manifest.repositoryGitUrl,
          resolvedRepository: resolvedRepository,
          knownTags: knownTagList,
          discoveredTags: discoveredTagList,
          tagsToSync: tagsToSync,
          skippedTags: skippedTags,
        );
      }
    }

    final workerCount = concurrency < routes.length
        ? concurrency
        : routes.length;
    await Future.wait([for (var i = 0; i < workerCount; i += 1) worker()]);
    final resolvedPlan = plan.whereType<_SourceSyncRoutePlan>().toList(
      growable: false,
    );
    resolvedPlan.sort((a, b) => a.manifestName.compareTo(b.manifestName));
    return resolvedPlan;
  }

  Future<_SourceManifestRepository> _sourceManifestRepository({
    required String url,
    required String displayPath,
    required List<String> tags,
  }) async {
    final temp = await Directory.systemTemp.createTemp('fluoh_package_repo_');
    try {
      await runGit(['init', '--quiet'], workingDirectory: temp);
      await runGit(['remote', 'add', 'origin', url], workingDirectory: temp);
      await _fetchRepositoryTags(temp, url: url, tags: tags);
      return _SourceManifestRepository(
        path: temp,
        displayPath: displayPath,
        temporary: true,
      );
    } catch (_) {
      await deleteIfExists(temp);
      rethrow;
    }
  }

  Future<_ReleasedSourcePackages> _releasedSourcePackages(
    _SourceManifestRepository repository, {
    required String sourceManifestName,
    required List<String> tags,
    required Set<String> packageFilters,
    required String expectedPackagePath,
  }) async {
    final packages = <_SourceSyncPackage>[];
    final skippedTags = <_SourceSyncSkippedTag>[];
    for (final tag in tags) {
      final tagged = await _readTaggedPackageManifest(repository.path, tag);
      if (tagged.skippedTag != null) {
        skippedTags.add(tagged.skippedTag!);
        continue;
      }
      final manifest = tagged.manifest;
      if (manifest == null) {
        continue;
      }
      final package = manifest.package;
      final bool matchesTag;
      try {
        matchesTag = package.matchesReleaseTag(manifest.sdkVersion, tag);
      } on FormatException catch (error) {
        skippedTags.add(
          _skippedTagFor(
            tag,
            reason: 'invalid-package-metadata',
            message: error.message,
          ),
        );
        continue;
      }
      if (!matchesTag) {
        skippedTags.add(_skippedTagFor(tag, reason: 'tag-metadata-mismatch'));
        continue;
      }
      if (package.path != expectedPackagePath) {
        skippedTags.add(
          _skippedTagFor(
            tag,
            reason: 'package-path-mismatch',
            message:
                'package.path is ${package.path}, expected $expectedPackagePath',
          ),
        );
        continue;
      }
      if (packageFilters.isNotEmpty && !packageFilters.contains(package.name)) {
        continue;
      }
      packages.add(
        _SourceSyncPackage(
          sourceManifestName: sourceManifestName,
          repository: repository.displayPath,
          manifest: manifest,
          package: package,
          releaseTag: tag,
        ),
      );
    }
    skippedTags.sort((a, b) => a.tag.compareTo(b.tag));
    return _ReleasedSourcePackages(
      packages: packages,
      skippedTags: skippedTags,
    );
  }

  Future<_TaggedPackageManifestRead> _readTaggedPackageManifest(
    Directory repository,
    String tag,
  ) async {
    final result = await runGit(
      ['show', '$tag:fluoh.yaml'],
      workingDirectory: repository,
      allowFailure: true,
    );
    if (result.exitCode != 0) {
      return _TaggedPackageManifestRead(
        skippedTag: _skippedTagFor(tag, reason: 'missing-package-manifest'),
      );
    }
    try {
      return _TaggedPackageManifestRead(
        manifest: PackageManifest.parse(result.stdout.toString()),
      );
    } on FormatException catch (error) {
      return _TaggedPackageManifestRead(
        skippedTag: _skippedTagFor(
          tag,
          reason: 'invalid-package-manifest',
          message: error.message,
        ),
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
}
