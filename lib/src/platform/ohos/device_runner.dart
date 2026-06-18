import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../task/task_workspace.dart';
import 'ohos_toolchain.dart';
import 'permission_profile.dart';

part 'device_runner_run.dart';
part 'device_runner_emulator.dart';
part 'device_runner_support.dart';

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
    required this.directory,
    required this.deployedRoot,
    required this.imageRoot,
    this.apiVersion,
  });

  /// Emulator display name.
  final String name;

  /// Concrete deployed emulator profile directory.
  final io.Directory directory;

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
  final result = await _runHdc(toolchain, const [
    'list',
    'targets',
  ], timeout: _ohosHdcCommandTimeout(environment.processEnvironment));
  if (_isHdcConnectionFailure(result)) {
    throw OhosDeviceException(
      'List OHOS device targets failed because hdc could not connect to its '
      'server.\n${_trimOutput(result.stdout)}${_trimOutput(result.stderr)}',
      code: 'ohos.hdc_connection_failed',
      details: _hdcFailureDetails(command: 'hdc list targets', result: result),
    );
  }
  if (_isHdcTimeout(result)) {
    throw OhosDeviceException(
      'List OHOS device targets timed out.\n'
      '${_trimOutput(result.stdout)}${_trimOutput(result.stderr)}',
      code: 'ohos.hdc_timeout',
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
