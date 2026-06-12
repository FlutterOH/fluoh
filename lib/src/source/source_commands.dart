import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../cli/argument_validation.dart';
import '../cli/command_usage.dart';
import '../cli/fluoh_command_runner.dart';
import '../cli/machine_output.dart';
import '../cli/terminal_output.dart';
import '../config/fluoh_config.dart';
import '../context/fluoh_environment.dart';
import '../package/git/package_git.dart';
import '../schema/schema.dart';
import 'source_runtime.dart';
import 'source_check_command.dart';
import 'source_sync.dart';

part 'source_sync_command.dart';
part 'source_sync_command_support.dart';
part 'source_config_commands.dart';

/// Top-level `fluoh source` command group.
class SourceCommand extends FluohCommand<int> {
  /// Creates the Source command group and subcommands.
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
    addSubcommand(
      SourceInitCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      SourceSyncCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      SourceCheckCommand(
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
  String get description => 'Manage FlutterOH package metadata sources.';

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
  CommandUsageSection('Configured sources:', [
    'list',
    'add',
    'remove',
    'update',
  ]),
  CommandUsageSection('Source repositories:', ['init', 'sync', 'check']),
];

/// Lists configured Source entries.
class SourceListCommand extends FluohCommand<int> {
  /// Creates the Source list command.
  SourceListCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print configured sources as JSON.',
    );
  }

  /// Runtime environment containing persisted config paths.
  final FluohEnvironment environment;

  /// Writer used for plain output.
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
    final sources = config.sources.entries.toList(growable: false);
    if (argResults!.flag('json')) {
      writeMachineOutput(
        stdout,
        command: 'source list',
        ok: true,
        exitCode: 0,
        fields: {
          'count': sources.length,
          'sources': [
            for (final entry in sources)
              {
                'name': entry.key,
                'source': entry.value.displayValue,
                'path': entry.value.path,
                if (entry.value.url != null) 'url': entry.value.url,
                'priority': entry.value.priority,
              },
          ],
        },
      );
      return 0;
    }
    if (config.sources.isEmpty) {
      _output.warning('No sources configured');
      return 0;
    }

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

/// Creates a local Source repository template.
class SourceInitCommand extends FluohCommand<int> {
  /// Creates the Source init command.
  SourceInitCommand({
    required this.environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout);

  /// Runtime environment used to resolve template paths.
  final FluohEnvironment environment;
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
    final source = _resolveUserSourceDirectory(
      environment.workingDirectory,
      Directory(rest.single),
    );
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
      await metadata.writeAsString(_localSourceMetadata());
    }
    if (!await exampleManifest.exists()) {
      await exampleManifest.writeAsString(_localSourceManifestTemplate());
    }
    if (!await readme.exists()) {
      await readme.writeAsString(_localSourceReadme());
    }

    if (existed) {
      _output.skipped(
        'Local source template already exists at ${_output.style.path(source.path)}',
      );
    } else {
      _output.success(
        'Created local source template at ${_output.style.path(source.path)}',
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

/// Synchronizes package release metadata into a Source repository.
