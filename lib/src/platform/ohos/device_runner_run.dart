part of 'device_runner.dart';

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
        : 'Multiple OHOS device targets are connected; pass --device-id with one '
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
  final hdcTimeout = _ohosHdcCommandTimeout(environment.processEnvironment);
  final install = await _runHdc(
    toolchain,
    installArguments,
    timeout: hdcTimeout,
  );
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
  final launch = await _runHdc(toolchain, launchArguments, timeout: hdcTimeout);

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
