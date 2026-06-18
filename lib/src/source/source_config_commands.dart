part of 'source_commands.dart';

/// Enables a Source in the persisted local configuration.
class SourceEnableCommand extends FluohCommand<int> {
  /// Creates the Source enable command.
  SourceEnableCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print the Source enablement result as JSON.',
    );
    argParser.addOption(
      'priority',
      valueHelp: 'int',
      help: 'Source priority. Higher values win when indexes overlap.',
      defaultsTo: '$defaultSourcePriority',
    );
  }

  /// Runtime environment containing config and cache paths.
  final FluohEnvironment environment;

  /// Writer kept for command construction consistency.
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'enable';

  @override
  String get description => 'Enable a Source for this machine.';

  @override
  String get invocation => 'fluoh source enable <name> <url-or-path>';

  @override
  Future<int> run() async {
    final json = argResults!.flag('json');
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
    final localSource = _resolveUserSourceDirectory(
      environment.workingDirectory,
      localUrlDirectory ?? Directory(urlOrPath),
    );
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
    final sourceUrl = isLocalSource ? _localSourceUrl(localSource) : urlOrPath;
    final updated = config.addGitSource(
      name,
      sourceUrl,
      cachePath,
      priority: priority,
    );
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
        output: !json && _output.style.capabilities.decorated ? _output : null,
      );
    } finally {
      if (snapshot != null) {
        await deleteIfExists(snapshot);
      }
    }
    if (json) {
      writeMachineOutput(
        stdout,
        command: 'source enable',
        ok: true,
        exitCode: 0,
        fields: {
          'name': name,
          'source': urlOrPath,
          'url': sourceUrl,
          'path': cachePath,
          'priority': priority,
        },
      );
      return 0;
    }
    _output.success('Enabled source $name: ${_output.style.path(urlOrPath)}');
    return 0;
  }
}

/// Disables a non-official Source in the persisted local configuration.
class SourceDisableCommand extends FluohCommand<int> {
  /// Creates the Source disable command.
  SourceDisableCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print the Source disablement result as JSON.',
    );
  }

  /// Runtime environment containing config and cache paths.
  final FluohEnvironment environment;

  /// Writer kept for command construction consistency.
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'disable';

  @override
  String get description =>
      'Disable a non-official Source in local configuration.';

  @override
  String get invocation => 'fluoh source disable <name>';

  @override
  Future<int> run() async {
    final json = argResults!.flag('json');
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
        output: !json && _output.style.capabilities.decorated ? _output : null,
      );
    } on ArgumentError catch (error) {
      usageException(error.message);
    }
    if (json) {
      writeMachineOutput(
        stdout,
        command: 'source disable',
        ok: true,
        exitCode: 0,
        fields: {'name': name, 'disabled': true},
      );
      return 0;
    }
    _output.success('Disabled source $name');
    return 0;
  }
}

/// Refreshes configured Source snapshots.
class SourceUpdateCommand extends FluohCommand<int> {
  /// Creates the Source update command.
  SourceUpdateCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print refreshed Source snapshots as JSON.',
    );
  }

  /// Runtime environment containing config and cache paths.
  final FluohEnvironment environment;

  /// Writer kept for command construction consistency.
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'update';

  @override
  String get description => 'Refresh local snapshots for configured Sources.';

  @override
  String get invocation => 'fluoh source update [name]';

  @override
  Future<int> run() async {
    final json = argResults!.flag('json');
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
                  output: json ? null : _output,
                )
              : await prepareLocalSourceSnapshot(
                  entry.key,
                  _resolveUserSourceDirectory(
                    environment.workingDirectory,
                    localSource,
                  ),
                );
        } else {
          await validateSource(entry.key, sourceConfig);
        }
      }

      await SourceRuntime(environment).saveConfigAndRebuildLock(
        config,
        snapshots: snapshots,
        output: !json && _output.style.capabilities.decorated ? _output : null,
      );
    } finally {
      for (final snapshot in snapshots.values) {
        await deleteIfExists(snapshot);
      }
    }

    if (json) {
      writeMachineOutput(
        stdout,
        command: 'source update',
        ok: true,
        exitCode: 0,
        fields: {
          'count': sources.length,
          'sources': [
            for (final entry in sources)
              {
                'name': entry.key,
                'source': entry.value.url ?? entry.value.path,
                'url': entry.value.url,
                'path': entry.value.path,
                'priority': entry.value.priority,
              },
          ],
        },
      );
      return 0;
    }
    for (final entry in sources) {
      _output.success('Updated source ${entry.key}');
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

Directory _resolveUserSourceDirectory(
  Directory workingDirectory,
  Directory directory,
) {
  if (directory.isAbsolute) {
    return directory;
  }
  return Directory('${workingDirectory.path}/${directory.path}');
}

String _localSourceUrl(Directory directory) {
  return Uri.file(directory.path).toString();
}

String _s(int count) => count == 1 ? '' : 's';

String _localSourceReadme() {
  return '''
# FlutterOH Source

Maintain SDK versions and package support metadata in this directory, then enable it locally with:

```sh
fluoh source enable <name> .
```

Sync released package repositories with:

```sh
fluoh source sync .
```

Root `fluoh.yaml` declares SDK versions and per-package routing.
`manifests/example/fluoh.yaml` contains a commented package Manifest template.
Copy or rename it for a package route, or let `fluoh source sync` create
released package metadata from Manifest repository URLs.
Edit Manifest files directly for advisory and maintenance notes.

A source repository can add scheduled validation or ingestion workflows on top of these files.
''';
}

String _localSourceMetadata() {
  return [
    'schema: 1',
    'kind: source',
    'name: local-flutteroh-source',
    'description: "Local FlutterOH source maintained by fluoh users."',
    '',
    '# Uncomment to document where this source is published.',
    '# repository:',
    '#   git:',
    '#     url: "https://github.com/FlutterOH/source.git"',
    '',
    '# Uncomment to publish FlutterOH SDK versions from this source.',
    '# sdk:',
    '#   git:',
    '#     url: "https://gitcode.com/CPF-Flutter/flutter_flutter.git"',
    '#   versions:',
    '#     - 3.35.8-ohos-0.0.3',
    '#     - 3.35.8-ohos-1.0.1',
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
    '#',
    '# repository:',
    '#   git:',
    '#     url: "https://github.com/FlutterOH/example.git"',
    '#',
    '# origin:',
    '#   kind: ported',
    '#',
    '# upstream:',
    '#   git:',
    '#     url: "https://github.com/example/upstream.git"',
    '#',
    '# package:',
    '#   name: example',
    '#   path: .',
    '#   # maintenance:',
    '#   #   frozen: true',
    '#   #   note: Upstream now includes native FlutterOH support.',
    '#   # advisory:',
    '#   #   message: Prefer upstream example for new projects.',
    '#   sdks:',
    '#     "3.35":',
    '#       releases:',
    '#         - version: "0.1.0"',
    '#           tag: example-1.0.0-ohos-3.35-0.1.0',
    '#           upstream:',
    '#             version: "1.0.0"',
    '#             ref: example-v1.0.0',
    '#             commit: "0123456789abcdef0123456789abcdef01234567"',
    '#           # status: experimental',
    '',
  ].join('\n');
}

List<SourceManifestRoute> _updatedManifestRoutes(
  List<SourceManifestRoute> routes, {
  required String manifestName,
}) {
  final updated = routes.any((route) => route.name == manifestName)
      ? routes
      : [...routes, SourceManifestRoute(name: manifestName)];
  return updated.toList(growable: false)
    ..sort((left, right) => left.name.compareTo(right.name));
}
