import 'package:args/command_runner.dart';

import '../cli/fluoh_command_runner.dart';
import '../context/fluoh_environment.dart';
import 'sdk_manager.dart';

class SdkCommand extends Command<int> {
  SdkCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
  }) {
    final manager = SdkManager(environment);
    addSubcommand(SdkListCommand(manager: manager, stdout: stdout));
    addSubcommand(SdkInstallCommand(manager: manager, stdout: stdout));
    addSubcommand(SdkCurrentCommand(manager: manager, stdout: stdout));
    addSubcommand(SdkRemoveCommand(manager: manager, stdout: stdout));
  }

  @override
  String get name => 'sdk';

  @override
  String get description => 'Manage cached Flutter OHOS SDKs.';
}

class SdkListCommand extends Command<int> {
  SdkListCommand({required this.manager, required this.stdout});

  final SdkManager manager;
  final OutputWriter stdout;

  @override
  String get name => 'list';

  @override
  String get description => 'List SDK releases from the active source.';

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
  String get invocation => 'fluoh sdk install <version>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Expected an SDK version.');
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
  String get description => 'Print the current SDK tag.';

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
  String get invocation => 'fluoh sdk remove <version>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Expected an SDK version.');
    }

    final release = await manager.resolveRelease(rest.single);
    await manager.remove(release.tag);
    stdout('Removed SDK ${release.tag}.');
    return 0;
  }
}
