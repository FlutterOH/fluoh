import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import '../cli/fluoh_command_runner.dart';
import '../config/fluoh_config.dart';
import '../context/fluoh_environment.dart';
import 'sdk_manager.dart';
import 'sdk_release.dart';

class SdkUseCommand extends Command<int> {
  SdkUseCommand({required this.environment, required OutputWriter stdout})
    : _stdout = stdout {
    argParser.addFlag(
      'pub-get',
      negatable: false,
      help: 'Run flutter pub get after switching the SDK.',
    );
  }

  final FluohEnvironment environment;
  final OutputWriter _stdout;

  @override
  String get name => 'use';

  @override
  String get description => 'Use a Flutter OHOS SDK version here.';

  @override
  String get invocation => 'fluoh sdk use <version>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Expected an SDK version.');
    }

    await _ensureFlutterProject();
    final manager = SdkManager(environment);
    final release = await manager.resolveRelease(rest.single);
    final sdkDirectory = await manager.install(release);
    await manager.markCurrent(release);
    _stdout('Will modify ${environment.workingDirectory.path}/.fvmrc.');
    _stdout(
      'Will modify ${environment.workingDirectory.path}/.fvm/flutter_sdk.',
    );
    _stdout('Will modify ${environment.workingDirectory.path}/fluoh.yaml.');
    await _writeProjectFiles(release, sdkDirectory);
    if (argResults!.flag('pub-get')) {
      await _runPubGet(sdkDirectory);
    }

    _stdout('Using Flutter OHOS SDK ${release.tag}.');
    return 0;
  }

  Future<void> _ensureFlutterProject() async {
    final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
    if (!await pubspec.exists()) {
      throw UsageException('Current directory is not a Flutter project.', '');
    }

    final yaml = loadYaml(await pubspec.readAsString());
    if (yaml is! YamlMap) {
      throw UsageException('pubspec.yaml must contain a YAML map.', '');
    }
    final dependencies = yaml['dependencies'];
    final flutter = dependencies is YamlMap ? dependencies['flutter'] : null;
    if (flutter is! YamlMap || flutter['sdk'] != 'flutter') {
      throw UsageException('Current directory is not a Flutter project.', '');
    }
  }

  Future<void> _runPubGet(Directory sdkDirectory) async {
    final sdkFlutter = File('${sdkDirectory.path}/bin/flutter');
    final executable = await sdkFlutter.exists() ? sdkFlutter.path : 'flutter';
    final result = await Process.run(executable, [
      'pub',
      'get',
    ], workingDirectory: environment.workingDirectory.path);
    if (result.exitCode != 0) {
      throw UsageException('flutter pub get failed:\n${result.stderr}', '');
    }
  }

  Future<void> _writeProjectFiles(
    SdkRelease release,
    Directory sdkDirectory,
  ) async {
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
