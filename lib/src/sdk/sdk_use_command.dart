import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import '../cli/argument_validation.dart';
import '../cli/fluoh_command_runner.dart';
import '../cli/terminal_output.dart';
import '../config/fluoh_yaml_schema.dart';
import '../context/fluoh_environment.dart';
import 'flutter_runner.dart';
import 'sdk_manager.dart';
import 'sdk_project_environment.dart';

/// Selects a FlutterOH SDK for the current project.
class SdkUseCommand extends FluohCommand<int> {
  /// Creates the SDK use command.
  SdkUseCommand({
    required this.environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser.addFlag(
      'pub-get',
      negatable: false,
      help:
          'Run flutter pub get after switching the SDK '
          'and any OHOS initialization.',
    );
    argParser.addFlag(
      'no-init-ohos',
      negatable: false,
      help: 'Skip creating the OHOS platform directory when it is missing.',
    );
  }

  /// Runtime environment for the target project.
  final FluohEnvironment environment;
  final TerminalOutput _output;

  @override
  String get name => 'use';

  @override
  String get description =>
      'Select a Flutter OHOS SDK version or series for this project.';

  @override
  String get invocation => 'fluoh sdk use <version-or-series>';

  @override
  Future<int> run() async {
    final rest = expectArgumentCount(
      argResults!,
      1,
      'Expected an SDK version or version series.',
      usageException,
    );

    await _ensureFlutterProject();
    await _ensureProjectConfigIsNotPackageManifest();
    final manager = SdkManager(environment);
    final release = await manager.resolveRelease(rest.single);
    _output.step(
      'Will modify ${_output.style.path(environment.workingDirectory.path)}/fluoh.yaml',
    );
    final installed = await manager.sdkDirectory(release.tag).exists();
    final projectEnvironment = SdkProjectEnvironment(environment);
    await projectEnvironment.ensureIdeSdkLinkCanBeUpdated();
    final sdkDirectory = await _output.withProgress(
      installed
          ? 'Configuring Flutter OHOS SDK ${release.tag}'
          : 'Installing Flutter OHOS SDK ${release.tag}; this may take a while.',
      () => projectEnvironment.configure(release),
    );
    _output.info(
      'Flutter OHOS SDK path: ${_output.style.path(sdkDirectory.path)}',
    );
    final ideLink = await projectEnvironment.linkIdeSdk(sdkDirectory);
    _output.info('IDE Flutter SDK link: ${_output.style.path(ideLink.path)}');
    _output.next(
      'Use this link as your IDE Flutter SDK path; reload the IDE if it keeps the old SDK.',
    );
    if (!argResults!.flag('no-init-ohos')) {
      try {
        await _initOhosPlatform(sdkDirectory);
      } on UsageException {
        _output.warning(
          'SDK was configured but OHOS platform initialization failed. '
          'Fix the issue above and re-run '
          '${_output.style.code('fluoh sdk use ${release.tag} --no-init-ohos')}, '
          'or create the ohos directory manually.',
        );
        rethrow;
      }
    }
    if (argResults!.flag('pub-get')) {
      try {
        await _runPubGet(sdkDirectory);
      } on UsageException {
        _output.warning(
          'SDK was configured successfully. '
          'Fix the pub get issue above and re-run '
          '${_output.style.code('fluoh deps get')}.',
        );
        rethrow;
      }
    }

    _output.success('Using Flutter OHOS SDK ${release.tag}');
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

  Future<void> _ensureProjectConfigIsNotPackageManifest() async {
    final fluohYaml = File('${environment.workingDirectory.path}/fluoh.yaml');
    if (!await fluohYaml.exists()) {
      return;
    }

    final yaml = loadYaml(await fluohYaml.readAsString());
    if (yaml is YamlMap) {
      ensureSupportedFluohYamlSchema(yaml);
    }
    if (yaml is YamlMap &&
        (yaml['package'] is YamlMap || yaml['packages'] is YamlMap) &&
        yaml['upstream'] is YamlMap) {
      throw UsageException(
        'Current directory is a FlutterOH package repository. '
            'Refusing to replace package repository metadata in fluoh.yaml.',
        '',
      );
    }
  }

  Future<void> _runPubGet(Directory sdkDirectory) async {
    final result = await _runSdkFlutter(sdkDirectory, const ['pub', 'get']);
    if (result.exitCode != 0) {
      throw UsageException('flutter pub get failed:\n${result.stderr}', '');
    }
  }

  Future<void> _initOhosPlatform(Directory sdkDirectory) async {
    final ohos = Directory('${environment.workingDirectory.path}/ohos');
    if (await ohos.exists()) {
      _output.skipped('OHOS platform directory already exists');
      return;
    }

    final result = await _runSdkFlutter(sdkDirectory, const [
      'create',
      '--no-pub',
      '--platforms=ohos',
      '.',
    ]);
    if (result.exitCode != 0) {
      throw UsageException(
        'flutter create --platforms=ohos failed:\n${result.stderr}',
        '',
      );
    }
    if (!await ohos.exists()) {
      throw UsageException(
        'flutter create --platforms=ohos did not create an ohos directory.',
        '',
      );
    }
    _output.success('Initialized OHOS platform directory');
  }

  Future<ProcessResult> _runSdkFlutter(
    Directory sdkDirectory,
    List<String> arguments,
  ) async {
    final flutter = File('${sdkDirectory.path}/bin/flutter');
    if (!await flutter.exists()) {
      throw UsageException(
        'Selected SDK does not contain bin/flutter: ${sdkDirectory.path}',
        '',
      );
    }
    return Process.run(
      flutter.path,
      arguments,
      workingDirectory: environment.workingDirectory.path,
      environment: selectedToolProcessEnvironment(
        environment: environment,
        tool: flutter,
      ),
    );
  }
}
