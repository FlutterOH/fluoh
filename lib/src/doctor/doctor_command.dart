import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import '../cli/argument_validation.dart';
import '../cli/fluoh_command_runner.dart';
import '../cli/fluoh_installation.dart';
import '../config/fluoh_config.dart';
import '../context/fluoh_environment.dart';
import '../cli/terminal_output.dart';
import '../ohos/device_runner.dart';
import '../ohos/ohos_toolchain.dart';
import '../platform/platform_environment.dart';
import '../sdk/sdk_project_config.dart';
import '../source/source_sync.dart';
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

class DoctorCommand extends FluohCommand<int> {
  DoctorCommand({
    required this.environment,
    required OutputWriter stdout,
    DoctorVersionMetadataProvider? versionMetadataProvider,
    DoctorScriptUriProvider? scriptUriProvider,
    bool enableColor = false,
    TerminalOutput? output,
  }) : _output =
           output ??
           TerminalOutput(
             stdout: stdout,
             style: TerminalStyle(
               capabilities: TerminalCapabilities(
                 ansi: enableColor,
                 decorated: enableColor,
                 unicode: true,
               ),
             ),
           ),
       _versionMetadataProvider =
           versionMetadataProvider ?? _fetchFluohVersionMetadata,
       _scriptUriProvider = scriptUriProvider ?? (() => Platform.script),
       _style =
           output?.style ??
           TerminalStyle(
             capabilities: TerminalCapabilities(
               ansi: enableColor,
               decorated: enableColor,
               unicode: true,
             ),
           ) {
    argParser
      ..addFlag(
        'strict',
        negatable: false,
        help: 'Return a non-zero exit code when doctor finds warnings.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the doctor result as JSON.',
      )
      ..addOption(
        'platform',
        allowed: const ['all', 'ohos', 'android', 'ios'],
        help: 'Platform scope to check. OHOS is checked by default.',
        allowedHelp: const {
          'all': 'Check OHOS, Android, and iOS.',
          'ohos': 'Check OHOS project or local tooling.',
          'android': 'Check Android SDK, adb, emulator, avdmanager, and Java.',
          'ios': 'Check Xcode xcrun and simctl.',
        },
      );
  }

  final FluohEnvironment environment;
  final TerminalOutput _output;
  final DoctorVersionMetadataProvider _versionMetadataProvider;
  final DoctorScriptUriProvider _scriptUriProvider;
  final TerminalStyle _style;

  @override
  String get name => 'doctor';

  @override
  String get description => 'Diagnose fluoh environment and project setup.';

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
      'Usage: ${runner!.executableName} $name [env|project|all]',
      argParser.usage,
      '',
      _output.style.section('Doctor scopes:'),
      '  env       ${_DoctorScope.environment.description}',
      '  project   ${_DoctorScope.project.description}',
      '  all       ${_DoctorScope.all.description}',
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }

  @override
  Future<int> run() async {
    final scope = _scopeFromArguments(argResults!, usageException);
    return _runScoped(scope, argResults!, usageException);
  }

  Future<int> _runScoped(
    _DoctorScope scope,
    ArgResults results,
    UsageError usageException,
  ) async {
    final checks = <_DoctorCheck>[];
    final platforms = _platformsFromOption(results.option('platform'));
    if (scope.includesEnvironment) {
      checks.add(await _checkToolVersion());
      checks.add(await _checkSource());
      checks.addAll(await _checkPlatformToolchains(platforms));
    }
    if (scope.includesProject) {
      checks.add(await _checkFlutterProject());
      checks.add(await _checkSdkFiles());
      checks.addAll(await _checkProjectPlatforms(platforms));
    }

    final issueCount = _issueCount(checks);
    if (results.flag('json')) {
      _output.write(
        jsonEncode({
          'scope': scope.cliName,
          'platforms': platforms.map((platform) => platform.cliName).toList(),
          'ok': issueCount == 0,
          'issueCount': issueCount,
          'checks': checks.map((check) => check.toJson()).toList(),
        }),
      );
    } else {
      _printChecks(scope, checks);
    }
    return results.flag('strict') && issueCount > 0 ? 1 : 0;
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
      return _DoctorCheck.warning(
        _DoctorCheckGroup.environment,
        'fluoh ($packageVersion)',
        details,
      );
    }

    if (versionMetadata?.currentVersionPublished case final published?) {
      details.add('Current version published: $published.');
    }
    final latestVersion = versionMetadata?.latestVersion;
    if (latestVersion == null || latestVersion.isEmpty) {
      details.add('Could not check the latest version from pub.dev.');
      return _DoctorCheck.warning(
        _DoctorCheckGroup.environment,
        'fluoh ($packageVersion)',
        details,
      );
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
      return _DoctorCheck.warning(
        _DoctorCheckGroup.environment,
        'fluoh ($packageVersion)',
        details,
      );
    }

    details.add('Latest version: $latestVersion.');
    details.add('Up to date.');
    return _DoctorCheck.ok(
      _DoctorCheckGroup.environment,
      'fluoh ($packageVersion)',
      details,
    );
  }

  Future<_DoctorCheck> _checkFlutterProject() async {
    final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
    if (!await pubspec.exists()) {
      return _DoctorCheck.warning(
        _DoctorCheckGroup.project,
        'Flutter project',
        ['Current directory is not a Flutter project.'],
      );
    }

    try {
      final yaml = loadYaml(await pubspec.readAsString());
      final dependencies = yaml is YamlMap ? yaml['dependencies'] : null;
      final flutter = dependencies is YamlMap ? dependencies['flutter'] : null;
      if (flutter is YamlMap && flutter['sdk'] == 'flutter') {
        return _DoctorCheck.ok(_DoctorCheckGroup.project, 'Flutter project', [
          'Detected Flutter project.',
        ]);
      }
    } on FormatException {
      // Report as a project warning below.
    }

    return _DoctorCheck.warning(_DoctorCheckGroup.project, 'Flutter project', [
      'Current directory is not a Flutter project.',
    ]);
  }

  Future<_DoctorCheck> _checkSource() async {
    final config = await FluohConfigStore(environment).load();
    if (config.sources.isEmpty) {
      return _DoctorCheck.warning(_DoctorCheckGroup.environment, 'Sources', [
        'No sources configured.',
      ]);
    }

    final available = <String>[];
    final missing = <String>[];
    final invalid = <String>[];
    for (final entry in config.sources.entries) {
      final sourceDirectory = entry.value.directory;
      final sourceManifest = File('${sourceDirectory.path}/fluoh.yaml');
      if (!await sourceDirectory.exists() || !await sourceManifest.exists()) {
        missing.add(entry.key);
        continue;
      }

      try {
        await validateSource(entry.key, entry.value);
        available.add(entry.key);
      } on UsageException catch (error) {
        invalid.add('${entry.key} (${error.message})');
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
    if (invalid.isNotEmpty) {
      details.add('Invalid: ${invalid.join(', ')}.');
    }

    return missing.isEmpty && invalid.isEmpty && available.isNotEmpty
        ? _DoctorCheck.ok(_DoctorCheckGroup.environment, 'Sources', details)
        : _DoctorCheck.warning(
            _DoctorCheckGroup.environment,
            'Sources',
            details,
          );
  }

  Future<_DoctorCheck> _checkSdkFiles() async {
    final sdkDetails = <String>[];
    var sdkHealthy = true;
    var sdkReadable = true;
    String? sdkVersion;
    try {
      sdkVersion = await readProjectSdkVersion(environment.workingDirectory);
    } on UsageException catch (error) {
      sdkDetails.add(error.message);
      sdkHealthy = false;
      sdkReadable = false;
    } on FormatException {
      sdkDetails.add('fluoh.yaml is not valid YAML.');
      sdkHealthy = false;
      sdkReadable = false;
    }

    if (sdkReadable) {
      if (sdkVersion == null) {
        sdkDetails.add('No FlutterOH SDK selected.');
        sdkHealthy = false;
      } else {
        sdkDetails.add('$sdkVersion.');
      }
    }

    return sdkHealthy
        ? _DoctorCheck.ok(_DoctorCheckGroup.project, 'Project SDK', sdkDetails)
        : _DoctorCheck.warning(
            _DoctorCheckGroup.project,
            'Project SDK',
            sdkDetails,
          );
  }

  Future<List<_DoctorCheck>> _checkProjectPlatforms(
    List<FluohPlatform> platforms,
  ) async {
    return [
      for (final platform in platforms) await _checkPlatformDirectory(platform),
    ];
  }

  Future<_DoctorCheck> _checkPlatformDirectory(FluohPlatform platform) async {
    final directory = Directory(
      '${environment.workingDirectory.path}/${platform.cliName}',
    );
    final title = '${_platformDisplayName(platform)} project platform';
    if (await directory.exists()) {
      return _DoctorCheck.ok(_DoctorCheckGroup.project, title, [
        '${platform.cliName} platform directory exists.',
      ]);
    }
    return _DoctorCheck.warning(_DoctorCheckGroup.project, title, [
      'Missing ${platform.cliName} platform directory.',
    ]);
  }

  Future<_DoctorCheck> _checkOhosToolchain() async {
    OhosToolchain toolchain;
    try {
      toolchain = await locateOhosToolchain(
        environment: environment.processEnvironment,
      );
    } on Object catch (error) {
      return _DoctorCheck.warning(
        _DoctorCheckGroup.environment,
        'OHOS local tools',
        [
          'DevEco Studio OpenHarmony tools were not found.',
          error.toString(),
          'Set FLUOH_DEVECO_STUDIO to the DevEco Studio .app path if it is not installed in the default location.',
        ],
      );
    }

    final details = <String>[
      'DevEco Studio: ${toolchain.devEcoStudio.path}.',
      'OpenHarmony SDK: ${toolchain.openHarmonySdk.path}.',
      'hap-sign-tool: ${toolchain.hapSignTool.path}.',
      'hdc: ${toolchain.hdc.path}.',
    ];
    var healthy = true;

    if (await toolchain.emulator.exists()) {
      details.add('Emulator: ${toolchain.emulator.path}.');
    } else {
      healthy = false;
      details.add(
        'DevEco emulator binary is missing: ${toolchain.emulator.path}.',
      );
    }

    final emulators = await discoverOhosLocalEmulators(
      environment: environment,
    );
    if (emulators.isEmpty) {
      healthy = false;
      details.add(
        'No local DevEco emulator HVD was found; create one in Device Manager or use --device <id> with a connected target.',
      );
    } else {
      details.add(
        'Local emulators: ${emulators.map((item) => item.name).join(', ')}.',
      );
    }

    return healthy
        ? _DoctorCheck.ok(
            _DoctorCheckGroup.environment,
            'OHOS local tools',
            details,
          )
        : _DoctorCheck.warning(
            _DoctorCheckGroup.environment,
            'OHOS local tools',
            details,
          );
  }

  Future<List<_DoctorCheck>> _checkPlatformToolchains(
    List<FluohPlatform> platforms,
  ) async {
    final checks = <_DoctorCheck>[];
    if (platforms.contains(FluohPlatform.ohos)) {
      checks.add(await _checkOhosToolchain());
    }
    final nativePlatforms = [
      for (final platform in platforms)
        if (platform != FluohPlatform.ohos) platform,
    ];
    if (nativePlatforms.isEmpty) {
      return checks;
    }
    final reports = await inspectPlatformEnvironment(
      environment: environment,
      platforms: nativePlatforms,
    );
    checks.addAll([
      for (final report in reports)
        report.ok
            ? _DoctorCheck.ok(
                _DoctorCheckGroup.environment,
                [
                  _platformDisplayName(report.platform),
                  'native tools',
                ].join(' '),
                [
                  for (final check in report.checks)
                    '${check.label}: ${check.message}',
                ],
              )
            : _DoctorCheck.warning(
                _DoctorCheckGroup.environment,
                [
                  _platformDisplayName(report.platform),
                  'native tools',
                ].join(' '),
                [
                  for (final check in report.checks)
                    '${check.label}: ${check.message}',
                ],
              ),
    ]);
    return checks;
  }

  void _printChecks(_DoctorScope scope, List<_DoctorCheck> checks) {
    _output.section('Doctor summary (${scope.cliName}):');
    final groups = _DoctorCheckGroup.values
        .where((group) => checks.any((check) => check.group == group))
        .toList();
    for (final group in groups) {
      if (groups.length > 1) {
        _output.section('${group.title}:');
      }
      for (final check in checks.where((check) => check.group == group)) {
        final marker = check.status == _DoctorCheckStatus.ok
            ? _style.symbols.success
            : _style.symbols.warning;
        _output.write(
          _style.status(
            check.status.terminalStatus,
            '[$marker] ${check.title}',
          ),
        );
        for (final detail in check.details) {
          _output.detail(detail);
        }
      }
    }

    final issueCount = _issueCount(checks);
    if (issueCount == 0) {
      _output.success('Doctor found no issues.');
    } else if (issueCount == 1) {
      _output.warning('Doctor found issues in 1 category.');
    } else {
      _output.warning('Doctor found issues in $issueCount categories.');
    }
  }
}

int _issueCount(List<_DoctorCheck> checks) {
  return checks
      .where((check) => check.status == _DoctorCheckStatus.warning)
      .length;
}

_DoctorScope _scopeFromArguments(
  ArgResults results,
  UsageError usageException,
) {
  final rest = results.rest;
  if (rest.isEmpty) {
    return _DoctorScope.all;
  }
  if (rest.length > 1) {
    usageException('Unexpected arguments: ${rest.join(' ')}.');
  }
  final value = rest.single;
  for (final scope in _DoctorScope.values) {
    if (scope.matches(value)) {
      return scope;
    }
  }
  usageException('Unknown doctor scope: $value.');
}

List<FluohPlatform> _platformsFromOption(String? value) {
  return switch (value) {
    'all' => const [
      FluohPlatform.ohos,
      FluohPlatform.android,
      FluohPlatform.ios,
    ],
    'ohos' => const [FluohPlatform.ohos],
    'android' => const [FluohPlatform.android],
    'ios' => const [FluohPlatform.ios],
    _ => const [FluohPlatform.ohos],
  };
}

String _platformDisplayName(FluohPlatform platform) {
  return switch (platform) {
    FluohPlatform.android => 'Android',
    FluohPlatform.ios => 'iOS',
    FluohPlatform.ohos => 'OHOS',
  };
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

class _DoctorCheck {
  const _DoctorCheck._(this.group, this.status, this.title, this.details);

  factory _DoctorCheck.ok(
    _DoctorCheckGroup group,
    String title,
    List<String> details,
  ) {
    return _DoctorCheck._(group, _DoctorCheckStatus.ok, title, details);
  }

  factory _DoctorCheck.warning(
    _DoctorCheckGroup group,
    String title,
    List<String> details,
  ) {
    return _DoctorCheck._(group, _DoctorCheckStatus.warning, title, details);
  }

  final _DoctorCheckGroup group;
  final _DoctorCheckStatus status;
  final String title;
  final List<String> details;

  Map<String, Object?> toJson() {
    return {
      'group': group.cliName,
      'title': title,
      'status': status.name,
      'details': details,
    };
  }
}

enum _DoctorScope { environment, project, all }

extension on _DoctorScope {
  String get cliName {
    return switch (this) {
      _DoctorScope.environment => 'env',
      _DoctorScope.project => 'project',
      _DoctorScope.all => 'all',
    };
  }

  String get description {
    return switch (this) {
      _DoctorScope.environment =>
        'Check global fluoh configuration and local toolchains.',
      _DoctorScope.project =>
        'Check the current FlutterOH project configuration.',
      _DoctorScope.all => 'Run both environment and project checks.',
    };
  }

  List<String> get aliases {
    return switch (this) {
      _DoctorScope.environment => const ['environment', 'global'],
      _DoctorScope.project => const [],
      _DoctorScope.all => const [],
    };
  }

  bool matches(String value) {
    return value == cliName || aliases.contains(value);
  }

  bool get includesEnvironment =>
      this == _DoctorScope.environment || this == _DoctorScope.all;

  bool get includesProject =>
      this == _DoctorScope.project || this == _DoctorScope.all;
}

enum _DoctorCheckGroup { environment, project }

extension on _DoctorCheckGroup {
  String get cliName {
    return switch (this) {
      _DoctorCheckGroup.environment => 'environment',
      _DoctorCheckGroup.project => 'project',
    };
  }

  String get title {
    return switch (this) {
      _DoctorCheckGroup.environment => 'Environment checks',
      _DoctorCheckGroup.project => 'Project checks',
    };
  }
}

enum _DoctorCheckStatus { ok, warning }

extension on _DoctorCheckStatus {
  TerminalStatus get terminalStatus {
    return switch (this) {
      _DoctorCheckStatus.ok => TerminalStatus.ok,
      _DoctorCheckStatus.warning => TerminalStatus.warning,
    };
  }
}

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
