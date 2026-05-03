import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/fluoh_command_runner.dart';
import '../config/fluoh_config.dart';
import '../context/fluoh_environment.dart';
import 'source_sync.dart';

class SourceCommand extends Command<int> {
  SourceCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
  }) {
    addSubcommand(SourceListCommand(environment: environment, stdout: stdout));
    addSubcommand(SourceAddCommand(environment: environment, stdout: stdout));
    addSubcommand(
      SourceRemoveCommand(environment: environment, stdout: stdout),
    );
    addSubcommand(
      SourceUpdateCommand(environment: environment, stdout: stdout),
    );
  }

  @override
  String get name => 'source';

  @override
  String get description => 'Manage FlutterOH/pub data sources.';
}

class SourceListCommand extends Command<int> {
  SourceListCommand({required this.environment, required this.stdout});

  final FluohEnvironment environment;
  final OutputWriter stdout;

  @override
  String get name => 'list';

  @override
  String get description => 'List configured data sources.';

  @override
  Future<int> run() async {
    final config = await FluohConfigStore(environment).load();
    if (config.sources.isEmpty) {
      stdout('No sources configured.');
      return 0;
    }

    for (final entry in config.sources.entries) {
      stdout('${entry.key} ${entry.value.displayValue}');
    }
    return 0;
  }
}

class SourceAddCommand extends Command<int> {
  SourceAddCommand({required this.environment, required this.stdout}) {
    argParser.addOption(
      'priority',
      help: 'Source priority. Higher values win when indexes overlap.',
      defaultsTo: '100',
    );
  }

  final FluohEnvironment environment;
  final OutputWriter stdout;

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
    stdout('Added source $name: $urlOrPath');
    return 0;
  }
}

class SourceRemoveCommand extends Command<int> {
  SourceRemoveCommand({required this.environment, required this.stdout});

  final FluohEnvironment environment;
  final OutputWriter stdout;

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
    final store = FluohConfigStore(environment);
    final config = await store.load();
    try {
      await store.save(config.removeSource(name));
    } on ArgumentError catch (error) {
      usageException(error.message);
    }
    stdout('Removed source $name.');
    return 0;
  }
}

class SourceUpdateCommand extends Command<int> {
  SourceUpdateCommand({required this.environment, required this.stdout});

  final FluohEnvironment environment;
  final OutputWriter stdout;

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
        : [_sourceEntry(config, rest.single)];
    if (sources.isEmpty) {
      usageException('No sources configured.');
    }

    for (final entry in sources) {
      final sourceConfig = entry.value;
      if (sourceConfig.url != null) {
        await syncGitSource(entry.key, sourceConfig);
      }
      await validateSource(entry.key, sourceConfig);
      stdout('Updated source ${entry.key}.');
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

bool _looksLikeGitSource(String value) {
  return value.startsWith('file:') ||
      value.contains('://') ||
      value.endsWith('.git');
}
