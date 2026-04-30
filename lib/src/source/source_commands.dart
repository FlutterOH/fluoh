import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/fluoh_command_runner.dart';
import '../config/fluoh_config.dart';
import '../context/fluoh_environment.dart';
import 'pub_source.dart';

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
    final updated = isLocalPath
        ? config.addSource(name, urlOrPath, priority: priority)
        : config.addGitSource(
            name,
            urlOrPath,
            '${environment.homeDirectory.path}/sources/$name',
            priority: priority,
          );
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
        await _syncGitSource(sourceConfig);
      }
      await _validateSource(entry.key, sourceConfig);
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

Future<void> _validateSource(String name, SourceConfig sourceConfig) async {
  final source = PubSource.directory(sourceConfig.directory);
  final validators =
      <({String label, bool present, Future<void> Function() validate})>[
        (
          label: 'sdk/index.yaml',
          present: source.hasSdkIndex,
          validate: () async => source.loadSdkIndex(),
        ),
        (
          label: 'packages/registry.yaml',
          present: source.hasPackageIndex,
          validate: () async {
            await source.loadPackageIndex();
            await source.loadCompatibilityMatrix();
          },
        ),
      ];
  final present = validators
      .where((entry) => entry.present)
      .toList(growable: false);
  if (present.isEmpty) {
    throw UsageException(
      'Source $name does not contain sdk/index.yaml or '
          'packages/registry.yaml.',
      '',
    );
  }

  try {
    for (final entry in present) {
      await entry.validate();
    }
  } on FormatException catch (error) {
    throw UsageException('Source $name is not valid: ${error.message}', '');
  } on FileSystemException catch (error) {
    throw UsageException(
      'Source $name could not be read: ${_fileSystemMessage(error)}',
      '',
    );
  }
}

String _fileSystemMessage(FileSystemException error) {
  final path = error.path;
  if (path == null || path.isEmpty) {
    return error.message;
  }
  return '${error.message}: $path';
}

Future<void> _syncGitSource(SourceConfig source) async {
  final directory = source.directory;
  final gitDirectory = Directory('${directory.path}/.git');
  if (await gitDirectory.exists()) {
    await _git(['pull', '--ff-only', '--quiet'], workingDirectory: directory);
    return;
  }

  if (await directory.exists()) {
    final entries = await directory.list().take(1).toList();
    if (entries.isNotEmpty) {
      throw UsageException(
        'Source cache exists and is not a Git repository: ${directory.path}',
        '',
      );
    }
  }

  await directory.parent.create(recursive: true);
  await _git(['clone', '--quiet', source.url!, directory.path]);
}

Future<void> _git(List<String> arguments, {Directory? workingDirectory}) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: workingDirectory?.path,
  );
  if (result.exitCode != 0) {
    throw UsageException(
      'git ${arguments.join(' ')} failed:\n${result.stderr}',
      '',
    );
  }
}

bool _looksLikeGitSource(String value) {
  return value.startsWith('file:') ||
      value.contains('://') ||
      value.endsWith('.git');
}
