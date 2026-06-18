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
import '../platform/ohos/ohos_toolchain.dart';
import '../platform/platform_environment.dart';
import '../sdk/sdk_project_config.dart';
import '../source/source_sync.dart';
import '../version.dart';

part 'doctor_support.dart';

/// Provides latest fluoh version metadata for doctor checks.
typedef DoctorVersionMetadataProvider =
    Future<DoctorVersionMetadata?> Function();

/// Provides the current script URI for installation diagnostics.
typedef DoctorScriptUriProvider = Uri Function();

const _ohosToolchainBaseTitle =
    'OpenHarmony toolchain - develop for OHOS devices';
const _androidToolchainBaseTitle =
    'Android toolchain - develop for Android devices';
const _iosToolchainBaseTitle = 'Xcode - develop for iOS devices';
const _macosToolchainBaseTitle = 'Xcode - develop for macOS desktop';
const _linuxToolchainBaseTitle = 'Linux toolchain - develop for Linux desktop';
const _windowsToolchainBaseTitle =
    'Windows toolchain - develop for Windows desktop';
const _webToolchainBaseTitle = 'Chrome - develop for the web';
const _appleToolchainBaseTitle = 'Xcode - develop for iOS and macOS';

/// Version metadata used by `fluoh doctor`.
class DoctorVersionMetadata {
  /// Creates doctor version metadata.
  const DoctorVersionMetadata({
    required this.latestVersion,
    this.currentVersionPublished,
  });

  /// Latest available fluoh version, when known.
  final String? latestVersion;

  /// Publish timestamp for the current CLI version, when known.
  final String? currentVersionPublished;
}

/// Reports fluoh, project, Source, SDK, and native toolchain health.
class DoctorCommand extends FluohCommand<int> {
  /// Creates the doctor command.
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
        valueHelp: 'platform',
        allowed: fluohPlatformOptionValues,
        help: 'Platforms to check. All platforms are checked by default.',
        allowedHelp: const {
          'all':
              'Check OHOS, Android, Web, and platforms supported by this host.',
          'ohos': 'Check OHOS local tooling.',
          'android': 'Check Android SDK, adb, emulator, avdmanager, and Java.',
          'ios': 'Check Xcode xcrun and simctl.',
          'macos': 'Check macOS host and Xcode command line tools.',
          'linux': 'Check Linux host and desktop build tools.',
          'web': 'Check Flutter web build and optional browser tooling.',
          'windows': 'Check Windows host and desktop build tools.',
        },
      );
  }

  /// Runtime environment used for filesystem, process, and home lookup.
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
    if (options.json) {
      final report = await _buildReport(options);
      final exitCode = options.strict && report.issueCount > 0 ? 1 : 0;
      writeMachineOutput(
        _output.write,
        command: name,
        ok: report.ok,
        exitCode: exitCode,
        fields: report.toJsonFields(includeNextAction: options.strict),
      );
      return exitCode;
    }

    var printedChecks = 0;
    final report = await _buildReport(
      options,
      onCheck: (check) {
        _printCheck(check, leadingBlank: printedChecks > 0);
        printedChecks += 1;
      },
    );
    _printSummary(report);
    final exitCode = options.strict && report.issueCount > 0 ? 1 : 0;
    return exitCode;
  }

  Future<_DoctorReport> _buildReport(
    _DoctorOptions options, {
    void Function(_DoctorCheck check)? onCheck,
  }) async {
    final checks = await _environmentChecks(
      options.platforms,
      onCheck: onCheck,
    );
    if (options.includeProject) {
      await _addTimedCheck(
        checks,
        () => _checkFlutterProject(options.platforms),
        onCheck: onCheck,
      );
    }

    return _DoctorReport(
      includeProject: options.includeProject,
      platforms: options.platforms,
      checks: checks,
    );
  }

  Future<List<_DoctorCheck>> _environmentChecks(
    List<FluohPlatform> platforms, {
    void Function(_DoctorCheck check)? onCheck,
  }) async {
    final checks = <_DoctorCheck>[];
    await _addTimedCheck(checks, _checkFluohInstallation, onCheck: onCheck);
    await _addTimedCheck(checks, _checkSources, onCheck: onCheck);
    checks.addAll(await _checkPlatformToolchains(platforms, onCheck: onCheck));
    await _addTimedCheck(
      checks,
      () => _checkConnectedDevices(platforms),
      onCheck: onCheck,
    );
    return checks;
  }

  Future<void> _addTimedCheck(
    List<_DoctorCheck> checks,
    Future<_DoctorCheck> Function() check, {
    void Function(_DoctorCheck check)? onCheck,
  }) async {
    final result = await _timedCheck(check);
    checks.add(result);
    onCheck?.call(result);
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
    final git = await _checkGitAvailable();
    final details = <_DoctorDetail>[
      _DoctorDetail.ok(_installationDescription(installation)),
      _DoctorDetail.ok('fluoh home at ${environment.homeDirectory.path}'),
      _DoctorDetail.ok('Dart version ${_dartVersion()}'),
      _DoctorDetail.ok('Dart executable at ${Platform.resolvedExecutable}'),
      git.detail,
    ];
    DoctorVersionMetadata? versionMetadata;
    try {
      versionMetadata = await _versionMetadataProvider();
    } on Exception catch (error) {
      details.add(
        _DoctorDetail.ok(
          'Could not check the latest version from pub.dev: ${error.toString()}',
        ),
      );
      return _fluohCheck(title, details, gitOk: git.ok);
    }

    if (versionMetadata?.currentVersionPublished case final published?) {
      details.add(_DoctorDetail.ok('Current version published: $published'));
    }
    final latestVersion = versionMetadata?.latestVersion;
    if (latestVersion == null || latestVersion.isEmpty) {
      details.add(
        _DoctorDetail.ok('Could not check the latest version from pub.dev.'),
      );
      return _fluohCheck(title, details, gitOk: git.ok);
    }

    if (_compareVersions(latestVersion, packageVersion) > 0) {
      details.add(_DoctorDetail.ok('Latest version: $latestVersion'));
      if (installation.method == FluohInstallMethod.localSourceCheckout) {
        details.add(
          _DoctorDetail.warning(
            'Upgrade available, but local source checkouts cannot be upgraded '
            'automatically.',
          ),
        );
      } else {
        details.add(
          _DoctorDetail.warning(
            'Upgrade available: $latestVersion; run `fluoh upgrade`',
          ),
        );
      }
      return _fluohCheck(title, details, gitOk: git.ok, upgradeAvailable: true);
    }

    details.add(_DoctorDetail.ok('Latest version: $latestVersion'));
    details.add(_DoctorDetail.ok('Up to date'));
    return _fluohCheck(title, details, gitOk: git.ok);
  }

  _DoctorCheck _fluohCheck(
    String title,
    List<_DoctorDetail> details, {
    required bool gitOk,
    bool upgradeAvailable = false,
  }) {
    final textDetails = details.map((detail) => detail.text).toList();
    final healthy = gitOk && !upgradeAvailable;
    return healthy
        ? _DoctorCheck.ok(
            _DoctorCheckGroup.environment,
            'fluoh',
            textDetails,
            id: 'fluoh.installation',
            summaryTitle: title,
            detailItems: details,
          )
        : _DoctorCheck.warning(
            _DoctorCheckGroup.environment,
            'fluoh',
            textDetails,
            id: 'fluoh.installation',
            summaryTitle: title,
            detailItems: details,
          );
  }

  Future<_GitAvailability> _checkGitAvailable() async {
    try {
      final result = await Process.run('git', [
        '--version',
      ], environment: environment.processEnvironment);
      final version = result.stdout.toString().trim();
      if (result.exitCode != 0) {
        final detail =
            _firstNonEmptyLine(result.stderr.toString()) ??
            _firstNonEmptyLine(result.stdout.toString()) ??
            'git --version exited with code ${result.exitCode}.';
        return _GitAvailability(
          ok: false,
          detail: _DoctorDetail.warning('Git unavailable: $detail'),
        );
      }
      final displayVersion = version.startsWith('git version ')
          ? 'Git version ${version.substring('git version '.length)}'
          : version;
      return _GitAvailability(
        ok: true,
        detail: _DoctorDetail.ok(
          displayVersion.isNotEmpty ? displayVersion : 'Git is available',
        ),
      );
    } on ProcessException {
      return const _GitAvailability(
        ok: false,
        detail: _DoctorDetail.warning(
          'Git unavailable: install Git and make sure it is on PATH.',
        ),
      );
    }
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
          'OpenHarmony SDK toolchains were not found',
          'Set FLUOH_DEVECO_STUDIO if the SDK is installed outside the default location.',
        ],
        summaryTitle: _ohosToolchainBaseTitle,
        jsonDetails: [
          'OpenHarmony SDK toolchains were not found',
          ?message,
          'Set FLUOH_DEVECO_STUDIO if the SDK is installed outside the default location.',
        ],
        id: 'ohos.toolchain',
      );
    }

    final openHarmonyVersion = await _readOpenHarmonySdkVersion(
      toolchain.openHarmonySdk,
    );
    final hdcVersion = _normalizeHdcVersion(
      await _commandVersion(toolchain.hdc, const [
        '-v',
      ], environment: environment.processEnvironment),
    );
    final emulatorExists = await toolchain.emulator.exists();
    final emulatorVersion = emulatorExists
        ? _normalizeOhosEmulatorVersion(
            await _commandVersion(toolchain.emulator, const [
              '-version',
            ], environment: environment.processEnvironment),
          )
        : null;
    final details = <String>[
      'OpenHarmony SDK at ${toolchain.openHarmonySdk.path}',
      hdcVersion == null ? 'hdc found' : 'hdc version $hdcVersion',
      !emulatorExists
          ? 'Emulator was not found at ${toolchain.emulator.path}'
          : emulatorVersion == null
          ? 'Emulator version unknown'
          : 'Emulator version $emulatorVersion',
    ];

    return _checkForStatus(
      healthy: emulatorExists,
      group: _DoctorCheckGroup.environment,
      id: 'ohos.toolchain',
      title: 'OpenHarmony toolchain',
      details: details,
      summaryTitle: _ohosToolchainSummaryTitle(version: openHarmonyVersion),
      data: {
        'tools': {
          'openHarmonySdk': _toolData(
            toolchain.openHarmonySdk.path,
            openHarmonyVersion,
          ),
          'hdc': _toolData(toolchain.hdc.path, hdcVersion),
          'emulator': emulatorExists
              ? _toolData(toolchain.emulator.path, emulatorVersion)
              : {'path': toolchain.emulator.path, 'missing': true},
        },
      },
    );
  }

  Future<List<_DoctorCheck>> _checkPlatformToolchains(
    List<FluohPlatform> platforms, {
    void Function(_DoctorCheck check)? onCheck,
  }) async {
    final checks = <_DoctorCheck>[];
    if (platforms.contains(FluohPlatform.ohos)) {
      await _addTimedCheck(checks, _checkOhosToolchain, onCheck: onCheck);
    }
    final nativePlatforms = [
      for (final platform in platforms)
        if (platform != FluohPlatform.ohos) platform,
    ];
    final hasIos = nativePlatforms.contains(FluohPlatform.ios);
    final hasMacos = nativePlatforms.contains(FluohPlatform.macos);
    var checkedApplePlatforms = false;
    for (final platform in nativePlatforms) {
      if ((platform == FluohPlatform.ios || platform == FluohPlatform.macos) &&
          hasIos &&
          hasMacos) {
        if (!checkedApplePlatforms) {
          await _addTimedCheck(
            checks,
            () => _checkApplePlatformToolchain(),
            onCheck: onCheck,
          );
          checkedApplePlatforms = true;
        }
        continue;
      }
      await _addTimedCheck(
        checks,
        () => _checkNativePlatformToolchain(platform),
        onCheck: onCheck,
      );
    }
    return checks;
  }

  Future<_DoctorCheck> _checkApplePlatformToolchain() async {
    final reports = await inspectPlatformEnvironment(
      environment: environment,
      platforms: const [FluohPlatform.ios, FluohPlatform.macos],
    );
    return _checkForStatus(
      healthy: reports.every((report) => report.ok),
      group: _DoctorCheckGroup.environment,
      id: 'apple.toolchain',
      title: 'Apple toolchain',
      details: _appleToolDetails(reports),
      summaryTitle: _appleToolSummaryTitle(reports),
      jsonDetails: _appleToolDetails(reports),
      data: {'reports': reports.map((report) => report.toJson()).toList()},
    );
  }

  Future<_DoctorCheck> _checkConnectedDevices(
    List<FluohPlatform> platforms,
  ) async {
    final reports = await listPlatformDeviceReports(
      environment: environment,
      platforms: platforms,
    );
    final details = <_DoctorDetail>[];
    final jsonDetails = <String>[];
    final targets = <PlatformTarget>[];
    var failedReports = 0;

    for (final report in reports) {
      if (!report.ok) {
        failedReports += 1;
        final message =
            '${_platformDisplayName(report.platform)} devices unavailable: '
            '${report.message ?? 'could not list devices'}';
        details.add(_DoctorDetail.warning(message));
        jsonDetails.add(message);
        continue;
      }
      targets.addAll(report.targets);
    }

    targets.sort((left, right) {
      final platform = left.platform.cliName.compareTo(right.platform.cliName);
      return platform == 0 ? left.name.compareTo(right.name) : platform;
    });

    final targetRows = _targetDisplayRows(targets);
    for (final detail in _formatTargetRows(targetRows)) {
      details.add(_DoctorDetail.ok(detail, wrap: false));
    }
    jsonDetails.addAll(targetRows.map((row) => row.plainText));
    if (targets.isEmpty && failedReports == 0) {
      const message = 'No connected devices detected';
      details.add(_DoctorDetail.ok(message));
      jsonDetails.add(message);
    }

    final title = targets.isEmpty
        ? 'Connected devices'
        : 'Connected device${targets.length == 1 ? '' : 's'} '
              '(${targets.length} available)';
    final data = {
      'reports': reports.map((report) => report.toJson()).toList(),
      'targets': targetRows.map((row) => row.toJson()).toList(),
    };
    return failedReports == 0
        ? _DoctorCheck.ok(
            _DoctorCheckGroup.environment,
            'Connected devices',
            jsonDetails,
            id: 'connected.devices',
            summaryTitle: title,
            detailItems: details,
            data: data,
          )
        : _DoctorCheck.warning(
            _DoctorCheckGroup.environment,
            'Connected devices',
            jsonDetails,
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

  void _printCheck(_DoctorCheck check, {required bool leadingBlank}) {
    if (leadingBlank) {
      _output.blank();
    }
    final timing = check.elapsed != null
        ? ' [${_formatElapsed(check.elapsed!)}]'
        : '';
    _writeDoctorHeading(check.status, '${check.summaryTitle}$timing');
    for (final detail in check.displayDetails) {
      _writeDoctorDetail(check.status, detail);
    }
  }

  void _printSummary(_DoctorReport report) {
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
    if (!detail.wrap) {
      _output.write('    $bullet ${_style.paint(detail.text, bold: true)}');
      return;
    }
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
