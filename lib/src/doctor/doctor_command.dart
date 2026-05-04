import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import '../cli/fluoh_command_runner.dart';
import '../config/fluoh_config.dart';
import '../context/fluoh_environment.dart';
import '../deps/deps_analyzer.dart';
import '../cli/fluoh_installation.dart';
import '../source/source_index.dart';
import '../version.dart';

typedef DoctorVersionMetadataProvider =
    Future<DoctorVersionMetadata?> Function();
typedef DoctorScriptUriProvider = Uri Function();

class DoctorVersionMetadata {
  const DoctorVersionMetadata({
    required this.latestVersion,
    this.currentVersionPublished,
  });

  final String? latestVersion;
  final String? currentVersionPublished;
}

class DoctorCommand extends Command<int> {
  DoctorCommand({
    required this.environment,
    required OutputWriter stdout,
    DoctorVersionMetadataProvider? versionMetadataProvider,
    DoctorScriptUriProvider? scriptUriProvider,
    bool enableColor = false,
  }) : _stdout = stdout,
       _versionMetadataProvider =
           versionMetadataProvider ?? _fetchFluohVersionMetadata,
       _scriptUriProvider = scriptUriProvider ?? (() => Platform.script),
       _style = _DoctorStyle(enableColor: enableColor);

  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final DoctorVersionMetadataProvider _versionMetadataProvider;
  final DoctorScriptUriProvider _scriptUriProvider;
  final _DoctorStyle _style;

  @override
  String get name => 'doctor';

  @override
  String get description => 'Diagnose FlutterOH project setup.';

  @override
  Future<int> run() async {
    final checks = <_DoctorCheck>[];
    checks.add(await _checkToolVersion());
    checks.add(await _checkSource());
    final project = await _checkFlutterProject();
    checks.add(project.check);
    checks.addAll(await _checkSdkFiles());
    checks.add(await _checkOhosDirectory());
    if (project.isFlutterProject) {
      checks.add(await _checkDependencies());
    }

    _printChecks(checks);
    return 0;
  }

  Future<_DoctorCheck> _checkToolVersion() async {
    final installation = resolveFluohInstallation(_scriptUriProvider());
    final details = [_installationDescription(installation)];
    DoctorVersionMetadata? versionMetadata;
    try {
      versionMetadata = await _versionMetadataProvider();
    } on Exception catch (error) {
      details.add(
        'Could not check the latest version from pub.dev: ${error.toString()}',
      );
      return _DoctorCheck.warning('fluoh ($packageVersion)', details);
    }

    if (versionMetadata?.currentVersionPublished case final published?) {
      details.add('Current version published: $published.');
    }
    final latestVersion = versionMetadata?.latestVersion;
    if (latestVersion == null || latestVersion.isEmpty) {
      details.add('Could not check the latest version from pub.dev.');
      return _DoctorCheck.warning('fluoh ($packageVersion)', details);
    }

    if (_compareVersions(latestVersion, packageVersion) > 0) {
      details.add('Latest version: $latestVersion.');
      if (installation.method == FluohInstallMethod.localSourceCheckout) {
        details.add(
          'Upgrade available, but local source checkouts cannot be upgraded '
          'automatically.',
        );
      } else {
        details.add('Upgrade available: $latestVersion. Run `fluoh upgrade`.');
      }
      return _DoctorCheck.warning('fluoh ($packageVersion)', details);
    }

    details.add('Latest version: $latestVersion.');
    details.add('Up to date.');
    return _DoctorCheck.ok('fluoh ($packageVersion)', details);
  }

  Future<_FlutterProjectCheck> _checkFlutterProject() async {
    final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
    if (!await pubspec.exists()) {
      return _FlutterProjectCheck(
        _DoctorCheck.warning('Flutter project', [
          'Current directory is not a Flutter project.',
        ]),
        isFlutterProject: false,
      );
    }

    try {
      final yaml = loadYaml(await pubspec.readAsString());
      final dependencies = yaml is YamlMap ? yaml['dependencies'] : null;
      final flutter = dependencies is YamlMap ? dependencies['flutter'] : null;
      if (flutter is YamlMap && flutter['sdk'] == 'flutter') {
        return _FlutterProjectCheck(
          _DoctorCheck.ok('Flutter project', ['Detected Flutter project.']),
          isFlutterProject: true,
        );
      }
    } on FormatException {
      // Report as a project warning below.
    }

    return _FlutterProjectCheck(
      _DoctorCheck.warning('Flutter project', [
        'Current directory is not a Flutter project.',
      ]),
      isFlutterProject: false,
    );
  }

  Future<_DoctorCheck> _checkSource() async {
    final config = await FluohConfigStore(environment).load();
    if (config.sources.isEmpty) {
      return _DoctorCheck.warning('Sources', ['No sources configured.']);
    }

    final available = <String>[];
    final missing = <String>[];
    for (final entry in config.sources.entries) {
      final source = SourceIndex.directory(entry.value.directory);
      if (source.hasSdkIndex || source.hasPackageIndex) {
        available.add(entry.key);
      } else {
        missing.add(entry.key);
      }
    }

    final details = <String>[];
    if (available.isNotEmpty) {
      details.add('Available: ${available.join(', ')}.');
    } else {
      details.add('No sources have been updated.');
    }
    if (missing.isNotEmpty) {
      details.add('Not updated: ${missing.join(', ')}.');
    }

    return missing.isEmpty && available.isNotEmpty
        ? _DoctorCheck.ok('Sources', details)
        : _DoctorCheck.warning('Sources', details);
  }

  Future<List<_DoctorCheck>> _checkSdkFiles() async {
    final fvmrc = File('${environment.workingDirectory.path}/.fvmrc');
    final fluohYaml = File('${environment.workingDirectory.path}/fluoh.yaml');
    final linkPath = '${environment.workingDirectory.path}/.fvm/flutter_sdk';
    final sdkDetails = <String>[];
    var sdkHealthy = true;
    String? fvmTag;
    try {
      fvmTag = await _readFvmTag(fvmrc);
    } on FormatException {
      sdkDetails.add('.fvmrc is not valid JSON.');
      sdkHealthy = false;
    }
    final fluohTag = await _readProjectSdkTag(fluohYaml);

    if (fvmTag == null && fluohTag == null) {
      sdkDetails.add('No FlutterOH SDK selected.');
      sdkHealthy = false;
    } else if (fvmTag != null && fluohTag != null && fvmTag != fluohTag) {
      sdkDetails.add('.fvmrc and fluoh.yaml select different SDKs.');
      sdkDetails.add('.fvmrc: $fvmTag.');
      sdkDetails.add('fluoh.yaml: $fluohTag.');
      sdkHealthy = false;
    } else {
      final tag = fvmTag ?? fluohTag!;
      sdkDetails.add('$tag.');
    }

    final checks = <_DoctorCheck>[
      sdkHealthy
          ? _DoctorCheck.ok('Project SDK', sdkDetails)
          : _DoctorCheck.warning('Project SDK', sdkDetails),
    ];

    if (await _isManagedFlutterSdk(linkPath)) {
      checks.add(
        _DoctorCheck.ok('FVM', ['.fvm/flutter_sdk is managed by fluoh.']),
      );
    } else {
      checks.add(
        _DoctorCheck.warning('FVM', [
          '.fvm/flutter_sdk is missing or not managed by fluoh.',
        ]),
      );
    }
    return checks;
  }

  Future<_DoctorCheck> _checkOhosDirectory() async {
    final ohos = Directory('${environment.workingDirectory.path}/ohos');
    if (await ohos.exists()) {
      return _DoctorCheck.ok('OpenHarmony platform', [
        'ohos platform directory exists.',
      ]);
    }
    return _DoctorCheck.warning('OpenHarmony platform', [
      'Missing ohos platform directory.',
    ]);
  }

  Future<_DoctorCheck> _checkDependencies() async {
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
        return _DoctorCheck.ok('Dependencies', [
          'No unknown or blocked packages.',
        ]);
      }

      return _DoctorCheck.warning('Dependencies', [
        'Dependencies needing attention: ${needingAttention.join(', ')}.',
      ]);
    } on UsageException catch (error) {
      return _DoctorCheck.warning('Dependencies', [
        'Dependency check skipped: ${error.message}',
      ]);
    } on FileSystemException catch (error) {
      return _DoctorCheck.warning('Dependencies', [
        'Dependency check skipped: ${error.message}',
      ]);
    } on FormatException catch (error) {
      return _DoctorCheck.warning('Dependencies', [
        'Dependency check skipped: ${error.message}',
      ]);
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

  void _printChecks(List<_DoctorCheck> checks) {
    _stdout('Doctor summary:');
    for (final check in checks) {
      final marker = check.status == _DoctorCheckStatus.ok ? '✓' : '!';
      _stdout(_style.header(check.status, '[$marker] ${check.title}'));
      for (final detail in check.details) {
        _stdout('    • $detail');
      }
    }

    final issueCount = checks
        .where((check) => check.status == _DoctorCheckStatus.warning)
        .length;
    if (issueCount == 0) {
      _stdout('Doctor found no issues.');
    } else if (issueCount == 1) {
      _stdout('Doctor found issues in 1 category.');
    } else {
      _stdout('Doctor found issues in $issueCount categories.');
    }
  }
}

String _installationDescription(FluohInstallation installation) {
  switch (installation.method) {
    case FluohInstallMethod.dartPubGlobal:
      return 'Installed with dart pub global activate.';
    case FluohInstallMethod.homebrew:
      return 'Installed with Homebrew.';
    case FluohInstallMethod.localSourceCheckout:
      return 'Running from a local source checkout.';
  }
}

class _DoctorStyle {
  const _DoctorStyle({required this.enableColor});

  final bool enableColor;

  String header(_DoctorCheckStatus status, String text) {
    if (!enableColor) {
      return text;
    }

    final color = switch (status) {
      _DoctorCheckStatus.ok => '\u001b[32m',
      _DoctorCheckStatus.warning => '\u001b[33m',
    };
    return '$color$text\u001b[0m';
  }
}

class _FlutterProjectCheck {
  const _FlutterProjectCheck(this.check, {required this.isFlutterProject});

  final _DoctorCheck check;
  final bool isFlutterProject;
}

class _DoctorCheck {
  const _DoctorCheck._(this.status, this.title, this.details);

  factory _DoctorCheck.ok(String title, List<String> details) {
    return _DoctorCheck._(_DoctorCheckStatus.ok, title, details);
  }

  factory _DoctorCheck.warning(String title, List<String> details) {
    return _DoctorCheck._(_DoctorCheckStatus.warning, title, details);
  }

  final _DoctorCheckStatus status;
  final String title;
  final List<String> details;
}

enum _DoctorCheckStatus { ok, warning }

Future<DoctorVersionMetadata?> _fetchFluohVersionMetadata() async {
  final client = HttpClient();
  try {
    final uri = Uri.https('pub.dev', '/api/packages/fluoh');
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 2));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 2));
    if (response.statusCode != HttpStatus.ok) {
      return null;
    }

    final body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 2));
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    return parseFluohVersionMetadata(decoded);
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

DoctorVersionMetadata? parseFluohVersionMetadata(
  Map<String, Object?> packageMetadata,
) {
  final latest = packageMetadata['latest'];
  if (latest is! Map<String, Object?>) {
    return null;
  }
  final version = latest['version'];
  return DoctorVersionMetadata(
    latestVersion: version is String ? version : null,
    currentVersionPublished: _currentVersionPublished(packageMetadata),
  );
}

String? _currentVersionPublished(Map<String, Object?> packageMetadata) {
  final versions = packageMetadata['versions'];
  if (versions is! List<Object?>) {
    return null;
  }

  for (final version in versions) {
    if (version is! Map<String, Object?>) {
      continue;
    }
    if (version['version'] != packageVersion) {
      continue;
    }
    final published = version['published'];
    if (published is! String) {
      return null;
    }
    final timestamp = DateTime.tryParse(published);
    return timestamp == null ? null : _formatDate(timestamp.toUtc());
  }
  return null;
}

String _formatDate(DateTime date) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
}

int _compareVersions(String left, String right) {
  final leftParts = _versionParts(left);
  final rightParts = _versionParts(right);
  final length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var i = 0; i < length; i += 1) {
    final leftPart = i < leftParts.length ? leftParts[i] : 0;
    final rightPart = i < rightParts.length ? rightParts[i] : 0;
    final compared = leftPart.compareTo(rightPart);
    if (compared != 0) {
      return compared;
    }
  }
  return 0;
}

List<int> _versionParts(String version) {
  return version
      .split(RegExp(r'[-+]'))
      .first
      .split('.')
      .map(int.tryParse)
      .whereType<int>()
      .toList(growable: false);
}
