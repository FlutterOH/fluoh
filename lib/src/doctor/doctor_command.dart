import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import '../cli/fluoh_command_runner.dart';
import '../config/fluoh_config.dart';
import '../context/fluoh_environment.dart';
import '../deps/deps_analyzer.dart';
import '../source/pub_source.dart';

class DoctorCommand extends Command<int> {
  DoctorCommand({required this.environment, required OutputWriter stdout})
    : _stdout = stdout;

  final FluohEnvironment environment;
  final OutputWriter _stdout;

  @override
  String get name => 'doctor';

  @override
  String get description => 'Diagnose FlutterOH project setup.';

  @override
  Future<int> run() async {
    final isFlutterProject = await _checkFlutterProject();
    await _checkSource();
    await _checkSdkFiles();
    await _checkOhosDirectory();
    if (isFlutterProject) {
      await _checkDependencies();
    }
    return 0;
  }

  Future<bool> _checkFlutterProject() async {
    final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
    if (!await pubspec.exists()) {
      _stdout('[WARN] Current directory is not a Flutter project.');
      return false;
    }

    try {
      final yaml = loadYaml(await pubspec.readAsString());
      final dependencies = yaml is YamlMap ? yaml['dependencies'] : null;
      final flutter = dependencies is YamlMap ? dependencies['flutter'] : null;
      if (flutter is YamlMap && flutter['sdk'] == 'flutter') {
        _stdout('[OK] Flutter project detected.');
        return true;
      }
    } on FormatException {
      // Report as a project warning below.
    }

    _stdout('[WARN] Current directory is not a Flutter project.');
    return false;
  }

  Future<void> _checkSource() async {
    final config = await FluohConfigStore(environment).load();
    if (config.sources.isEmpty) {
      _stdout('[WARN] No sources configured.');
      return;
    }

    final available = <String>[];
    final missing = <String>[];
    for (final entry in config.sources.entries) {
      final source = PubSource.directory(entry.value.directory);
      if (source.hasSdkIndex || source.hasPackageIndex) {
        available.add(entry.key);
      } else {
        missing.add(entry.key);
      }
    }

    if (available.isNotEmpty) {
      _stdout('[OK] Sources available: ${available.join(', ')}.');
    } else {
      _stdout('[WARN] No sources have been updated.');
    }
    if (missing.isNotEmpty) {
      _stdout('[WARN] Sources not updated: ${missing.join(', ')}.');
    }
  }

  Future<void> _checkSdkFiles() async {
    final fvmrc = File('${environment.workingDirectory.path}/.fvmrc');
    final fluohYaml = File('${environment.workingDirectory.path}/fluoh.yaml');
    final linkPath = '${environment.workingDirectory.path}/.fvm/flutter_sdk';
    String? fvmTag;
    try {
      fvmTag = await _readFvmTag(fvmrc);
    } on FormatException {
      _stdout('[WARN] .fvmrc is not valid JSON.');
    }
    final fluohTag = await _readProjectSdkTag(fluohYaml);

    if (fvmTag == null && fluohTag == null) {
      _stdout('[WARN] No FlutterOH SDK selected.');
      return;
    }
    final tag = fvmTag ?? fluohTag!;
    if (fvmTag != null && fluohTag != null && fvmTag != fluohTag) {
      _stdout('[WARN] .fvmrc and fluoh.yaml select different SDKs.');
    } else {
      _stdout('[OK] Project SDK: $tag.');
    }

    if (await _isManagedFlutterSdk(linkPath)) {
      _stdout('[OK] .fvm/flutter_sdk is managed by fluoh.');
    } else {
      _stdout('[WARN] .fvm/flutter_sdk is missing or not managed by fluoh.');
    }
  }

  Future<void> _checkOhosDirectory() async {
    final ohos = Directory('${environment.workingDirectory.path}/ohos');
    if (await ohos.exists()) {
      _stdout('[OK] ohos platform directory exists.');
    } else {
      _stdout('[WARN] Missing ohos platform directory.');
    }
  }

  Future<void> _checkDependencies() async {
    try {
      final report = await DepsAnalyzer(environment).analyze();
      final needingAttention = report.dependencies
          .where(
            (dependency) =>
                dependency.status == DependencyStatus.unknown ||
                dependency.status == DependencyStatus.blocked,
          )
          .map((dependency) => dependency.name)
          .toList(growable: false);
      if (needingAttention.isEmpty) {
        _stdout('[OK] Dependencies have no unknown or blocked packages.');
      } else {
        _stdout(
          '[WARN] Dependencies needing attention: ${needingAttention.join(', ')}.',
        );
      }
    } on UsageException catch (error) {
      _stdout('[WARN] Dependency check skipped: ${error.message}');
    } on FileSystemException catch (error) {
      _stdout('[WARN] Dependency check skipped: ${error.message}');
    } on FormatException catch (error) {
      _stdout('[WARN] Dependency check skipped: ${error.message}');
    }
  }

  Future<String?> _readFvmTag(File fvmrc) async {
    if (!await fvmrc.exists()) {
      return null;
    }
    final decoded = jsonDecode(await fvmrc.readAsString());
    if (decoded is Map<String, Object?>) {
      return decoded['flutter'] as String?;
    }
    return null;
  }

  Future<String?> _readProjectSdkTag(File fluohYaml) async {
    if (!await fluohYaml.exists()) {
      return null;
    }
    final yaml = loadYaml(await fluohYaml.readAsString());
    if (yaml is! YamlMap) {
      return null;
    }
    final sdk = yaml['sdk'];
    if (sdk is YamlMap) {
      return sdk['version'] as String?;
    }
    return null;
  }

  Future<bool> _isManagedFlutterSdk(String path) async {
    final link = Link(path);
    if (await link.exists()) {
      final target = await link.target();
      return target.startsWith(environment.sdksDirectory.path);
    }

    final marker = File('$path/FLUOH_SDK_PATH');
    if (await marker.exists()) {
      final target = (await marker.readAsString()).trim();
      return target.startsWith(environment.sdksDirectory.path);
    }
    return false;
  }
}
