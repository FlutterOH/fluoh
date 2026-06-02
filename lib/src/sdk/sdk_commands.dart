import 'package:args/command_runner.dart';

import '../cli/argument_validation.dart';
import '../cli/command_usage.dart';
import '../cli/fluoh_command_runner.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import 'sdk_manager.dart';
import 'sdk_use_command.dart';

/// Top-level `fluoh sdk` command group.
class SdkCommand extends FluohCommand<int> {
  /// Creates the SDK command group and its subcommands.
  SdkCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    final manager = SdkManager(environment);
    addSubcommand(
      SdkListCommand(manager: manager, stdout: stdout, output: _output),
    );
    addSubcommand(
      SdkInstallCommand(manager: manager, stdout: stdout, output: _output),
    );
    addSubcommand(
      SdkCurrentCommand(manager: manager, stdout: stdout, output: _output),
    );
    addSubcommand(
      SdkRemoveCommand(manager: manager, stdout: stdout, output: _output),
    );
    addSubcommand(
      SdkUseCommand(environment: environment, stdout: stdout, output: _output),
    );
  }

  final TerminalOutput _output;

  @override
  String get name => 'sdk';

  @override
  String get description => 'Manage cached Flutter OHOS SDKs.';

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
        sections: _sdkCommandSections,
        isSubcommand: true,
        lineLength: argParser.usageLineLength,
        style: _output.style,
      ),
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }
}

const _sdkCommandSections = [
  CommandUsageSection('', ['list', 'install', 'current', 'remove', 'use']),
];

/// Lists remote and installed SDK versions.
class SdkListCommand extends FluohCommand<int> {
  /// Creates the SDK list command.
  SdkListCommand({
    required this.manager,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout);

  /// SDK manager used to load Source and cache data.
  final SdkManager manager;

  /// Writer used for plain list output.
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'list';

  @override
  String get description => 'List SDK versions from configured sources.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final entries = await manager.listEntries();
    if (_output.style.capabilities.decorated) {
      _output.table(
        columns: const [
          TerminalTableColumn('#', style: TerminalTableCellStyle.muted),
          TerminalTableColumn('Version', style: TerminalTableCellStyle.value),
          TerminalTableColumn('Channel', style: TerminalTableCellStyle.muted),
          TerminalTableColumn('Status', style: TerminalTableCellStyle.status),
        ],
        rows: [
          for (var index = 0; index < entries.length; index += 1)
            [
              '${index + 1}',
              entries[index].tag,
              entries[index].channel,
              entries[index].installed ? 'installed' : 'remote',
            ],
        ],
      );
      return 0;
    }

    var index = 1;
    for (final sdk in entries) {
      final status = sdk.installed ? 'installed' : 'remote';
      stdout('[$index] ${sdk.tag} ${sdk.channel} $status');
      index += 1;
    }
    return 0;
  }
}

/// Installs an SDK into the local cache.
class SdkInstallCommand extends FluohCommand<int> {
  /// Creates the SDK install command.
  SdkInstallCommand({
    required this.manager,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout);

  /// SDK manager used for release resolution and install.
  final SdkManager manager;

  /// Writer kept for command construction consistency.
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'install';

  @override
  String get description => 'Install an SDK version into the local cache.';

  @override
  String get invocation => 'fluoh sdk install <version-or-series>';

  @override
  Future<int> run() async {
    final rest = expectArgumentCount(
      argResults!,
      1,
      'Expected an SDK version or version series.',
      usageException,
    );

    final release = await manager.resolveRelease(rest.single);
    await _output.withProgress(
      'Installing SDK ${release.tag}',
      () => manager.install(release),
    );
    _output.success('Installed SDK ${release.tag}');
    return 0;
  }
}

/// Prints the SDK selected for the current project.
class SdkCurrentCommand extends FluohCommand<int> {
  /// Creates the SDK current command.
  SdkCurrentCommand({
    required this.manager,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout);

  /// SDK manager used to read project SDK state.
  final SdkManager manager;

  /// Writer kept for command construction consistency.
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'current';

  @override
  String get description => 'Print the current project SDK version.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final version = await manager.currentSdkVersion();
    if (version == null || version.isEmpty) {
      _output.warning('No SDK selected');
      return 1;
    }

    _output.info('Current SDK: $version');
    return 0;
  }
}

/// Removes an SDK from the local cache.
class SdkRemoveCommand extends FluohCommand<int> {
  /// Creates the SDK remove command.
  SdkRemoveCommand({
    required this.manager,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout);

  /// SDK manager used to resolve and remove SDKs.
  final SdkManager manager;

  /// Writer kept for command construction consistency.
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'remove';

  @override
  String get description => 'Remove an SDK version from the local cache.';

  @override
  String get invocation => 'fluoh sdk remove <version-or-series>';

  @override
  Future<int> run() async {
    final rest = expectArgumentCount(
      argResults!,
      1,
      'Expected an SDK version or version series.',
      usageException,
    );

    final tag = await manager.remove(rest.single);
    _output.success('Removed SDK $tag');
    return 0;
  }
}
