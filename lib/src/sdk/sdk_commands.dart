import 'package:args/command_runner.dart';

import '../cli/command_usage.dart';
import '../cli/fluoh_command_runner.dart';
import '../context/fluoh_environment.dart';
import 'sdk_manager.dart';
import 'sdk_use_command.dart';

class SdkCommand extends Command<int> {
  SdkCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
  }) : _stdout = stdout {
    final manager = SdkManager(environment);
    addSubcommand(SdkListCommand(manager: manager, stdout: stdout));
    addSubcommand(SdkInstallCommand(manager: manager, stdout: stdout));
    addSubcommand(SdkCurrentCommand(manager: manager, stdout: stdout));
    addSubcommand(SdkRemoveCommand(manager: manager, stdout: stdout));
    addSubcommand(SdkUseCommand(environment: environment, stdout: stdout));
  }

  final OutputWriter _stdout;

  @override
  String get name => 'sdk';

  @override
  String get description => 'Manage cached Flutter OHOS SDKs.';

  @override
  String get usage => '$description\n\n$_usageWithoutDescription';

  @override
  void printUsage() {
    _stdout(usage);
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
      ),
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }
}

const _sdkCommandSections = [
  CommandUsageSection('', ['list', 'install', 'current', 'remove', 'use']),
];

class SdkListCommand extends Command<int> {
  SdkListCommand({required this.manager, required this.stdout});

  final SdkManager manager;
  final OutputWriter stdout;

  @override
  String get name => 'list';

  @override
  String get description => 'List SDK releases from configured sources.';

  @override
  Future<int> run() async {
    for (final release in await manager.listReleases()) {
      final status = await manager.sdkDirectory(release.tag).exists()
          ? 'installed'
          : 'remote';
      stdout('${release.tag} ${release.channel} $status');
    }
    return 0;
  }
}

class SdkInstallCommand extends Command<int> {
  SdkInstallCommand({required this.manager, required this.stdout});

  final SdkManager manager;
  final OutputWriter stdout;

  @override
  String get name => 'install';

  @override
  String get description => 'Install an SDK release into the local cache.';

  @override
  String get invocation => 'fluoh sdk install <version-or-series>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Expected an SDK version or version series.');
    }

    final release = await manager.resolveRelease(rest.single);
    await manager.install(release);
    stdout('Installed SDK ${release.tag}.');
    return 0;
  }
}

class SdkCurrentCommand extends Command<int> {
  SdkCurrentCommand({required this.manager, required this.stdout});

  final SdkManager manager;
  final OutputWriter stdout;

  @override
  String get name => 'current';

  @override
  String get description => 'Print the current project SDK tag.';

  @override
  Future<int> run() async {
    final tag = await manager.currentSdkTag();
    if (tag == null || tag.isEmpty) {
      stdout('No SDK selected.');
      return 1;
    }

    stdout('Current SDK: $tag');
    return 0;
  }
}

class SdkRemoveCommand extends Command<int> {
  SdkRemoveCommand({required this.manager, required this.stdout});

  final SdkManager manager;
  final OutputWriter stdout;

  @override
  String get name => 'remove';

  @override
  String get description => 'Remove an SDK release from the local cache.';

  @override
  String get invocation => 'fluoh sdk remove <version-or-series>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Expected an SDK version or version series.');
    }

    final release = await manager.resolveRelease(rest.single);
    await manager.remove(release.tag);
    stdout('Removed SDK ${release.tag}.');
    return 0;
  }
}
