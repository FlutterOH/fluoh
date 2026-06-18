part of 'doctor_command.dart';

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
      platforms: fluohPlatformsFromCliOption(results.option('platform')),
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

  Map<String, Object?> toJsonFields({bool includeNextAction = false}) {
    return {
      'project': includeProject,
      'platforms': platforms.map((platform) => platform.cliName).toList(),
      'issueCount': issueCount,
      'checks': checks.map((check) => check.toJson()).toList(),
      if (includeNextAction) 'state': ok ? 'ready' : 'blocked',
      if (includeNextAction) 'nextAction': _nextAction(),
    };
  }

  Map<String, Object?> _nextAction() {
    if (ok) {
      return {
        'type': 'ready',
        'phase': 'doctor',
        'message': 'Doctor strict checks passed.',
      };
    }
    return {
      'type': 'blocked',
      'phase': 'doctor',
      'reason': 'doctor_warnings',
      'message':
          'Doctor strict checks reported warnings that require local environment or project repair.',
      'rerunCommand': _rerunCommand(),
      'failingChecks': [
        for (final check in checks)
          if (check.status == _DoctorCheckStatus.warning)
            {
              'group': check.group.cliName,
              'id': check.id,
              'title': check.title,
              'details': check.jsonDetails,
              if (check.data.isNotEmpty) 'data': check.data,
            },
      ],
    };
  }

  String _rerunCommand() {
    final parts = ['fluoh doctor'];
    if (!_samePlatforms(platforms, defaultHostFluohPlatforms())) {
      if (platforms.length == 1) {
        parts.add('--platform ${platforms.single.cliName}');
      } else {
        parts.add('--platform all');
      }
    }
    if (includeProject) {
      parts.add('--project');
    }
    parts.add('--json');
    parts.add('--strict');
    return parts.join(' ');
  }
}

bool _samePlatforms(List<FluohPlatform> left, List<FluohPlatform> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

int _issueCount(List<_DoctorCheck> checks) {
  return checks
      .where((check) => check.status == _DoctorCheckStatus.warning)
      .length;
}

List<String> _platformToolSummary(PlatformDoctorReport report) {
  return [for (final check in report.checks) _platformToolPlainDetail(check)];
}

String _ohosToolchainSummaryTitle({String? version}) {
  final suffix = version == null ? '' : ' (OpenHarmony SDK version $version)';
  return '$_ohosToolchainBaseTitle$suffix';
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

String _fluohSummaryTitle() {
  return 'fluoh ($packageVersion, on ${_hostDescription()}, '
      'locale ${Platform.localeName})';
}

String _dartVersion() => Platform.version.split(' ').first;

String _hostDescription() {
  final os = _hostOperatingSystemName();
  final version = normalizeAppleOperatingSystemVersion(
    Platform.operatingSystemVersion,
  );
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
    FluohPlatform.linux => _linuxToolchainBaseTitle,
    FluohPlatform.macos => _macosToolchainBaseTitle,
    FluohPlatform.ohos => _ohosToolchainBaseTitle,
    FluohPlatform.web => _webToolchainBaseTitle,
    FluohPlatform.windows => _windowsToolchainBaseTitle,
  };
  final version = switch (report.platform) {
    FluohPlatform.android =>
      _checkVersion(report, 'android.sdk') ??
          _checkVersion(report, 'android.adb'),
    FluohPlatform.ios => _checkVersion(report, 'ios.xcode'),
    FluohPlatform.linux => _checkVersion(report, 'linux.cmake'),
    FluohPlatform.macos => _checkVersion(report, 'macos.xcode'),
    FluohPlatform.ohos => null,
    FluohPlatform.web => _checkVersion(report, 'web.chrome'),
    FluohPlatform.windows => _checkVersion(report, 'windows.cmake'),
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
    FluohPlatform.linux => 'CMake',
    FluohPlatform.macos => 'Xcode',
    FluohPlatform.ohos => '',
    FluohPlatform.web => 'Chrome',
    FluohPlatform.windows => 'CMake',
  };
  if (report.platform == FluohPlatform.web) {
    return '$title ($version)';
  }
  return '$title ($label $version)';
}

String _appleToolSummaryTitle(List<PlatformDoctorReport> reports) {
  final ios = _reportFor(reports, FluohPlatform.ios);
  final macos = _reportFor(reports, FluohPlatform.macos);
  final version =
      (ios == null ? null : _checkVersion(ios, 'ios.xcode')) ??
      (macos == null ? null : _checkVersion(macos, 'macos.xcode'));
  return version == null
      ? _appleToolchainBaseTitle
      : '$_appleToolchainBaseTitle (Xcode $version)';
}

String _platformToolchainTitle(FluohPlatform platform) {
  return switch (platform) {
    FluohPlatform.android => 'Android toolchain',
    FluohPlatform.ios => 'iOS toolchain',
    FluohPlatform.linux => 'Linux toolchain',
    FluohPlatform.macos => 'macOS toolchain',
    FluohPlatform.ohos => 'OpenHarmony toolchain',
    FluohPlatform.web => _webToolchainBaseTitle,
    FluohPlatform.windows => 'Windows toolchain',
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

PlatformDoctorReport? _reportFor(
  List<PlatformDoctorReport> reports,
  FluohPlatform platform,
) {
  for (final report in reports) {
    if (report.platform == platform) {
      return report;
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
    'macos.host' => _sentence(check.message),
    'macos.xcode' => 'Xcode found',
    'web.build' || 'web.chrome' => _sentence(check.message),
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

String? _normalizeOhosEmulatorVersion(String? value) {
  if (value == null) {
    return null;
  }
  return normalizeOhosEmulatorVersion(value);
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
    FluohPlatform.linux => [
      for (final check in report.checks) _toolDetailLine(check),
    ],
    FluohPlatform.macos => _macosToolDetails(report),
    FluohPlatform.ohos => [
      for (final check in report.checks) _toolDetailLine(check),
    ],
    FluohPlatform.web => _webToolDetails(report),
    FluohPlatform.windows => [
      for (final check in report.checks) _toolDetailLine(check),
    ],
  };
}

List<String> _webToolDetails(PlatformDoctorReport report) {
  final chrome = _checksById(report)['web.chrome'];
  final detail = _webChromeDetailLine(chrome);
  return detail.isEmpty ? const <String>[] : <String>[detail];
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
    details.add('Java binary at: ${java.path}');
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

List<String> _appleToolDetails(List<PlatformDoctorReport> reports) {
  final ios = _reportFor(reports, FluohPlatform.ios);
  final macos = _reportFor(reports, FluohPlatform.macos);
  final iosChecks = ios == null
      ? const <String, PlatformToolCheck>{}
      : _checksById(ios);
  final macosChecks = macos == null
      ? const <String, PlatformToolCheck>{}
      : _checksById(macos);
  final xcode = iosChecks['ios.xcode'] ?? macosChecks['macos.xcode'];
  final xcrun = iosChecks['ios.xcrun'] ?? macosChecks['macos.xcrun'];
  final simctl = iosChecks['ios.simctl'];
  final cocoaPods = iosChecks['ios.cocoapods'];
  final host = macosChecks['macos.host'];
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
  if (host != null && !host.ok) {
    details.add(_toolDetailLine(host));
  }

  return [
    for (final detail in details)
      if (detail.isNotEmpty) detail,
  ];
}

List<String> _macosToolDetails(PlatformDoctorReport report) {
  final checks = _checksById(report);
  final host = checks['macos.host'];
  final xcode = checks['macos.xcode'];
  final xcrun = checks['macos.xcrun'];
  final details = <String>[];

  if (host != null && !host.ok) {
    details.add(_toolDetailLine(host));
  }
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

String _webChromeDetailLine(PlatformToolCheck? check) {
  if (check == null || !check.ok) {
    return _toolDetailLine(check);
  }
  final path = check.path;
  if (path != null) {
    return '${check.label} at $path';
  }
  return _toolDetailLine(check);
}

Map<String, Object?> _platformToolData(PlatformDoctorReport report) {
  return {'checks': report.checks.map((check) => check.toJson()).toList()};
}

String _platformDisplayName(FluohPlatform platform) {
  return switch (platform) {
    FluohPlatform.android => 'Android',
    FluohPlatform.ios => 'iOS',
    FluohPlatform.linux => 'Linux',
    FluohPlatform.macos => 'macOS',
    FluohPlatform.ohos => 'OHOS',
    FluohPlatform.web => 'Web',
    FluohPlatform.windows => 'Windows',
  };
}

List<_TargetDisplayRow> _targetDisplayRows(List<PlatformTarget> targets) {
  return [
    for (final target in targets)
      _TargetDisplayRow(
        name: platformTargetDisplayName(target),
        id: target.id,
        platform: platformTargetDisplayPlatform(target),
        details: platformTargetSummary(target),
      ),
  ];
}

List<String> _formatTargetRows(List<_TargetDisplayRow> rows) {
  if (rows.isEmpty) {
    return const [];
  }
  final nameWidth = rows.map((row) => row.name.length).reduce(_max);
  final idWidth = rows.map((row) => row.id.length).reduce(_max);
  final platformWidth = rows.map((row) => row.platform.length).reduce(_max);
  return [
    for (final row in rows)
      [
        row.name.padRight(nameWidth),
        row.id.padRight(idWidth),
        row.platform.padRight(platformWidth),
        row.details,
      ].where((part) => part.trim().isNotEmpty).join(' • '),
  ];
}

int _max(int left, int right) {
  return left > right ? left : right;
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
  const _DoctorDetail(this.text, {this.status, this.wrap = true});

  const _DoctorDetail.ok(String text, {bool wrap = true})
    : this(text, status: _DoctorCheckStatus.ok, wrap: wrap);

  const _DoctorDetail.warning(String text, {bool wrap = true})
    : this(text, status: _DoctorCheckStatus.warning, wrap: wrap);

  final String text;
  final _DoctorCheckStatus? status;
  final bool wrap;
}

class _GitAvailability {
  const _GitAvailability({required this.ok, required this.detail});

  final bool ok;
  final _DoctorDetail detail;
}

class _TargetDisplayRow {
  const _TargetDisplayRow({
    required this.name,
    required this.id,
    required this.platform,
    required this.details,
  });

  final String name;
  final String id;
  final String platform;
  final String details;

  String get plainText {
    return [
      name,
      id,
      platform,
      details,
    ].where((part) => part.trim().isNotEmpty).join(' • ');
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'id': id,
      'platform': platform,
      if (details.isNotEmpty) 'summary': details,
    };
  }
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

/// Parses pub.dev package metadata into doctor version metadata.
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
