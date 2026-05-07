import 'dart:io';

import '../config/fluoh_config.dart';
import '../context/fluoh_environment.dart';
import 'sdk_manager.dart';
import 'sdk_release.dart';

class SdkProjectEnvironment {
  const SdkProjectEnvironment(this.environment);

  final FluohEnvironment environment;

  Future<Directory> configure(
    SdkRelease release, {
    bool writeFluohConfig = true,
  }) async {
    final manager = SdkManager(environment);
    final sdkDirectory = await manager.install(release);
    await writeFiles(release, writeFluohConfig: writeFluohConfig);
    return sdkDirectory;
  }

  Future<void> writeFiles(
    SdkRelease release, {
    bool writeFluohConfig = true,
  }) async {
    if (writeFluohConfig) {
      await _writeProjectFluohConfig(release);
    }
  }

  Future<void> _writeProjectFluohConfig(SdkRelease release) async {
    final config = await FluohConfigStore(environment).load();
    await File('${environment.workingDirectory.path}/fluoh.yaml').writeAsString(
      [
        'schema: 1',
        'sdk:',
        '  version: ${release.tag}',
        'sources:',
        for (final name in config.sources.keys) '  - $name',
        'dependencyPolicy:',
        '  replacementMode: overrides',
        '',
      ].join('\n'),
    );
  }
}
