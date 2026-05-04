import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

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
    await manager.markCurrent(release);
    await writeFiles(release, sdkDirectory, writeFluohConfig: writeFluohConfig);
    return sdkDirectory;
  }

  Future<void> writeFiles(
    SdkRelease release,
    Directory sdkDirectory, {
    bool writeFluohConfig = true,
  }) async {
    await File('${environment.workingDirectory.path}/.fvmrc').writeAsString(
      const JsonEncoder.withIndent('  ').convert({'flutter': release.tag}),
    );

    final fvmDirectory = Directory('${environment.workingDirectory.path}/.fvm');
    await fvmDirectory.create(recursive: true);

    final linkPath = '${fvmDirectory.path}/flutter_sdk';
    await _deleteExistingLinkOrDirectory(linkPath);
    try {
      await Link(linkPath).create(sdkDirectory.path);
    } on FileSystemException {
      final fallback = Directory(linkPath);
      await fallback.create(recursive: true);
      await File(
        '${fallback.path}/FLUOH_SDK_PATH',
      ).writeAsString(sdkDirectory.path);
    }

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

  Future<void> _deleteExistingLinkOrDirectory(String path) async {
    final link = Link(path);
    if (await link.exists()) {
      await link.delete();
      return;
    }

    final directory = Directory(path);
    if (await directory.exists()) {
      final marker = File('${directory.path}/FLUOH_SDK_PATH');
      if (!await marker.exists()) {
        throw UsageException(
          'Refusing to replace existing .fvm/flutter_sdk directory because '
              'it was not created by fluoh.',
          '',
        );
      }
      await directory.delete(recursive: true);
      return;
    }

    final file = File(path);
    if (await file.exists()) {
      throw UsageException(
        'Refusing to replace existing .fvm/flutter_sdk file because it was '
            'not created by fluoh.',
        '',
      );
    }
  }
}
