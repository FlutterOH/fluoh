import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import '../platform/ohos/build_profile_signing.dart';
import '../platform/ohos/debug_signer.dart';
import '../platform/ohos/resource_layout.dart';
import 'workflow_result.dart';

/// A platform run preparation session that must be restored after the run.
class PlatformRunPreparation {
  /// Creates a platform run preparation result.
  const PlatformRunPreparation({
    this.steps = const [],
    this.details = const {},
    this.failureStep,
    this.restore,
  });

  /// Workflow steps produced while preparing the platform run.
  final List<WorkflowStepResult> steps;

  /// Extra machine-readable details to attach to the run step.
  final Map<String, Object?> details;

  /// Failure step when preparation blocked the run.
  final WorkflowStepResult? failureStep;

  /// Restores temporary platform state after the run.
  final Future<void> Function()? restore;

  /// Whether preparation completed successfully.
  bool get passed => failureStep == null;

  /// Restores temporary platform state when needed.
  Future<void> restoreIfNeeded() async {
    final restoreCallback = restore;
    if (restoreCallback != null) {
      await restoreCallback();
    }
  }
}

/// Prepares a platform before `flutter run`.
///
/// This is the shared hook for platform-specific signing or device prerequisites.
/// OHOS currently uses it to apply temporary debug signing. iOS real-device
/// signing and Android debug-keystore checks can be added here without changing
/// the run command surface.
Future<PlatformRunPreparation> preparePlatformRun({
  required String platform,
  required FluohEnvironment environment,
  required Directory projectDirectory,
  required String displayPath,
  required TerminalOutput output,
  required String usage,
  required bool autoSign,
  String? doctorNextCommand,
  String? buildNextCommand,
}) async {
  return _platformRunPreparer(platform).prepare(
    environment: environment,
    projectDirectory: projectDirectory,
    displayPath: displayPath,
    output: output,
    usage: usage,
    autoSign: autoSign,
    doctorNextCommand: doctorNextCommand,
    buildNextCommand: buildNextCommand,
  );
}

_PlatformRunPreparer _platformRunPreparer(String platform) {
  return switch (platform) {
    'ohos' => const _OhosRunPreparer(),
    _ => const _NoopRunPreparer(),
  };
}

abstract class _PlatformRunPreparer {
  const _PlatformRunPreparer();

  Future<PlatformRunPreparation> prepare({
    required FluohEnvironment environment,
    required Directory projectDirectory,
    required String displayPath,
    required TerminalOutput output,
    required String usage,
    required bool autoSign,
    String? doctorNextCommand,
    String? buildNextCommand,
  });
}

class _NoopRunPreparer extends _PlatformRunPreparer {
  const _NoopRunPreparer();

  @override
  Future<PlatformRunPreparation> prepare({
    required FluohEnvironment environment,
    required Directory projectDirectory,
    required String displayPath,
    required TerminalOutput output,
    required String usage,
    required bool autoSign,
    String? doctorNextCommand,
    String? buildNextCommand,
  }) async {
    return const PlatformRunPreparation();
  }
}

class _OhosRunPreparer extends _PlatformRunPreparer {
  const _OhosRunPreparer();

  @override
  Future<PlatformRunPreparation> prepare({
    required FluohEnvironment environment,
    required Directory projectDirectory,
    required String displayPath,
    required TerminalOutput output,
    required String usage,
    required bool autoSign,
    String? doctorNextCommand,
    String? buildNextCommand,
  }) async {
    if (!autoSign) {
      return const PlatformRunPreparation();
    }

    final ohosDirectory = Directory('${projectDirectory.path}/ohos');
    final expectedPath = displayPath == '.' ? 'ohos' : '$displayPath/ohos';
    if (!await ohosDirectory.exists()) {
      const reason = 'Missing OHOS project.';
      return PlatformRunPreparation(
        failureStep: _diagnosticStep(
          name: 'ohos-run-preparation',
          path: displayPath,
          command: 'prepare platform run signing',
          code: 'ohos.ohos_project_missing',
          message: reason,
          reason: '$reason Expected $expectedPath.',
          details: {'expectedPath': expectedPath},
          nextCommand: doctorNextCommand,
        ),
      );
    }

    await stabilizeOhosResourceLayout(ohosDirectory);
    output.step('Preparing temporary OHOS debug signing in $displayPath');
    late final OhosDebugSigningMaterial signingMaterial;
    try {
      signingMaterial = await prepareOhosDebugSigning(
        environment: environment,
        ohosDirectory: ohosDirectory,
        output: output,
        usage: usage,
      );
    } on UsageException catch (error) {
      return PlatformRunPreparation(
        failureStep: _diagnosticStep(
          name: 'ohos-run-preparation',
          path: displayPath,
          command: 'prepare platform run signing',
          code: 'ohos.toolchain_missing',
          message: 'Could not locate the local OpenHarmony toolchain.',
          reason: error.message,
          details: {'error': error.message},
          nextCommand: doctorNextCommand,
        ),
      );
    } on Object catch (error) {
      return PlatformRunPreparation(
        failureStep: _diagnosticStep(
          name: 'ohos-run-preparation',
          path: displayPath,
          command: 'prepare platform run signing',
          code: error is OhosSigningException
              ? 'ohos.signing_profile_failed'
              : 'ohos.auto_sign_failed',
          message: 'OHOS automatic debug signing failed.',
          reason: error.toString(),
          details: {'error': error.toString()},
          nextCommand: doctorNextCommand,
        ),
      );
    }

    late final OhosBuildProfileSigningSession signingSession;
    try {
      signingSession = await applyTemporaryOhosSigning(
        ohosDirectory: ohosDirectory,
        config: signingMaterial.signingConfig,
      );
    } on Object catch (error) {
      return PlatformRunPreparation(
        failureStep: _diagnosticStep(
          name: 'ohos-run-preparation',
          path: displayPath,
          command: 'patch platform run signing',
          code: 'ohos.build_profile_patch_failed',
          message: 'Could not patch OHOS build-profile signing.',
          reason: error.toString(),
          details: {
            ..._signingDetails(signingMaterial),
            'error': error.toString(),
          },
          nextCommand: buildNextCommand,
        ),
      );
    }

    final details = {
      'runPreparation': {
        'platform': 'ohos',
        'signingMode': 'build-profile',
        ..._signingDetails(signingMaterial),
      },
    };
    return PlatformRunPreparation(
      steps: [
        WorkflowStepResult(
          name: 'ohos-run-preparation',
          path: displayPath,
          command: 'prepare platform run signing',
          status: 'passed',
          exitCode: 0,
          details: details,
        ),
      ],
      details: details,
      restore: () async {
        await signingSession.restore();
        final profilePath = displayPath == '.'
            ? 'ohos/build-profile.json5'
            : '$displayPath/ohos/build-profile.json5';
        output.detail('Restored $profilePath');
      },
    );
  }
}

WorkflowStepResult _diagnosticStep({
  required String name,
  required String path,
  required String command,
  required String code,
  required String message,
  required String reason,
  required Map<String, Object?> details,
  String? nextCommand,
}) {
  return WorkflowStepResult(
    name: name,
    path: path,
    command: command,
    status: 'failed',
    exitCode: 1,
    reason: reason,
    diagnostics: [
      WorkflowDiagnostic(
        code: code,
        message: message,
        details: details,
        nextCommand: nextCommand,
      ),
    ],
  );
}

Map<String, Object?> _signingDetails(OhosDebugSigningMaterial signingMaterial) {
  final profile = signingMaterial.permissionProfile;
  return {
    'bundleName': profile.bundleName,
    'permissionCount': profile.requestedPermissions.length,
    if (profile.restrictedPermissions.isNotEmpty)
      'restrictedPermissions': profile.restrictedPermissions,
    'signingConfig': signingMaterial.signingConfig.name,
    'profile': signingMaterial.signingConfig.profile,
    'signingDirectory': signingMaterial.directory.path,
  };
}
