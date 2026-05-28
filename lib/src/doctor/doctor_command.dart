import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import '../cli/argument_validation.dart';
import '../cli/fluoh_command_runner.dart';
import '../cli/fluoh_installation.dart';
import '../cli/machine_output.dart';
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

const _ohosToolchainBaseTitle =
    'OpenHarmony toolchain - develop for OHOS devices';
const _androidToolchainBaseTitle =
    'Android toolchain - develop for Android devices';
const _iosToolchainBaseTitle = 'Xcode - develop for iOS devices';

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
        'project',
        abbr: 'p',
        negatable: false,
        help: 'Also check the current FlutterOH project.',
      )
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
        help: 'Platforms to check. All platforms are checked by default.',
        allowedHelp: const {
          'all': 'Check OHOS, Android, and iOS.',
          'ohos': 'Check OHOS local tooling.',
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
  String get description =>
      'Diagnose fluoh environment and optional project setup.';

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
      'Usage: ${runner!.executableName} $name [-p|--project] [--platform <name>]',
      argParser.usage,
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    return _run(argResults!);
  }

  Future<int> _run(ArgResults results) async {
    final options = _DoctorOptions.fromArgResults(results);
    final report = await _buildReport(options);
    final exitCode = options.strict && report.issueCount > 0 ? 1 : 0;

    if (options.json) {
      writeMachineOutput(
        _output.write,
        command: name,
        ok: report.ok,
        exitCode: exitCode,
        fields: report.toJsonFields(),
      );
    } else {
      _printReport(report);
    }
    return exitCode;
  }

  Future<_DoctorReport> _buildReport(_DoctorOptions options) async {
    final checks = await _environmentChecks(options.platforms);
    if (options.includeProject) {
      checks.add(
        await _timedCheck(() => _checkFlutterProject(options.platforms)),
      );
    }

    return _DoctorReport(
      includeProject: options.includeProject,
      platforms: options.platforms,
      checks: checks,
    );
  }

  Future<List<_DoctorCheck>> _environmentChecks(
    List<FluohPlatform> platforms,
  ) async {
    return [
      await _timedCheck(_checkFluohInstallation),
      await _timedCheck(_checkSources),
      ...await _checkPlatformToolchains(platforms),
      await _timedCheck(() => _checkConnectedDevices(platforms)),
    ];
  }

  Future<_DoctorCheck> _timedCheck(
    Future<_DoctorCheck> Function() check,
  ) async {
    final stopwatch = Stopwatch()..start();
    final result = await check();
    stopwatch.stop();
    return result.withElapsed(stopwatch.elapsed);
  }

  Future<_DoctorCheck> _checkFluohInstallation() async {
    final installation = resolveFluohInstallation(_scriptUriProvider());
    final title = _fluohSummaryTitle();
    final details = [
      _installationDescription(installation),
      'fluoh home at ${environment.homeDirectory.path}',
      'Dart version ${_dartVersion()}',
      'Dart executable at ${Platform.resolvedExecutable}',
    ];
    DoctorVersionMetadata? versionMetadata;
    try {
      versionMetadata = await _versionMetadataProvider();
    } on Exception catch (error) {
      details.add(
        'Could not check the latest version from pub.dev: ${error.toString()}',
      );
      return _DoctorCheck.ok(
        _DoctorCheckGroup.environment,
        'fluoh',
        details,
        id: 'fluoh.installation',
        summaryTitle: title,
      );
    }

    if (versionMetadata?.currentVersionPublished case final published?) {
      details.add('Current version published: $published');
    }
    final latestVersion = versionMetadata?.latestVersion;
    if (latestVersion == null || latestVersion.isEmpty) {
      details.add('Could not check the latest version from pub.dev.');
      return _DoctorCheck.ok(
        _DoctorCheckGroup.environment,
        'fluoh',
        details,
        id: 'fluoh.installation',
        summaryTitle: title,
      );
    }

    if (_compareVersions(latestVersion, packageVersion) > 0) {
      details.add('Latest version: $latestVersion');
      if (installation.method == FluohInstallMethod.localSourceCheckout) {
        details.add(
          'Upgrade available, but local source checkouts cannot be upgraded '
          'automatically.',
        );
      } else {
        details.add('Upgrade available: $latestVersion; run `fluoh upgrade`');
      }
      return _DoctorCheck.warning(
        _DoctorCheckGroup.environment,
        'fluoh',
        details,
        id: 'fluoh.installation',
        summaryTitle: title,
      );
    }

    details.add('Latest version: $latestVersion');
    details.add('Up to date');
    return _DoctorCheck.ok(
      _DoctorCheckGroup.environment,
      'fluoh',
      details,
      id: 'fluoh.installation',
      summaryTitle: title,
    );
  }

  Future<_DoctorCheck> _checkFlutterProject(
    List<FluohPlatform> platforms,
  ) async {
    final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
    if (!await pubspec.exists()) {
      return _DoctorCheck.warning(
        _DoctorCheckGroup.project,
        'Flutter project',
        ['Current directory is not a Flutter project'],
        id: 'project.flutter',
      );
    }

    var isFlutterProject = false;
    try {
      final yaml = loadYaml(await pubspec.readAsString());
      final dependencies = yaml is YamlMap ? yaml['dependencies'] : null;
      final flutter = dependencies is YamlMap ? dependencies['flutter'] : null;
      if (flutter is YamlMap && flutter['sdk'] == 'flutter') {
        isFlutterProject = true;
      }
    } on FormatException {
      // Report as a project warning below.
    }

    if (!isFlutterProject) {
      return _DoctorCheck.warning(
        _DoctorCheckGroup.project,
        'Flutter project',
        ['Current directory is not a Flutter project'],
        id: 'project.flutter',
      );
    }

    final details = <_DoctorDetail>[
      _DoctorDetail.ok('Detected Flutter project'),
    ];
    var healthy = true;

    try {
      final sdkVersion = await readProjectSdkVersion(
        environment.workingDirectory,
      );
      if (sdkVersion == null) {
        details.add(_DoctorDetail.warning('No FlutterOH SDK selected'));
        healthy = false;
      } else {
        details.add(_DoctorDetail.ok('FlutterOH SDK $sdkVersion selected'));
      }
    } on UsageException catch (error) {
      details.add(_DoctorDetail.warning(error.message));
      healthy = false;
    } on FormatException {
      details.add(_DoctorDetail.warning('fluoh.yaml is not valid YAML'));
      healthy = false;
    }

    final platformData = <String, Object?>{};
    for (final platform in platforms) {
      final path = platform.cliName;
      final directory = Directory('${environment.workingDirectory.path}/$path');
      final exists = await directory.exists();
      platformData[platform.cliName] = {'path': path, 'exists': exists};
      if (exists) {
        details.add(_DoctorDetail.ok('$path platform directory exists'));
      } else {
        details.add(_DoctorDetail.warning('Missing $path platform directory'));
        healthy = false;
      }
    }

    final plainDetails = details.map((detail) => detail.text).toList();
    final data = {'platformDirectories': platformData};
    if (healthy) {
      return _DoctorCheck.ok(
        _DoctorCheckGroup.project,
        'Flutter project',
        plainDetails,
        id: 'project.flutter',
        detailItems: details,
        data: data,
      );
    }
    return _DoctorCheck.warning(
      _DoctorCheckGroup.project,
      'Flutter project',
      [...plainDetails],
      id: 'project.flutter',
      detailItems: details,
      data: data,
    );
  }

  Future<_DoctorCheck> _checkSources() async {
    final config = await FluohConfigStore(environment).load();
    if (config.sources.isEmpty) {
      return _DoctorCheck.warning(_DoctorCheckGroup.environment, 'Sources', [
        'No sources configured',
      ], id: 'source.snapshots');
    }

    final details = <_DoctorDetail>[];
    var availableCount = 0;
    var issueCount = 0;
    for (final entry in config.sources.entries) {
      final source = entry.value;
      final sourceDirectory = entry.value.directory;
      final sourceManifest = File('${sourceDirectory.path}/fluoh.yaml');
      if (!await sourceDirectory.exists() || !await sourceManifest.exists()) {
        issueCount += 1;
        details.add(
          _DoctorDetail.warning(
            '${entry.key}: ${source.displayValue} (not updated)',
          ),
        );
        continue;
      }

      try {
        await validateSource(entry.key, entry.value);
        availableCount += 1;
        details.add(_DoctorDetail.ok('${entry.key}: ${source.displayValue}'));
      } on UsageException catch (error) {
        issueCount += 1;
        details.add(
          _DoctorDetail.warning(
            '${entry.key}: ${source.displayValue} (${error.message})',
          ),
        );
      }
    }

    if (availableCount == 0 && issueCount == 0) {
      details.add(_DoctorDetail.warning('No sources have been updated'));
      issueCount += 1;
    }

    return issueCount == 0 && availableCount > 0
        ? _DoctorCheck.ok(
            _DoctorCheckGroup.environment,
            'Sources',
            details.map((detail) => detail.text).toList(),
            id: 'source.snapshots',
            detailItems: details,
          )
        : _DoctorCheck.warning(
            _DoctorCheckGroup.environment,
            'Sources',
            details.map((detail) => detail.text).toList(),
            id: 'source.snapshots',
            detailItems: details,
          );
  }

  Future<_DoctorCheck> _checkOhosToolchain() async {
    OhosToolchain toolchain;
    try {
      toolchain = await locateOhosToolchain(
        environment: environment.processEnvironment,
      );
    } on Object catch (error) {
      final message = _singleLine(error.toString());
      return _DoctorCheck.warning(
        _DoctorCheckGroup.environment,
        'OpenHarmony toolchain',
        [
          'DevEco Studio OpenHarmony tools were not found',
          'Set FLUOH_DEVECO_STUDIO to the DevEco Studio .app path if it is not installed in the default location.',
        ],
        summaryTitle: _ohosToolchainBaseTitle,
        jsonDetails: [
          'DevEco Studio OpenHarmony tools were not found',
          ?message,
          'Set FLUOH_DEVECO_STUDIO to the DevEco Studio .app path if it is not installed in the default location.',
        ],
        id: 'ohos.toolchain',
      );
    }

    final devEcoVersion = await _readDevEcoVersion(toolchain.devEcoStudio);
    final openHarmonyVersion = await _readOpenHarmonySdkVersion(
      toolchain.openHarmonySdk,
    );
    final hdcVersion = _normalizeHdcVersion(
      await _commandVersion(toolchain.hdc, const [
        '-v',
      ], environment: environment.processEnvironment),
    );
    final details = <String>[
      _foundDetail('DevEco Studio', devEcoVersion),
      _foundDetail('OpenHarmony SDK', openHarmonyVersion),
      'Signing tools found',
      _foundDetail('hdc', hdcVersion),
    ];
    final jsonDetails = <String>[
      _pathDetail('DevEco Studio', toolchain.devEcoStudio.path, devEcoVersion),
      _pathDetail(
        'OpenHarmony SDK',
        toolchain.openHarmonySdk.path,
        openHarmonyVersion,
      ),
      'hap-sign-tool at ${toolchain.hapSignTool.path}',
      _pathDetail('hdc', toolchain.hdc.path, hdcVersion),
    ];
    var healthy = true;

    if (await toolchain.emulator.exists()) {
      details.add('DevEco emulator found');
      jsonDetails.add('Emulator at ${toolchain.emulator.path}');
    } else {
      healthy = false;
      details.add('DevEco emulator binary is missing');
      jsonDetails.add(
        'DevEco emulator binary is missing: ${toolchain.emulator.path}',
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
      final emulatorNames = emulators.map((item) => item.name).join(', ');
      details.add('Local emulators: $emulatorNames');
      jsonDetails.add('Local emulators: $emulatorNames');
    }

    return _checkForStatus(
      healthy: healthy,
      group: _DoctorCheckGroup.environment,
      id: 'ohos.toolchain',
      title: 'OpenHarmony toolchain',
      details: details,
      summaryTitle: healthy
          ? _ohosToolchainSummaryTitle(version: devEcoVersion)
          : _ohosToolchainBaseTitle,
      jsonDetails: jsonDetails,
      data: {
        'tools': {
          'devEcoStudio': _toolData(toolchain.devEcoStudio.path, devEcoVersion),
          'openHarmonySdk': _toolData(
            toolchain.openHarmonySdk.path,
            openHarmonyVersion,
          ),
          'hapSignTool': toolchain.hapSignTool.path,
          'hdc': _toolData(toolchain.hdc.path, hdcVersion),
          'emulator': toolchain.emulator.path,
        },
        'localEmulators': [for (final emulator in emulators) emulator.name],
      },
    );
  }

  Future<List<_DoctorCheck>> _checkPlatformToolchains(
    List<FluohPlatform> platforms,
  ) async {
    final checks = <_DoctorCheck>[];
    if (platforms.contains(FluohPlatform.ohos)) {
      checks.add(await _timedCheck(_checkOhosToolchain));
    }
    final nativePlatforms = [
      for (final platform in platforms)
        if (platform != FluohPlatform.ohos) platform,
    ];
    checks.addAll([
      for (final platform in nativePlatforms)
        await _timedCheck(() => _checkNativePlatformToolchain(platform)),
    ]);
    return checks;
  }

  Future<_DoctorCheck> _checkConnectedDevices(
    List<FluohPlatform> platforms,
  ) async {
    final reports = await listPlatformDeviceReports(
      environment: environment,
      platforms: platforms,
    );
    final details = <_DoctorDetail>[];
    final targets = <PlatformTarget>[];
    var failedReports = 0;

    for (final report in reports) {
      if (!report.ok) {
        failedReports += 1;
        details.add(
          _DoctorDetail.warning(
            '${_platformDisplayName(report.platform)} devices unavailable: '
            '${report.message ?? 'could not list devices'}',
          ),
        );
        continue;
      }
      targets.addAll(report.targets);
    }

    targets.sort((left, right) {
      final platform = left.platform.cliName.compareTo(right.platform.cliName);
      return platform == 0 ? left.name.compareTo(right.name) : platform;
    });

    for (final target in targets) {
      details.add(_DoctorDetail.ok(_targetDetail(target)));
    }
    if (targets.isEmpty && failedReports == 0) {
      details.add(_DoctorDetail.ok('No connected devices detected'));
    }

    final title = targets.isEmpty
        ? 'Connected devices'
        : 'Connected devices (${targets.length} available)';
    final data = {'reports': reports.map((report) => report.toJson()).toList()};
    final detailText = details.map((detail) => detail.text).toList();
    return failedReports == 0
        ? _DoctorCheck.ok(
            _DoctorCheckGroup.environment,
            'Connected devices',
            detailText,
            id: 'connected.devices',
            summaryTitle: title,
            detailItems: details,
            data: data,
          )
        : _DoctorCheck.warning(
            _DoctorCheckGroup.environment,
            'Connected devices',
            detailText,
            id: 'connected.devices',
            summaryTitle: title,
            detailItems: details,
            data: data,
          );
  }

  Future<_DoctorCheck> _checkNativePlatformToolchain(
    FluohPlatform platform,
  ) async {
    final reports = await inspectPlatformEnvironment(
      environment: environment,
      platforms: [platform],
    );
    final report = reports.single;
    return _checkForStatus(
      healthy: report.ok,
      group: _DoctorCheckGroup.environment,
      id: '${report.platform.cliName}.toolchain',
      title: _platformToolchainTitle(report.platform),
      details: _platformToolSummary(report),
      summaryTitle: _platformToolSummaryTitle(report),
      jsonDetails: _platformToolDetails(report),
      data: _platformToolData(report),
    );
  }

  void _printReport(_DoctorReport report) {
    for (var index = 0; index < report.checks.length; index += 1) {
      if (index > 0) {
        _output.blank();
      }
      final check = report.checks[index];
      final timing = check.elapsed != null
          ? ' [${_formatElapsed(check.elapsed!)}]'
          : '';
      _writeDoctorHeading(check.status, '${check.summaryTitle}$timing');
      for (final detail in check.displayDetails) {
        _writeDoctorDetail(check.status, detail);
      }
    }

    final issueCount = report.issueCount;
    if (issueCount == 0) {
      _output.success('Doctor found no issues.');
    } else if (issueCount == 1) {
      _output.warning('Doctor found issues in 1 category.');
    } else {
      _output.warning('Doctor found issues in $issueCount categories.');
    }
  }

  void _writeDoctorHeading(_DoctorCheckStatus status, String text) {
    final rawMarker = '[${status.marker(_style.symbols)}]';
    final marker = status.formatMarker(_style, rawMarker);
    final width = (fluohUsageLineLength() - rawMarker.length - 1)
        .clamp(20, fluohUsageLineLength())
        .toInt();
    final lines = wrapTerminalText(text, width: width);
    if (lines.isEmpty) {
      _output.write(marker);
      return;
    }
    _output.write('$marker ${lines.first}');
    final continuationPrefix = ' ' * (rawMarker.length + 1);
    for (final line in lines.skip(1)) {
      _output.write('$continuationPrefix$line');
    }
  }

  void _writeDoctorDetail(_DoctorCheckStatus status, _DoctorDetail detail) {
    final detailStatus = detail.status ?? status;
    final bullet = _style.status(
      detailStatus == _DoctorCheckStatus.ok
          ? TerminalStatus.ok
          : TerminalStatus.warning,
      _style.symbols.bullet,
    );
    final lines = _wrapDoctorDetail(detail.text, width: fluohUsageLineLength());
    if (lines.isEmpty) {
      return;
    }
    _output.write('    $bullet ${_style.paint(lines.first, bold: true)}');
    for (final line in lines.skip(1)) {
      _output.write('      ${_style.paint(line, bold: true)}');
    }
  }
}

class _DoctorOptions {
  const _DoctorOptions({
    required this.includeProject,
    required this.platforms,
    required this.strict,
    required this.json,
  });

  factory _DoctorOptions.fromArgResults(ArgResults results) {
    return _DoctorOptions(
      includeProject: results.flag('project'),
      platforms: _platformsFromOption(results.option('platform')),
      strict: results.flag('strict'),
      json: results.flag('json'),
    );
  }

  final bool includeProject;
  final List<FluohPlatform> platforms;
  final bool strict;
  final bool json;
}

class _DoctorReport {
  const _DoctorReport({
    required this.includeProject,
    required this.platforms,
    required this.checks,
  });

  final bool includeProject;
  final List<FluohPlatform> platforms;
  final List<_DoctorCheck> checks;

  int get issueCount => _issueCount(checks);

  bool get ok => issueCount == 0;

  Map<String, Object?> toJsonFields() {
    return {
      'project': includeProject,
      'platforms': platforms.map((platform) => platform.cliName).toList(),
      'issueCount': issueCount,
      'checks': checks.map((check) => check.toJson()).toList(),
    };
  }
}

int _issueCount(List<_DoctorCheck> checks) {
  return checks
      .where((check) => check.status == _DoctorCheckStatus.warning)
      .length;
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
    _ => const [FluohPlatform.ohos, FluohPlatform.android, FluohPlatform.ios],
  };
}

List<String> _platformToolSummary(PlatformDoctorReport report) {
  return [for (final check in report.checks) _platformToolPlainDetail(check)];
}

String _ohosToolchainSummaryTitle({String? version}) {
  final suffix = version == null ? '' : ' (DevEco Studio $version)';
  return '$_ohosToolchainBaseTitle$suffix';
}

Future<String?> _readDevEcoVersion(Directory devEcoStudio) async {
  final infoPlist = File('${devEcoStudio.path}/Contents/Info.plist');
  if (!await infoPlist.exists()) {
    return null;
  }
  final text = await infoPlist.readAsString();
  final match = RegExp(
    r'<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>',
    multiLine: true,
  ).firstMatch(text);
  return match?.group(1)?.trim();
}

Future<String?> _readOpenHarmonySdkVersion(Directory sdk) async {
  for (final path in [
    '${sdk.path}/oh-uni-package.json',
    '${sdk.path}/ets/oh-uni-package.json',
  ]) {
    final file = File(path);
    if (!await file.exists()) {
      continue;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) {
        final version = decoded['version']?.toString().trim();
        if (version != null && version.isNotEmpty) {
          return version;
        }
      }
    } on Object {
      // Ignore unreadable optional SDK metadata.
    }
  }
  return null;
}

Future<String?> _commandVersion(
  File executable,
  List<String> arguments, {
  required Map<String, String> environment,
}) async {
  if (!await executable.exists()) {
    return null;
  }
  try {
    final result = await Process.run(
      executable.path,
      arguments,
      environment: environment,
    ).timeout(const Duration(seconds: 3));
    if (result.exitCode != 0) {
      return null;
    }
    return _firstNonEmptyLine('${result.stdout}\n${result.stderr}');
  } on Object {
    return null;
  }
}

String _foundDetail(String label, String? version) {
  return version == null ? '$label found' : '$label $version';
}

String _pathDetail(String label, String path, String? version) {
  final versionPrefix = version == null ? '' : ' $version';
  return '$label$versionPrefix at $path';
}

String _fluohSummaryTitle() {
  return 'fluoh ($packageVersion, on ${_hostDescription()}, '
      'locale ${Platform.localeName})';
}

String _dartVersion() => Platform.version.split(' ').first;

String _hostDescription() {
  final os = _hostOperatingSystemName();
  final version = Platform.operatingSystemVersion.trim();
  final dartArch = _dartRuntimeArchitecture();
  final parts = <String>[os, if (version.isNotEmpty) version, ?dartArch];
  return parts.join(' ');
}

String _hostOperatingSystemName() {
  return switch (Platform.operatingSystem) {
    'macos' => 'macOS',
    'windows' => 'Windows',
    'linux' => 'Linux',
    'android' => 'Android',
    'ios' => 'iOS',
    final value => value,
  };
}

String? _dartRuntimeArchitecture() {
  final match = RegExp(r'on "([^"]+)"').firstMatch(Platform.version);
  final value = match?.group(1)?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  final normalized = value.replaceAll('_', '-');
  if (Platform.operatingSystem == 'macos' && normalized.startsWith('macos-')) {
    return 'darwin-${normalized.substring('macos-'.length)}';
  }
  return normalized;
}

Object _toolData(String path, String? version) {
  if (version == null) {
    return path;
  }
  return {'path': path, 'version': version};
}

_DoctorCheck _checkForStatus({
  required bool healthy,
  required _DoctorCheckGroup group,
  required String id,
  required String title,
  required List<String> details,
  String? summaryTitle,
  List<String>? jsonDetails,
  Map<String, Object?> data = const {},
}) {
  return healthy
      ? _DoctorCheck.ok(
          group,
          title,
          details,
          id: id,
          summaryTitle: summaryTitle,
          jsonDetails: jsonDetails,
          data: data,
        )
      : _DoctorCheck.warning(
          group,
          title,
          details,
          id: id,
          summaryTitle: summaryTitle,
          jsonDetails: jsonDetails,
          data: data,
        );
}

String _platformToolSummaryTitle(PlatformDoctorReport report) {
  final title = switch (report.platform) {
    FluohPlatform.android => _androidToolchainBaseTitle,
    FluohPlatform.ios => _iosToolchainBaseTitle,
    FluohPlatform.ohos => _ohosToolchainBaseTitle,
  };
  final version = switch (report.platform) {
    FluohPlatform.android =>
      _checkVersion(report, 'android.sdk') ??
          _checkVersion(report, 'android.adb'),
    FluohPlatform.ios => _checkVersion(report, 'ios.xcode'),
    FluohPlatform.ohos => null,
  };
  if (version == null) {
    return title;
  }
  final label = switch (report.platform) {
    FluohPlatform.android =>
      _checkVersion(report, 'android.sdk') == null
          ? 'adb'
          : 'Android SDK version',
    FluohPlatform.ios => 'Xcode',
    FluohPlatform.ohos => '',
  };
  return '$title ($label $version)';
}

String _platformToolchainTitle(FluohPlatform platform) {
  return switch (platform) {
    FluohPlatform.android => 'Android toolchain',
    FluohPlatform.ios => 'iOS toolchain',
    FluohPlatform.ohos => 'OpenHarmony toolchain',
  };
}

String? _checkVersion(PlatformDoctorReport report, String id) {
  for (final check in report.checks) {
    if (check.id == id && check.version != null) {
      return check.version;
    }
  }
  return null;
}

String _platformToolPlainDetail(PlatformToolCheck check) {
  if (!check.ok) {
    return _sentence(check.message);
  }
  if (check.version case final version?) {
    return '${check.label} $version';
  }
  return switch (check.id) {
    'android.sdk' => 'Android SDK found',
    'ios.xcode' => 'Xcode found',
    'ios.simctl' => _sentence(check.message),
    _ => '${check.label} found',
  };
}

String _sentence(String value) {
  return _singleLine(value) ?? '';
}

String _formatElapsed(Duration elapsed) {
  final milliseconds = elapsed.inMilliseconds;
  if (milliseconds < 1000) {
    return '${milliseconds}ms';
  }
  final seconds = milliseconds / 1000;
  return '${seconds.toStringAsFixed(1)}s';
}

String? _singleLine(String value) {
  final line = _firstNonEmptyLine(value);
  if (line == null) {
    return null;
  }
  return line.length <= 240 ? line : '${line.substring(0, 237)}...';
}

String? _normalizeHdcVersion(String? value) {
  if (value == null) {
    return null;
  }
  final match = RegExp(r'^Ver:\s*(.+)$').firstMatch(value.trim());
  return match?.group(1)?.trim() ?? value;
}

String? _firstNonEmptyLine(String value) {
  for (final rawLine in const LineSplitter().convert(value)) {
    final line = rawLine.trim();
    if (line.isNotEmpty) {
      return line;
    }
  }
  return null;
}

List<String> _wrapDoctorDetail(String value, {required int width}) {
  final contentWidth = (width - 6).clamp(32, width).toInt();
  return wrapTerminalText(
    value,
    width: contentWidth,
  ).where((line) => line.isNotEmpty).toList();
}

List<String> _platformToolDetails(PlatformDoctorReport report) {
  return switch (report.platform) {
    FluohPlatform.android => _androidToolDetails(report),
    FluohPlatform.ios => _iosToolDetails(report),
    FluohPlatform.ohos => [
      for (final check in report.checks) _toolDetailLine(check),
    ],
  };
}

List<String> _androidToolDetails(PlatformDoctorReport report) {
  final checks = _checksById(report);
  final sdk = checks['android.sdk'];
  final platform = checks['android.platform'];
  final emulator = checks['android.emulator'];
  final java = checks['android.java'];
  final licenses = checks['android.licenses'];
  final details = <String>[];

  if (sdk == null || !sdk.ok) {
    details.add(_toolDetailLine(sdk));
  } else {
    details.add('Android SDK at ${sdk.path}');
  }

  if (emulator != null) {
    details.add(
      emulator.ok && emulator.version != null
          ? 'Emulator version ${emulator.version}'
          : _toolDetailLine(emulator),
    );
  }

  if (platform != null) {
    final buildTools = platform.details['buildTools']?.toString();
    details.add(
      platform.ok && platform.version != null && buildTools != null
          ? 'Platform ${platform.version}, build-tools $buildTools'
          : _toolDetailLine(platform),
    );
  }

  if (java == null || !java.ok) {
    details.add(_toolDetailLine(java));
  } else {
    details.add('Java binary at ${java.path}');
    if (java.details['androidStudioBundledJdk'] == true) {
      details.add(
        'This is the JDK bundled with the latest Android Studio installation on this machine.',
      );
    }
    details.add('To override the JDK path, set JAVA_HOME or FLUOH_JAVA.');
    if (java.version != null) {
      details.add('Java version ${java.version}');
    }
  }

  if (licenses != null) {
    details.add(_sentence(licenses.message));
  }

  return [
    for (final detail in details)
      if (detail.isNotEmpty) detail,
  ];
}

List<String> _iosToolDetails(PlatformDoctorReport report) {
  final checks = _checksById(report);
  final xcode = checks['ios.xcode'];
  final xcrun = checks['ios.xcrun'];
  final simctl = checks['ios.simctl'];
  final cocoaPods = checks['ios.cocoapods'];
  final details = <String>[];

  if (xcode == null || !xcode.ok) {
    details.add(_toolDetailLine(xcode));
  } else {
    details.add('Xcode at ${xcode.path}');
    if (xcode.details['buildVersion'] case final buildVersion?) {
      details.add('Build $buildVersion');
    }
  }

  if (xcrun != null && !xcrun.ok) {
    details.add(_toolDetailLine(xcrun));
  }
  if (simctl != null && !simctl.ok) {
    details.add(_toolDetailLine(simctl));
  }
  if (cocoaPods != null) {
    details.add(
      cocoaPods.ok && cocoaPods.version != null
          ? 'CocoaPods version ${cocoaPods.version}'
          : _toolDetailLine(cocoaPods),
    );
  }

  return [
    for (final detail in details)
      if (detail.isNotEmpty) detail,
  ];
}

Map<String, PlatformToolCheck> _checksById(PlatformDoctorReport report) {
  return {for (final check in report.checks) check.id: check};
}

String _toolDetailLine(PlatformToolCheck? check) {
  if (check == null) {
    return '';
  }
  if (!check.ok) {
    return _sentence(check.message);
  }
  if (check.path != null && check.version != null) {
    return '${check.label} ${check.version} at ${check.path}';
  }
  if (check.path != null) {
    return '${check.label} at ${check.path}';
  }
  if (check.version != null) {
    return '${check.label} version ${check.version}';
  }
  return _sentence(check.message);
}

Map<String, Object?> _platformToolData(PlatformDoctorReport report) {
  return {'checks': report.checks.map((check) => check.toJson()).toList()};
}

String _platformDisplayName(FluohPlatform platform) {
  return switch (platform) {
    FluohPlatform.android => 'Android',
    FluohPlatform.ios => 'iOS',
    FluohPlatform.ohos => 'OHOS',
  };
}

String _targetDetail(PlatformTarget target) {
  final parts = <String>[
    target.name,
    '(${_platformDisplayName(target.platform)})',
    target.kind,
    target.id,
    if (target.state != null) target.state!,
    if (target.details['details'] != null)
      target.details['details']!.toString(),
    if (target.details['osVersion'] != null)
      'OS ${target.details['osVersion']}',
    if (target.details['model'] != null) target.details['model']!.toString(),
  ];
  return parts.where((part) => part.trim().isNotEmpty).join(' - ');
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

class _DoctorDetail {
  const _DoctorDetail(this.text, {this.status});

  const _DoctorDetail.ok(String text)
    : this(text, status: _DoctorCheckStatus.ok);

  const _DoctorDetail.warning(String text)
    : this(text, status: _DoctorCheckStatus.warning);

  final String text;
  final _DoctorCheckStatus? status;
}

class _DoctorCheck {
  _DoctorCheck._(
    this.group,
    this.status,
    this.id,
    this.title,
    List<String> details, {
    String? summaryTitle,
    List<String>? jsonDetails,
    List<_DoctorDetail>? detailItems,
    this.data = const {},
    this.elapsed,
  }) : summaryTitle = summaryTitle ?? title,
       jsonDetails = jsonDetails ?? details,
       displayDetails =
           detailItems ??
           [for (final detail in jsonDetails ?? details) _DoctorDetail(detail)],
       super();

  factory _DoctorCheck.ok(
    _DoctorCheckGroup group,
    String title,
    List<String> details, {
    required String id,
    String? summaryTitle,
    List<String>? jsonDetails,
    List<_DoctorDetail>? detailItems,
    Map<String, Object?> data = const {},
  }) {
    return _DoctorCheck._(
      group,
      _DoctorCheckStatus.ok,
      id,
      title,
      details,
      summaryTitle: summaryTitle,
      jsonDetails: jsonDetails,
      detailItems: detailItems,
      data: data,
    );
  }

  factory _DoctorCheck.warning(
    _DoctorCheckGroup group,
    String title,
    List<String> details, {
    required String id,
    String? summaryTitle,
    List<String>? jsonDetails,
    List<_DoctorDetail>? detailItems,
    Map<String, Object?> data = const {},
  }) {
    return _DoctorCheck._(
      group,
      _DoctorCheckStatus.warning,
      id,
      title,
      details,
      summaryTitle: summaryTitle,
      jsonDetails: jsonDetails,
      detailItems: detailItems,
      data: data,
    );
  }

  final _DoctorCheckGroup group;
  final _DoctorCheckStatus status;
  final String id;
  final String title;
  final String summaryTitle;
  final List<String> jsonDetails;
  final List<_DoctorDetail> displayDetails;
  final Map<String, Object?> data;
  final Duration? elapsed;

  _DoctorCheck withElapsed(Duration elapsed) {
    return _DoctorCheck._(
      group,
      status,
      id,
      title,
      jsonDetails,
      summaryTitle: summaryTitle,
      jsonDetails: jsonDetails,
      detailItems: displayDetails,
      data: data,
      elapsed: elapsed,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'group': group.cliName,
      'id': id,
      'title': title,
      'status': status.name,
      'details': jsonDetails,
      if (elapsed != null) 'durationMs': elapsed!.inMilliseconds,
      if (data.isNotEmpty) 'data': data,
    };
  }
}

enum _DoctorCheckGroup { environment, project }

extension on _DoctorCheckGroup {
  String get cliName {
    return switch (this) {
      _DoctorCheckGroup.environment => 'environment',
      _DoctorCheckGroup.project => 'project',
    };
  }
}

enum _DoctorCheckStatus { ok, warning }

extension on _DoctorCheckStatus {
  String marker(TerminalSymbols symbols) {
    return switch (this) {
      _DoctorCheckStatus.ok => symbols.success,
      _DoctorCheckStatus.warning => symbols.warning,
    };
  }

  String formatMarker(TerminalStyle style, String marker) {
    return switch (this) {
      _DoctorCheckStatus.ok => style.status(TerminalStatus.ok, marker),
      _DoctorCheckStatus.warning => style.status(
        TerminalStatus.warning,
        marker,
      ),
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
