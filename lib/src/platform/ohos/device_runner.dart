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
    this.apiVersion,
  });

  /// Emulator display name.
  final String name;

  /// Deployed emulator root directory.
  final io.Directory deployedRoot;

  /// Emulator image root directory.
  final io.Directory imageRoot;

  /// OpenHarmony API version when it can be inferred from DevEco metadata.
  final int? apiVersion;
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
  if (_isHdcConnectionFailure(result)) {
    throw OhosDeviceException(
      'List OHOS device targets failed because hdc could not connect to its '
      'server.\n${_trimOutput(result.stdout)}${_trimOutput(result.stderr)}',
      code: 'ohos.hdc_connection_failed',
      details: _hdcFailureDetails(command: 'hdc list targets', result: result),
    );
  }
  if (result.exitCode != 0) {
    throw OhosDeviceException(
      'List OHOS device targets failed with exit code ${result.exitCode}.\n'
      '${_trimOutput(result.stdout)}${_trimOutput(result.stderr)}',
      details: _hdcFailureDetails(command: 'hdc list targets', result: result),
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
  } on OhosDeviceException catch (error) {
    return OhosDeviceRunResult(
      exitCode: 1,
      targetId: null,
      launchInfo: launchInfo,
      logFile: null,
      findings: const [],
      diagnostics: [
        OhosDeviceDiagnostic(
          code: error.code ?? 'ohos.hdc_targets_failed',
          message: 'Could not list OHOS device targets with hdc',
          details: {'error': error.message, ...error.details},
        ),
      ],
      reason: error.message,
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
  final requestedDevice = deviceId?.trim();
  var target = requestedDevice != null && requestedDevice.isNotEmpty
      ? _selectTarget(targets, requestedDevice)
      : startEmulator
      ? _selectRunningOhosEmulatorTarget(targets)
      : _selectTarget(targets, null);
  if (target == null && startEmulator && requestedDevice == null) {
    final previousTargetIds = targets.map((target) => target.id).toSet();
    OhosEmulatorStartResult? startResult;
    try {
      startResult = await startOhosEmulator(
        environment: environment,
        toolchain: toolchain,
        emulatorName: emulatorName,
      );
    } on OhosDeviceException catch (error) {
      if (_shouldFallbackToConnectedOhosTarget(
        error: error,
        emulatorName: emulatorName,
        targets: targets,
      )) {
        target = _selectTarget(targets, null);
      } else {
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
              details: {'error': error.toString()},
            ),
          ],
          reason: error.toString(),
        );
      }
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
            details: {'error': error.toString()},
          ),
        ],
        reason: error.toString(),
      );
    }
    if (target == null && startResult != null) {
      output.step('Starting OHOS emulator ${startResult.emulator.name}');
      output.detail(startResult.command.join(' '));
      target = await waitForOhosDeviceTarget(
        environment: environment,
        deviceId: deviceId,
        previousTargetIds: previousTargetIds,
        waitForNewTarget: true,
        timeout: deviceTimeout,
        usage: usage,
      );
    }
  }
  if (target == null) {
    final requested = deviceId?.trim();
    final recommendationDetails = await _ohosTargetRecommendationDetails(
      environment: environment,
      connectedTargets: targets,
    );
    final reason = requested != null && requested.isNotEmpty
        ? 'Requested OHOS device target $requested is not connected. '
              'Connected targets: '
              '${targets.isEmpty ? 'none' : targets.map((item) => item.id).join(', ')}.'
        : targets.isEmpty
        ? 'No OHOS device target is connected. Start a DevEco emulator or '
              'connect a device, then retry. Pass --auto-emulator to let '
              'fluoh choose and start a local DevEco emulator.'
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
            ...recommendationDetails,
          },
        ),
      ],
      reason: reason,
    );
  }

  output.step('Installing ${haps.length} OHOS HAP file(s) on ${target.id}');
  final installArguments = _targeted(target.id, [
    'install',
    '-r',
    ...haps.map((file) => file.path),
  ]);
  final install = await _runHdc(toolchain, installArguments);
  if (_isHdcCommandFailure(install)) {
    final effectiveExitCode = _effectiveHdcExitCode(install);
    return OhosDeviceRunResult(
      exitCode: effectiveExitCode,
      targetId: target.id,
      launchInfo: launchInfo,
      logFile: null,
      findings: const [],
      diagnostics: [
        _hdcFailureDiagnostic(
          defaultCode: 'ohos.install_failed',
          defaultMessage: 'OHOS HAP install failed',
          command: 'hdc ${installArguments.join(' ')}',
          targetId: target.id,
          result: install,
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
    await _runHdcBestEffort(
      toolchain,
      _targeted(target.id, const ['hilog', '-r']),
      workingDirectory: ohosDirectory.path,
      timeout: const Duration(seconds: 2),
    );
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
  final launchArguments = _targeted(target.id, [
    'shell',
    'aa',
    'start',
    '-d',
    '0',
    '-a',
    launchInfo.abilityName,
    '-b',
    launchInfo.bundleName,
  ]);
  final launch = await _runHdc(toolchain, launchArguments);

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
  if (_isHdcCommandFailure(launch)) {
    final effectiveExitCode = _effectiveHdcExitCode(launch);
    return OhosDeviceRunResult(
      exitCode: effectiveExitCode,
      targetId: target.id,
      launchInfo: launchInfo,
      logFile: logFile,
      findings: findings,
      diagnostics: [
        _hdcFailureDiagnostic(
          defaultCode: 'ohos.launch_failed',
          defaultMessage: 'OHOS ability launch failed',
          command: 'hdc ${launchArguments.join(' ')}',
          targetId: target.id,
          result: launch,
          details: {
            'device': target.id,
            'bundleName': launchInfo.bundleName,
            'abilityName': launchInfo.abilityName,
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
          message: 'OHOS runtime error patterns were found in hilog',
          details: {
            'device': target.id,
            'bundleName': launchInfo.bundleName,
            if (logFile != null) 'hilog': logFile.path,
            'findings': findings,
          },
        ),
      ],
      reason: 'OHOS runtime error patterns were found in hilog',
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
  Set<String> previousTargetIds = const {},
  bool waitForNewTarget = false,
  Duration timeout = const Duration(seconds: 90),
  String usage = '',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final targets = await listOhosDeviceTargets(
      environment: environment,
      usage: usage,
    );
    final filteredTargets = waitForNewTarget
        ? [
            for (final target in targets)
              if (!previousTargetIds.contains(target.id)) target,
          ]
        : targets;
    final target = _selectTarget(filteredTargets, deviceId);
    if (target != null) {
      return target;
    }
    if (DateTime.now().isAfter(deadline) || timeout == Duration.zero) {
      return null;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
}

bool _shouldFallbackToConnectedOhosTarget({
  required OhosDeviceException error,
  required String? emulatorName,
  required List<OhosDeviceTarget> targets,
}) {
  final requestedEmulator = emulatorName?.trim();
  return targets.isNotEmpty &&
      (requestedEmulator == null || requestedEmulator.isEmpty) &&
      _isOhosEmulatorUnavailable(error);
}

bool _isOhosEmulatorUnavailable(OhosDeviceException error) {
  return error.message.contains('Could not locate DevEco emulator at') ||
      error.message.contains('No local DevEco emulator is deployed');
}

OhosDeviceTarget? _selectRunningOhosEmulatorTarget(
  List<OhosDeviceTarget> targets,
) {
  final candidates = [
    for (final target in targets)
      if (_isOhosEmulatorTarget(target)) target,
  ]..sort((left, right) => left.id.compareTo(right.id));
  return candidates.isEmpty ? null : candidates.first;
}

bool _isOhosEmulatorTarget(OhosDeviceTarget target) {
  final id = target.id.toLowerCase();
  final details = target.details?.toLowerCase() ?? '';
  return id.startsWith('emulator-') ||
      id.startsWith('127.0.0.1:') ||
      id.startsWith('localhost:') ||
      id.contains('emulator') ||
      details.contains('emulator');
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
      ? _defaultOhosEmulator(emulators)
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
        final emulatorDirectory = _emulatorDirectoryFromListItem(
          deployedRoot: deployedRoot,
          name: name,
          item: item,
        );
        emulators.add(
          OhosLocalEmulator(
            name: name,
            deployedRoot: deployedRoot,
            imageRoot: imageRoot,
            apiVersion:
                _apiVersionFromMap(item) ??
                await _apiVersionFromConfig(emulatorDirectory) ??
                _apiVersionFromName(name),
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
          apiVersion:
              await _apiVersionFromConfig(entity) ??
              _apiVersionFromName(_fileName(entity.path)),
        ),
      );
    }
  }
  emulators.sort((left, right) => left.name.compareTo(right.name));
  return emulators;
}

Future<Map<String, Object?>> _ohosTargetRecommendationDetails({
  required FluohEnvironment environment,
  required List<OhosDeviceTarget> connectedTargets,
}) async {
  final devices = [
    for (final target in connectedTargets)
      {
        'id': target.id,
        if (target.details != null) 'details': target.details,
        'runArguments': '--device ${target.id}',
      },
  ];
  List<OhosLocalEmulator> emulators;
  try {
    emulators = await discoverOhosLocalEmulators(environment: environment);
  } on Object catch (error) {
    return {
      'targetSelection': {
        'policy': 'emulator-first',
        'recommendation':
            'Prefer a local DevEco emulator for repeatable automation. '
            'Emulator discovery failed; run fluoh emulators --platform ohos '
            '--json for details, then fall back to a connected device if '
            'needed.',
        if (devices.isNotEmpty) 'devices': devices,
        'emulatorDiscoveryError': error.toString(),
      },
    };
  }

  if (emulators.isEmpty) {
    return {
      'targetSelection': {
        'policy': 'emulator-first',
        'recommendation': devices.isNotEmpty
            ? 'No local DevEco emulator is available. Use a connected OHOS '
                  'device as a fallback, or create a DevEco emulator and '
                  'rerun with --auto-emulator.'
            : 'No local DevEco emulator or connected OHOS device is available. '
                  'Create a DevEco emulator and rerun with --auto-emulator.',
        'emulators': const [],
        if (devices.isNotEmpty) 'devices': devices,
      },
    };
  }

  final suggested = _suggestedOhosEmulators(emulators);
  return {
    'targetSelection': {
      'policy': 'emulator-first',
      'recommendation': suggested.length > 1
          ? 'Prefer repeatable local DevEco emulator coverage. Run both the '
                'lowest and highest API version emulators for compatibility; '
                'use connected real devices only when no emulator is available.'
          : 'Prefer the available local DevEco emulator for repeatable '
                'automation; use connected real devices only when no emulator '
                'is available.',
      'emulators': emulators.map(_emulatorSuggestionJson).toList(),
      'suggestedEmulators': suggested.map(_emulatorSuggestionJson).toList(),
      'suggestedRunArguments': [
        '--auto-emulator',
        for (final emulator in suggested) '--emulator ${emulator.name}',
      ],
      if (devices.isNotEmpty) 'devices': devices,
    },
  };
}

List<OhosLocalEmulator> _suggestedOhosEmulators(
  List<OhosLocalEmulator> emulators,
) {
  if (emulators.length <= 1) {
    return emulators;
  }
  final withApi =
      [
        for (final emulator in emulators)
          if (emulator.apiVersion != null) emulator,
      ]..sort((left, right) {
        final apiCompare = left.apiVersion!.compareTo(right.apiVersion!);
        return apiCompare != 0 ? apiCompare : left.name.compareTo(right.name);
      });
  if (withApi.length >= 2 &&
      withApi.first.apiVersion != withApi.last.apiVersion) {
    return [withApi.first, withApi.last];
  }
  final sorted = [...emulators]
    ..sort((left, right) => left.name.compareTo(right.name));
  return [sorted.first, sorted.last];
}

OhosLocalEmulator _defaultOhosEmulator(List<OhosLocalEmulator> emulators) {
  final withApi =
      [
        for (final emulator in emulators)
          if (emulator.apiVersion != null) emulator,
      ]..sort((left, right) {
        final apiCompare = right.apiVersion!.compareTo(left.apiVersion!);
        return apiCompare != 0 ? apiCompare : left.name.compareTo(right.name);
      });
  if (withApi.isNotEmpty) {
    return withApi.first;
  }
  final sorted = [...emulators]
    ..sort((left, right) => left.name.compareTo(right.name));
  return sorted.first;
}

Map<String, Object?> _emulatorSuggestionJson(OhosLocalEmulator emulator) {
  return {
    'name': emulator.name,
    if (emulator.apiVersion != null) 'apiVersion': emulator.apiVersion,
    'runArguments': '--emulator ${emulator.name}',
  };
}

io.Directory _emulatorDirectoryFromListItem({
  required io.Directory deployedRoot,
  required String name,
  required Map<Object?, Object?> item,
}) {
  final rawPath = item['path']?.toString().trim();
  if (rawPath != null && rawPath.isNotEmpty) {
    final path = rawPath.startsWith('/')
        ? rawPath
        : '${deployedRoot.path}/$rawPath';
    return io.Directory(path);
  }
  return io.Directory('${deployedRoot.path}/$name');
}

int? _apiVersionFromMap(Map<Object?, Object?> item) {
  for (final key in const [
    'apiVersion',
    'apiLevel',
    'api',
    'sdkApiVersion',
    'sdkVersion',
    'systemApiVersion',
    'systemVersion',
    'version',
  ]) {
    final version = _firstInteger(item[key]);
    if (version != null) {
      return version;
    }
  }
  return null;
}

Future<int?> _apiVersionFromConfig(io.Directory emulatorDirectory) async {
  final config = io.File('${emulatorDirectory.path}/config.ini');
  if (!await config.exists()) {
    return null;
  }
  try {
    final content = await config.readAsString();
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || !line.contains('=')) {
        continue;
      }
      final separator = line.indexOf('=');
      final key = line.substring(0, separator).trim().toLowerCase();
      if (!const {
        'apiversion',
        'apilevel',
        'api',
        'sdkapiversion',
        'sdkversion',
        'systemapiversion',
        'systemversion',
        'version',
      }.contains(key)) {
        continue;
      }
      final version = _firstInteger(line.substring(separator + 1));
      if (version != null) {
        return version;
      }
    }
  } on Object {
    return null;
  }
  return null;
}

int? _apiVersionFromName(String name) {
  final match = RegExp(
    r'(?:api|openharmony|harmonyos)[-_ ]*(\d+)',
    caseSensitive: false,
  ).firstMatch(name);
  return match == null ? null : int.tryParse(match.group(1)!);
}

int? _firstInteger(Object? value) {
  final text = value?.toString();
  if (text == null || text.trim().isEmpty) {
    return null;
  }
  final match = RegExp(r'\d+').firstMatch(text);
  return match == null ? null : int.tryParse(match.group(0)!);
}

/// Returns fatal runtime findings from an OHOS hilog capture.
List<String> classifyOhosRuntimeLog(String log) {
  final findings = <String>[];
  final seen = <String>{};
  final fatalPattern = RegExp(
    r'(FATAL EXCEPTION|Fatal signal|SIGSEGV|SIGABRT|Process crashed|'
    r'app ?crash|CppCrash|MissingPluginException|No implementation found '
    r'for method|MethodChannel#\s*-->\s*method not implemented)',
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
  const OhosDeviceException(this.message, {this.code, this.details = const {}});

  /// User-facing failure message.
  final String message;

  /// Stable diagnostic code when the failure has a known machine meaning.
  final String? code;

  /// Additional machine-readable diagnostic details.
  final Map<String, Object?> details;

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

Future<void> _runHdcBestEffort(
  OhosToolchain toolchain,
  List<String> arguments, {
  required Duration timeout,
  String? workingDirectory,
}) async {
  io.Process? process;
  final drains = <Future<void>>[];
  try {
    process = await io.Process.start(
      toolchain.hdc.path,
      arguments,
      workingDirectory: workingDirectory,
    );
    drains
      ..add(process.stdout.drain<void>())
      ..add(process.stderr.drain<void>());
    await process.exitCode.timeout(timeout);
  } on TimeoutException {
    process?.kill();
  } on Object {
    process?.kill();
  } finally {
    try {
      await Future.wait(drains).timeout(const Duration(seconds: 1));
    } on Object {
      process?.kill();
    }
  }
}

bool _isHdcCommandFailure(OhosHdcResult result) {
  return result.exitCode != 0 ||
      _isHdcConnectionFailure(result) ||
      _isHdcTargetUnavailable(result);
}

int _effectiveHdcExitCode(OhosHdcResult result) {
  return result.exitCode == 0 && _isHdcCommandFailure(result)
      ? 1
      : result.exitCode;
}

bool _isHdcConnectionFailure(OhosHdcResult result) {
  return _containsHdcOutputFragment(result, const [
    'connect server failed',
    'failed to connect hdc server',
    'failed to connect to hdc server',
    'connect hdc server failed',
  ]);
}

bool _isHdcTargetUnavailable(OhosHdcResult result) {
  return _containsHdcOutputFragment(result, const [
    'not match target founded',
    'not match target found',
    'target offline',
    'device offline',
  ]);
}

bool _containsHdcOutputFragment(OhosHdcResult result, List<String> fragments) {
  final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
  return fragments.any(output.contains);
}

OhosDeviceDiagnostic _hdcFailureDiagnostic({
  required String defaultCode,
  required String defaultMessage,
  required String command,
  required String targetId,
  required OhosHdcResult result,
  Map<String, Object?> details = const {},
}) {
  final code = _isHdcConnectionFailure(result)
      ? 'ohos.hdc_connection_failed'
      : _isHdcTargetUnavailable(result)
      ? 'ohos.hdc_target_unavailable'
      : defaultCode;
  final message = switch (code) {
    'ohos.hdc_connection_failed' => 'OHOS hdc connection failed',
    'ohos.hdc_target_unavailable' => 'OHOS hdc target became unavailable',
    _ => defaultMessage,
  };
  return OhosDeviceDiagnostic(
    code: code,
    message: message,
    details: {
      ...details,
      ..._hdcFailureDetails(
        command: command,
        result: result,
        targetId: targetId,
      ),
    },
  );
}

Map<String, Object?> _hdcFailureDetails({
  required String command,
  required OhosHdcResult result,
  String? targetId,
}) {
  final effectiveExitCode = _effectiveHdcExitCode(result);
  return {
    'command': command,
    'targetId': ?targetId,
    'exitCode': effectiveExitCode,
    if (effectiveExitCode != result.exitCode) 'rawExitCode': result.exitCode,
    if (result.stdout.trim().isNotEmpty) 'stdout': result.stdout,
    if (result.stderr.trim().isNotEmpty) 'stderr': result.stderr,
  };
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
    '${environment.packageRunsDirectory.path}/'
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
