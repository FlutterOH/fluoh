import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import 'ohos_toolchain.dart';
import 'permission_profile.dart';

/// Launch metadata read from OHOS app manifests.
class OhosLaunchInfo {
  /// Creates OHOS launch metadata.
  const OhosLaunchInfo({
    required this.bundleName,
    required this.moduleName,
    required this.abilityName,
  });

  /// Application bundle name.
  final String bundleName;

  /// Module name containing the launch ability.
  final String moduleName;

  /// Ability name used by `hdc shell aa start`.
  final String abilityName;
}

/// Connected OHOS target reported by `hdc list targets`.
class OhosDeviceTarget {
  /// Creates a device target descriptor.
  const OhosDeviceTarget({required this.id, this.details});

  /// hdc target id.
  final String id;

  /// Optional hdc details after the target id.
  final String? details;
}

/// Local OpenHarmony emulator discovered from the SDK installation.
class OhosLocalEmulator {
  /// Creates a local emulator descriptor.
  const OhosLocalEmulator({
    required this.name,
    required this.deployedRoot,
    required this.imageRoot,
  });

  /// Emulator display name.
  final String name;

  /// Deployed emulator root directory.
  final io.Directory deployedRoot;

  /// Emulator image root directory.
  final io.Directory imageRoot;
}

/// Result of starting a local OpenHarmony emulator.
class OhosEmulatorStartResult {
  /// Creates an emulator start result.
  const OhosEmulatorStartResult({
    required this.emulator,
    required this.command,
  });

  /// Emulator that was started.
  final OhosLocalEmulator emulator;

  /// Command used to start the emulator.
  final List<String> command;
}

/// Result of installing and launching OHOS HAPs on a target.
class OhosDeviceRunResult {
  /// Creates an OHOS device run result.
  const OhosDeviceRunResult({
    required this.exitCode,
    required this.targetId,
    required this.launchInfo,
    required this.logFile,
    required this.findings,
    required this.diagnostics,
    this.reason,
  });

  /// Exit code for the run operation.
  final int exitCode;

  /// Selected hdc target id.
  final String? targetId;

  /// Launch metadata used for the app start command.
  final OhosLaunchInfo? launchInfo;

  /// Captured hilog file.
  final io.File? logFile;

  /// Human-readable findings from the run.
  final List<String> findings;

  /// Structured diagnostics from install, launch, or runtime checks.
  final List<OhosDeviceDiagnostic> diagnostics;

  /// Optional high-level failure reason.
  final String? reason;

  /// Whether the run completed successfully.
  bool get passed => exitCode == 0;
}

/// Structured OHOS device run diagnostic.
class OhosDeviceDiagnostic {
  /// Creates a device diagnostic.
  const OhosDeviceDiagnostic({
    required this.code,
    required this.message,
    this.severity = 'error',
    this.details = const {},
  });

  /// Stable diagnostic code.
  final String code;

  /// Human-readable diagnostic message.
  final String message;

  /// Diagnostic severity.
  final String severity;

  /// Additional machine-readable diagnostic details.
  final Map<String, Object?> details;

  /// Converts the diagnostic to JSON.
  Map<String, Object?> toJson() {
    return {
      'code': code,
      'severity': severity,
      'message': message,
      if (details.isNotEmpty) 'details': details,
    };
  }
}

/// Captured `hdc` command result.
class OhosHdcResult {
  /// Creates an hdc result.
  const OhosHdcResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// hdc exit code.
  final int exitCode;

  /// Captured stdout.
  final String stdout;

  /// Captured stderr.
  final String stderr;
}

/// Reads launch metadata from an OHOS project directory.
Future<OhosLaunchInfo> readOhosLaunchInfo(io.Directory ohosDirectory) async {
  final bundleName = await readOhosBundleName(ohosDirectory);
  final moduleFiles = await _moduleJsonFiles(ohosDirectory);
  for (final moduleFile in moduleFiles) {
    final content = await moduleFile.readAsString();
    final moduleName = _firstStringValue(content, 'name') ?? 'entry';
    final abilityName =
        _firstStringValue(content, 'mainElement') ?? _firstAbilityName(content);
    if (abilityName == null || abilityName.trim().isEmpty) {
      continue;
    }
    return OhosLaunchInfo(
      bundleName: bundleName,
      moduleName: moduleName,
      abilityName: abilityName,
    );
  }
  throw const FormatException('Missing launchable OHOS ability.');
}

/// Lists connected OHOS hdc targets.
Future<List<OhosDeviceTarget>> listOhosDeviceTargets({
  required FluohEnvironment environment,
  String usage = '',
}) async {
  final toolchain = await locateOhosToolchain(
    environment: environment.processEnvironment,
    usage: usage,
  );
  final result = await _runHdc(toolchain, const ['list', 'targets']);
  if (result.exitCode != 0) {
    throw OhosDeviceException(
      'List OHOS device targets failed with exit code ${result.exitCode}.\n'
      '${_trimOutput(result.stdout)}${_trimOutput(result.stderr)}',
    );
  }
  return parseOhosDeviceTargets(result.stdout);
}

/// Parses `hdc list targets` output.
List<OhosDeviceTarget> parseOhosDeviceTargets(String output) {
  final targets = <OhosDeviceTarget>[];
  for (final rawLine in const LineSplitter().convert(output)) {
    final line = rawLine.trim();
    if (line.isEmpty || line == '[Empty]') {
      continue;
    }
    final parts = line.split(RegExp(r'\s+'));
    final id = parts.first.trim();
    if (id.isEmpty || id.startsWith('[')) {
      continue;
    }
    targets.add(
      OhosDeviceTarget(
        id: id,
        details: parts.length > 1 ? parts.skip(1).join(' ') : null,
      ),
    );
  }
  return targets;
}

/// Installs and launches signed HAPs on an OHOS device or emulator.
Future<OhosDeviceRunResult> runOhosHapsOnDevice({
  required FluohEnvironment environment,
  required io.Directory ohosDirectory,
  required List<io.File> haps,
  required TerminalOutput output,
  String? deviceId,
  bool startEmulator = false,
  String? emulatorName,
  Duration deviceTimeout = const Duration(seconds: 90),
  Duration logDuration = const Duration(seconds: 8),
  String usage = '',
}) async {
  if (haps.isEmpty) {
    return const OhosDeviceRunResult(
      exitCode: 1,
      targetId: null,
      launchInfo: null,
      logFile: null,
      findings: [],
      diagnostics: [
        OhosDeviceDiagnostic(
          code: 'ohos.no_installable_hap',
          message: 'No signed OHOS HAP was found to install',
        ),
      ],
      reason: 'No signed OHOS HAP was found to install',
    );
  }

  late OhosToolchain toolchain;
  try {
    toolchain = await locateOhosToolchain(
      environment: environment.processEnvironment,
      usage: usage,
    );
  } on Object catch (error) {
    return OhosDeviceRunResult(
      exitCode: 1,
      targetId: null,
      launchInfo: null,
      logFile: null,
      findings: const [],
      diagnostics: [
        OhosDeviceDiagnostic(
          code: 'ohos.toolchain_missing',
          message: 'Could not locate the local OpenHarmony toolchain',
          details: {'error': error.toString()},
        ),
      ],
      reason: error.toString(),
    );
  }

  late OhosLaunchInfo launchInfo;
  try {
    launchInfo = await readOhosLaunchInfo(ohosDirectory);
  } on Object catch (error) {
    return OhosDeviceRunResult(
      exitCode: 1,
      targetId: null,
      launchInfo: null,
      logFile: null,
      findings: const [],
      diagnostics: [
        OhosDeviceDiagnostic(
          code: 'ohos.launch_info_missing',
          message: 'Could not read the OHOS launch ability',
          details: {'error': error.toString()},
        ),
      ],
      reason: error.toString(),
    );
  }

  late List<OhosDeviceTarget> targets;
  try {
    targets = await listOhosDeviceTargets(
      environment: environment,
      usage: usage,
    );
  } on Object catch (error) {
    return OhosDeviceRunResult(
      exitCode: 1,
      targetId: null,
      launchInfo: launchInfo,
      logFile: null,
      findings: const [],
      diagnostics: [
        OhosDeviceDiagnostic(
          code: 'ohos.hdc_targets_failed',
          message: 'Could not list OHOS device targets with hdc',
          details: {'error': error.toString()},
        ),
      ],
      reason: error.toString(),
    );
  }
  var target = _selectTarget(targets, deviceId);
  if (target == null && startEmulator && targets.isEmpty) {
    late OhosEmulatorStartResult startResult;
    try {
      startResult = await startOhosEmulator(
        environment: environment,
        toolchain: toolchain,
        emulatorName: emulatorName,
      );
    } on Object catch (error) {
      return OhosDeviceRunResult(
        exitCode: 1,
        targetId: null,
        launchInfo: launchInfo,
        logFile: null,
        findings: const [],
        diagnostics: [
          OhosDeviceDiagnostic(
            code: 'ohos.emulator_start_failed',
            message: 'Could not start a local DevEco emulator',
          ),
        ],
        reason: error.toString(),
      );
    }
    output.step('Starting OHOS emulator ${startResult.emulator.name}');
    output.detail(startResult.command.join(' '));
    target = await waitForOhosDeviceTarget(
      environment: environment,
      deviceId: deviceId,
      timeout: deviceTimeout,
      usage: usage,
    );
  }
  if (target == null) {
    final requested = deviceId?.trim();
    final reason = requested != null && requested.isNotEmpty
        ? 'Requested OHOS device target $requested is not connected. '
              'Connected targets: '
              '${targets.isEmpty ? 'none' : targets.map((item) => item.id).join(', ')}.'
        : targets.isEmpty
        ? 'No OHOS device target is connected. Start a DevEco emulator or '
              'connect a device, then retry. Pass --emulator to let fluoh '
              'start a local DevEco emulator.'
        : 'Multiple OHOS device targets are connected; pass --device with one '
              'of: ${targets.map((item) => item.id).join(', ')}.';
    return OhosDeviceRunResult(
      exitCode: 1,
      targetId: null,
      launchInfo: launchInfo,
      logFile: null,
      findings: const [],
      diagnostics: [
        OhosDeviceDiagnostic(
          code: requested != null && requested.isNotEmpty
              ? 'ohos.device_not_found'
              : targets.isEmpty
              ? 'ohos.device_missing'
              : 'ohos.device_ambiguous',
          message: reason,
          details: {
            if (requested != null && requested.isNotEmpty)
              'requestedDevice': requested,
            'connectedDevices': targets.map((target) => target.id).toList(),
          },
        ),
      ],
      reason: reason,
    );
  }

  output.step('Installing ${haps.length} OHOS HAP file(s) on ${target.id}');
  final install = await _runHdc(
    toolchain,
    _targeted(target.id, ['install', '-r', ...haps.map((file) => file.path)]),
  );
  if (install.exitCode != 0) {
    return OhosDeviceRunResult(
      exitCode: install.exitCode,
      targetId: target.id,
      launchInfo: launchInfo,
      logFile: null,
      findings: const [],
      diagnostics: [
        OhosDeviceDiagnostic(
          code: 'ohos.install_failed',
          message: 'OHOS HAP install failed',
          details: {
            'device': target.id,
            'exitCode': install.exitCode,
            if (install.stdout.trim().isNotEmpty) 'stdout': install.stdout,
            if (install.stderr.trim().isNotEmpty) 'stderr': install.stderr,
          },
        ),
      ],
      reason:
          'OHOS HAP install failed\n'
          '${_trimOutput(install.stdout)}${_trimOutput(install.stderr)}',
    );
  }

  final logBuffer = StringBuffer();
  io.Process? logProcess;
  Future<int>? logExitCode;
  final logStreamDrains = <Future<void>>[];
  if (logDuration > Duration.zero) {
    logProcess = await io.Process.start(
      toolchain.hdc.path,
      _targeted(target.id, const ['hilog']),
      workingDirectory: ohosDirectory.path,
    );
    logExitCode = logProcess.exitCode;
    logStreamDrains.add(
      logProcess.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(logBuffer.write)
          .asFuture<void>(),
    );
    logStreamDrains.add(
      logProcess.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(logBuffer.write)
          .asFuture<void>(),
    );
  }

  output.step(
    'Launching ${launchInfo.bundleName}/${launchInfo.abilityName} on '
    '${target.id}',
  );
  final launch = await _runHdc(
    toolchain,
    _targeted(target.id, [
      'shell',
      'aa',
      'start',
      '-d',
      '0',
      '-a',
      launchInfo.abilityName,
      '-b',
      launchInfo.bundleName,
    ]),
  );

  if (logDuration > Duration.zero) {
    await Future<void>.delayed(logDuration);
    await _stopLogProcess(logProcess, logExitCode);
    await _drainLogStreams(logStreamDrains);
  }

  final logFile = logDuration > Duration.zero
      ? await _writeHilog(
          environment: environment,
          launchInfo: launchInfo,
          content: logBuffer.toString(),
        )
      : null;
  final findings = classifyOhosRuntimeLog(logBuffer.toString());
  if (launch.exitCode != 0) {
    return OhosDeviceRunResult(
      exitCode: launch.exitCode,
      targetId: target.id,
      launchInfo: launchInfo,
      logFile: logFile,
      findings: findings,
      diagnostics: [
        OhosDeviceDiagnostic(
          code: 'ohos.launch_failed',
          message: 'OHOS ability launch failed',
          details: {
            'device': target.id,
            'bundleName': launchInfo.bundleName,
            'abilityName': launchInfo.abilityName,
            'exitCode': launch.exitCode,
            if (launch.stdout.trim().isNotEmpty) 'stdout': launch.stdout,
            if (launch.stderr.trim().isNotEmpty) 'stderr': launch.stderr,
            if (logFile != null) 'hilog': logFile.path,
          },
        ),
      ],
      reason:
          'OHOS ability launch failed\n'
          '${_trimOutput(launch.stdout)}${_trimOutput(launch.stderr)}',
    );
  }
  if (findings.isNotEmpty) {
    return OhosDeviceRunResult(
      exitCode: 1,
      targetId: target.id,
      launchInfo: launchInfo,
      logFile: logFile,
      findings: findings,
      diagnostics: [
        OhosDeviceDiagnostic(
          code: 'ohos.runtime_crash',
          message: 'OHOS runtime crash patterns were found in hilog',
          details: {
            'device': target.id,
            'bundleName': launchInfo.bundleName,
            if (logFile != null) 'hilog': logFile.path,
            'findings': findings,
          },
        ),
      ],
      reason: 'OHOS runtime crash patterns were found in hilog',
    );
  }

  return OhosDeviceRunResult(
    exitCode: 0,
    targetId: target.id,
    launchInfo: launchInfo,
    logFile: logFile,
    findings: findings,
    diagnostics: const [],
  );
}

/// Waits until an OHOS device target is available.
Future<OhosDeviceTarget?> waitForOhosDeviceTarget({
  required FluohEnvironment environment,
  String? deviceId,
  Duration timeout = const Duration(seconds: 90),
  String usage = '',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final targets = await listOhosDeviceTargets(
      environment: environment,
      usage: usage,
    );
    final target = _selectTarget(targets, deviceId);
    if (target != null) {
      return target;
    }
    if (DateTime.now().isAfter(deadline) || timeout == Duration.zero) {
      return null;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
}

/// Starts a local OpenHarmony emulator.
Future<OhosEmulatorStartResult> startOhosEmulator({
  required FluohEnvironment environment,
  required OhosToolchain toolchain,
  String? emulatorName,
}) async {
  if (!await toolchain.emulator.exists()) {
    throw OhosDeviceException(
      'Could not locate DevEco emulator at ${toolchain.emulator.path}',
    );
  }
  final emulators = await discoverOhosLocalEmulators(environment: environment);
  if (emulators.isEmpty) {
    throw const OhosDeviceException(
      'No local DevEco emulator is deployed. Create one in DevEco Studio '
      'Device Manager first.',
    );
  }
  final requested = emulatorName?.trim();
  final emulator = requested == null || requested.isEmpty
      ? emulators.first
      : emulators.where((candidate) => candidate.name == requested).firstOrNull;
  if (emulator == null) {
    throw OhosDeviceException(
      'Local DevEco emulator $requested was not found. Available emulators: '
      '${emulators.map((item) => item.name).join(', ')}',
    );
  }

  final command = [
    toolchain.emulator.path,
    '-hvd',
    emulator.name,
    '-path',
    emulator.deployedRoot.path,
    '-t',
    'trace_${DateTime.now().millisecondsSinceEpoch}_fluoh',
    '-imageRoot',
    emulator.imageRoot.path,
  ];
  await io.Process.start(
    command.first,
    command.skip(1).toList(),
    workingDirectory: toolchain.emulator.parent.path,
    mode: io.ProcessStartMode.detached,
  );
  return OhosEmulatorStartResult(emulator: emulator, command: command);
}

/// Discovers locally deployed OpenHarmony emulators.
Future<List<OhosLocalEmulator>> discoverOhosLocalEmulators({
  required FluohEnvironment environment,
}) async {
  final processEnvironment = environment.processEnvironment;
  final deployedRoot = io.Directory(
    processEnvironment['FLUOH_OHOS_EMULATOR_DEPLOYED']?.trim().isNotEmpty ??
            false
        ? processEnvironment['FLUOH_OHOS_EMULATOR_DEPLOYED']!.trim()
        : '${_userHome(processEnvironment)}/.Huawei/Emulator/deployed',
  );
  final imageRoot = io.Directory(
    processEnvironment['FLUOH_HARMONYOS_SDK_ROOT']?.trim().isNotEmpty ?? false
        ? processEnvironment['FLUOH_HARMONYOS_SDK_ROOT']!.trim()
        : '${_userHome(processEnvironment)}/Library/Huawei/Sdk',
  );
  final listFile = io.File('${deployedRoot.path}/lists.json');
  if (await listFile.exists()) {
    final decoded = jsonDecode(await listFile.readAsString());
    if (decoded is List) {
      final emulators = <OhosLocalEmulator>[];
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final name = item['name']?.toString().trim();
        if (name == null || name.isEmpty) {
          continue;
        }
        emulators.add(
          OhosLocalEmulator(
            name: name,
            deployedRoot: deployedRoot,
            imageRoot: imageRoot,
          ),
        );
      }
      if (emulators.isNotEmpty) {
        return emulators;
      }
    }
  }

  if (!await deployedRoot.exists()) {
    return const [];
  }
  final emulators = <OhosLocalEmulator>[];
  await for (final entity in deployedRoot.list()) {
    if (entity is io.Directory &&
        await io.File('${entity.path}/config.ini').exists()) {
      emulators.add(
        OhosLocalEmulator(
          name: _fileName(entity.path),
          deployedRoot: deployedRoot,
          imageRoot: imageRoot,
        ),
      );
    }
  }
  emulators.sort((left, right) => left.name.compareTo(right.name));
  return emulators;
}

/// Returns fatal runtime findings from an OHOS hilog capture.
List<String> classifyOhosRuntimeLog(String log) {
  final findings = <String>[];
  final seen = <String>{};
  final fatalPattern = RegExp(
    r'(FATAL EXCEPTION|Fatal signal|SIGSEGV|SIGABRT|Process crashed|'
    r'app ?crash|CppCrash)',
    caseSensitive: false,
  );
  for (final rawLine in const LineSplitter().convert(log)) {
    final line = rawLine.trim();
    if (line.isEmpty || !fatalPattern.hasMatch(line)) {
      continue;
    }
    final finding = line.length <= 500 ? line : line.substring(0, 500);
    if (seen.add(finding)) {
      findings.add(finding);
    }
    if (findings.length >= 20) {
      break;
    }
  }
  return findings;
}

/// Exception thrown for OHOS device and emulator failures.
class OhosDeviceException implements Exception {
  /// Creates an OHOS device exception.
  const OhosDeviceException(this.message);

  /// User-facing failure message.
  final String message;

  @override
  String toString() => message;
}

Future<List<io.File>> _moduleJsonFiles(io.Directory ohosDirectory) async {
  final mainFiles = <io.File>[];
  final fallbackFiles = <io.File>[];
  await for (final entity in ohosDirectory.list(recursive: true)) {
    if (entity is! io.File || !entity.path.endsWith('/module.json5')) {
      continue;
    }
    final normalized = entity.path.replaceAll('\\', '/');
    if (normalized.contains('/ohosTest/')) {
      continue;
    }
    if (normalized.endsWith('/src/main/module.json5')) {
      mainFiles.add(entity);
    } else {
      fallbackFiles.add(entity);
    }
  }
  mainFiles.sort((left, right) => left.path.compareTo(right.path));
  fallbackFiles.sort((left, right) => left.path.compareTo(right.path));
  return [...mainFiles, ...fallbackFiles];
}

String? _firstStringValue(String content, String key) {
  return RegExp(
    '"${RegExp.escape(key)}"\\s*:\\s*"([^"]+)"',
  ).firstMatch(content)?.group(1);
}

String? _firstAbilityName(String content) {
  final key = RegExp(r'"abilities"\s*:').firstMatch(content);
  if (key == null) {
    return null;
  }
  final start = content.indexOf('[', key.end);
  if (start < 0) {
    return null;
  }
  final end = _matchingBracket(content, start, '[', ']');
  if (end < 0) {
    return null;
  }
  return _firstStringValue(content.substring(start, end + 1), 'name');
}

int _matchingBracket(String text, int start, String open, String close) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var index = start; index < text.length; index += 1) {
    final char = text[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }
    if (char == '"') {
      inString = true;
    } else if (char == open) {
      depth += 1;
    } else if (char == close) {
      depth -= 1;
      if (depth == 0) {
        return index;
      }
    }
  }
  return -1;
}

OhosDeviceTarget? _selectTarget(
  List<OhosDeviceTarget> targets,
  String? requestedId,
) {
  if (requestedId != null && requestedId.trim().isNotEmpty) {
    for (final target in targets) {
      if (target.id == requestedId) {
        return target;
      }
    }
    return null;
  }
  return targets.length == 1 ? targets.single : null;
}

List<String> _targeted(String targetId, List<String> arguments) {
  return ['-t', targetId, ...arguments];
}

Future<OhosHdcResult> _runHdc(
  OhosToolchain toolchain,
  List<String> arguments,
) async {
  final result = await io.Process.run(toolchain.hdc.path, arguments);
  return OhosHdcResult(
    exitCode: result.exitCode,
    stdout: result.stdout.toString(),
    stderr: result.stderr.toString(),
  );
}

Future<void> _stopLogProcess(io.Process? process, Future<int>? exitCode) async {
  if (process == null || exitCode == null) {
    return;
  }
  process.kill(io.ProcessSignal.sigint);
  try {
    await exitCode.timeout(const Duration(seconds: 2));
  } on TimeoutException {
    process.kill(io.ProcessSignal.sigkill);
    await exitCode.timeout(const Duration(seconds: 2), onTimeout: () => -1);
  }
}

Future<void> _drainLogStreams(List<Future<void>> streams) async {
  try {
    await Future.wait<void>(
      streams,
    ).timeout(const Duration(seconds: 2), onTimeout: () => const []);
  } on Object {
    // Hilog capture is diagnostic only; keep the device run result authoritative.
  }
}

Future<io.File> _writeHilog({
  required FluohEnvironment environment,
  required OhosLaunchInfo launchInfo,
  required String content,
}) async {
  final directory = io.Directory(
    '${environment.homeDirectory.path}/package-runs/'
    '${_safePathSegment(launchInfo.bundleName)}',
  );
  await directory.create(recursive: true);
  final timestamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[^0-9A-Za-z]+'), '-')
      .replaceAll(RegExp(r'-+$'), '');
  final file = io.File('${directory.path}/$timestamp.hilog');
  await file.writeAsString(content);
  return file;
}

String _safePathSegment(String value) {
  final safe = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return safe.isEmpty ? 'app' : safe;
}

String _fileName(String path) {
  return path.replaceAll('\\', '/').split('/').last;
}

String _userHome(Map<String, String> environment) {
  final home = environment['HOME'] ?? environment['USERPROFILE'];
  if (home != null && home.trim().isNotEmpty) {
    return home.trim();
  }
  return io.Platform.environment['HOME'] ??
      io.Platform.environment['USERPROFILE'] ??
      '.';
}

String _trimOutput(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return '';
  }
  const limit = 3000;
  final trimmed = text.length <= limit
      ? text
      : text.substring(text.length - limit);
  return '$trimmed\n';
}
