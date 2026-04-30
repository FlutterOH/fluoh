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
    addSubcommand(SourceUseCommand(environment: environment, stdout: stdout));
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
      final marker = entry.key == config.activeSource ? '*' : ' ';
      stdout('$marker ${entry.key} ${entry.value.displayValue}');
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

class SourceUseCommand extends Command<int> {
  SourceUseCommand({required this.environment, required this.stdout});

  final FluohEnvironment environment;
  final OutputWriter stdout;

  @override
  String get name => 'use';

  @override
  String get description => 'Select the active data source.';

  @override
  String get invocation => 'fluoh source use <name>';

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
      await store.save(config.useSource(name));
    } on ArgumentError catch (error) {
      usageException(error.message);
    }
    stdout('Using source $name.');
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
  String get description => 'Validate and refresh the active data source.';

  @override
  Future<int> run() async {
    final config = await FluohConfigStore(environment).load();
    final active = config.activeSource;
    final sourceConfig = _activeSourceConfig(config);
    if (sourceConfig.url != null) {
      await _syncGitSource(sourceConfig);
    }
    final source = PubSource.directory(sourceConfig.directory);

    await source.loadSdkIndex();
    await source.loadPackageIndex();
    await source.loadCompatibilityMatrix();

    stdout('Updated source $active.');
    return 0;
  }
}

SourceConfig _activeSourceConfig(FluohConfig config) {
  try {
    return config.activeSourceConfig();
  } on StateError catch (error) {
    throw UsageException(error.message, '');
  }
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
