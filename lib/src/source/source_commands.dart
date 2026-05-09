import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/command_usage.dart';
import '../cli/fluoh_command_runner.dart';
import '../cli/terminal_output.dart';
import '../config/fluoh_config.dart';
import '../context/fluoh_environment.dart';
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
  String get description => 'Manage FlutterOH/pub data sources.';

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
  CommandUsageSection('', ['list', 'init', 'add', 'remove', 'update']),
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
  SourceInitCommand({required this.stdout, TerminalOutput? output})
    : _output = output ?? TerminalOutput(stdout: stdout);

  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'init';

  @override
  String get description => 'Create a local source template.';

  @override
  String get invocation => 'fluoh source init <path>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Expected a local source path.');
    }

    final source = Directory(rest.single);
    final metadata = File('${source.path}/fluoh.yaml');
    final repositories = File('${source.path}/packages/repositories.yaml');
    final manifests = Directory('${source.path}/packages/manifests');
    final readme = File('${source.path}/README.md');
    final existed = await repositories.exists();

    await manifests.create(recursive: true);
    if (!await metadata.exists()) {
      await source.create(recursive: true);
      await metadata.writeAsString(_localSourceMetadata(source));
    }
    if (!existed) {
      await repositories.parent.create(recursive: true);
      await repositories.writeAsString('''
schema: 1
repositories: []
''');
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
      'Edit packages/repositories.yaml and packages/manifests/*.yaml.',
    );
    _output.next(
      'Add it with: fluoh source add <name> ${_output.style.path(source.path)}',
    );
    return 0;
  }
}

class SourceAddCommand extends Command<int> {
  SourceAddCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser.addOption(
      'priority',
      help: 'Source priority. Higher values win when indexes overlap.',
      defaultsTo: '100',
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
    final rest = argResults!.rest;
    if (rest.length != 2) {
      usageException('Expected a source name and URL or path.');
    }

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
    final isLocalPath = await Directory(urlOrPath).exists();
    if (!isLocalPath && !_looksLikeGitSource(urlOrPath)) {
      usageException('Source path does not exist: $urlOrPath');
    }

    final store = FluohConfigStore(environment);
    final config = await store.load();
    final cachePath = '${environment.homeDirectory.path}/sources/$name';
    final updated = isLocalPath
        ? config.addSource(name, cachePath, priority: priority)
        : config.addGitSource(name, urlOrPath, cachePath, priority: priority);
    if (isLocalPath) {
      await syncLocalSource(name, Directory(urlOrPath), Directory(cachePath));
    }
    await store.save(updated);
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
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Expected a source name.');
    }

    final name = rest.single;
    _ensureValidSourceName(name);
    final store = FluohConfigStore(environment);
    final config = await store.load();
    try {
      await store.save(config.removeSource(name));
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
    final config = await FluohConfigStore(environment).load();
    final rest = argResults!.rest;
    if (rest.length > 1) {
      usageException('Expected zero or one source name.');
    }

    final sources = rest.isEmpty
        ? config.sources.entries.toList(growable: false)
        : [_sourceEntry(config, _validatedSourceName(rest.single))];
    if (sources.isEmpty) {
      usageException('No sources configured.');
    }

    for (final entry in sources) {
      final sourceConfig = entry.value;
      if (sourceConfig.url != null) {
        await syncGitSource(entry.key, sourceConfig, output: _output);
      }
      await validateSource(entry.key, sourceConfig);
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
      value.contains('://') ||
      value.endsWith('.git');
}

String _localSourceReadme() {
  return '''
# FlutterOH Local Source

Maintain package adapter metadata in this directory, then register it with:

```sh
fluoh source add <name> .
```

Add packages to `packages/repositories.yaml` and write matching package manifests in `packages/manifests/`.
This template is package-only; SDK releases continue to come from other configured sources.
''';
}

String _localSourceMetadata(Directory source) {
  return '''
schema: 1
name: Local FlutterOH source
description: Local package source maintained by fluoh users.
repositoryUrl: file:${source.path}
''';
}
