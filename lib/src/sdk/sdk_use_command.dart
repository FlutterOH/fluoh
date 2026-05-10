import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import '../cli/fluoh_command_runner.dart';
import '../cli/terminal_output.dart';
import '../config/fluoh_yaml_schema.dart';
import '../context/fluoh_environment.dart';
import 'sdk_manager.dart';
import 'sdk_project_environment.dart';

class SdkUseCommand extends Command<int> {
  SdkUseCommand({
    required this.environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser.addFlag(
      'pub-get',
      negatable: false,
      help: 'Run flutter pub get after switching the SDK.',
    );
  }

  final FluohEnvironment environment;
  final TerminalOutput _output;

  @override
  String get name => 'use';

  @override
  String get description => 'Use a Flutter OHOS SDK version or series here.';

  @override
  String get invocation => 'fluoh sdk use <version-or-series>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Expected an SDK version or version series.');
    }

    await _ensureFlutterProject();
    await _ensureProjectConfigIsNotPubManifest();
    final manager = SdkManager(environment);
    final release = await manager.resolveRelease(rest.single);
    _output.step(
      'Will modify ${_output.style.path(environment.workingDirectory.path)}/fluoh.yaml.',
    );
    final installed = await manager.sdkDirectory(release.tag).exists();
    final projectEnvironment = SdkProjectEnvironment(environment);
    await projectEnvironment.ensureIdeSdkLinkCanBeUpdated();
    final sdkDirectory = await _output.withProgress(
      installed
          ? 'Configuring Flutter OHOS SDK ${release.tag}.'
          : 'Installing Flutter OHOS SDK ${release.tag}; this may take a while.',
      () => projectEnvironment.configure(release),
    );
    _output.info(
      'Flutter OHOS SDK path: ${_output.style.path(sdkDirectory.path)}.',
    );
    final ideLink = await projectEnvironment.linkIdeSdk(sdkDirectory);
    _output.info('IDE Flutter SDK link: ${_output.style.path(ideLink.path)}.');
    _output.next(
      'Use this link as your IDE Flutter SDK path; reload the IDE if it keeps the old SDK.',
    );
    if (argResults!.flag('pub-get')) {
      await _runPubGet(sdkDirectory);
    }

    _output.success('Using Flutter OHOS SDK ${release.tag}.');
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

  Future<void> _ensureProjectConfigIsNotPubManifest() async {
    final fluohYaml = File('${environment.workingDirectory.path}/fluoh.yaml');
    if (!await fluohYaml.exists()) {
      return;
    }

    final yaml = loadYaml(await fluohYaml.readAsString());
    if (yaml is YamlMap) {
      ensureSupportedFluohYamlSchema(yaml);
    }
    if (yaml is YamlMap &&
        yaml['package'] is YamlMap &&
        yaml['upstream'] is YamlMap) {
      throw UsageException(
        'Current directory is a FlutterOH pub repository. '
            'Refusing to replace pub repository metadata in fluoh.yaml.',
        '',
      );
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
}
