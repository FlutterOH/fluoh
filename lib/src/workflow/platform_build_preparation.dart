import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import '../platform/ohos/build_profile_signing.dart';
import '../platform/ohos/debug_signer.dart';
import '../platform/ohos/resource_layout.dart';
import '../sdk/flutter_runner.dart';
import 'workflow_result.dart';

/// Platform-specific preparation for `flutter build`.
class PlatformBuildPreparation {
  const PlatformBuildPreparation._({
    this.steps = const [],
    this.failureStep,
    required _PlatformBuildPreparationDelegate delegate,
  }) : _delegate = delegate;

  /// Workflow steps produced while preparing the platform build.
  final List<WorkflowStepResult> steps;

  /// Failure step when preparation blocked the build.
  final WorkflowStepResult? failureStep;

  final _PlatformBuildPreparationDelegate _delegate;

  /// Whether preparation completed successfully.
  bool get passed => failureStep == null;

  /// Attempts platform-specific recovery after a failed build.
  Future<PlatformBuildRecovery> recoverFailedBuild({
    required SelectedToolResult buildResult,
    required DateTime modifiedAfter,
  }) {
    return _delegate.recoverFailedBuild(
      buildResult: buildResult,
      modifiedAfter: modifiedAfter,
    );
  }

  /// Collects platform-specific artifacts after a successful build.
  Future<PlatformBuildArtifacts> collectSuccessfulBuildArtifacts({
    required DateTime modifiedAfter,
  }) {
    return _delegate.collectSuccessfulBuildArtifacts(
      modifiedAfter: modifiedAfter,
    );
  }

  /// Restores temporary platform state when needed.
  Future<void> restoreIfNeeded() => _delegate.restoreIfNeeded();
}

/// Platform-specific build recovery result.
class PlatformBuildRecovery {
  /// Creates a platform build recovery result.
  const PlatformBuildRecovery({
    this.steps = const [],
    this.failureStep,
    this.artifactPaths = const [],
    this.signingMode,
  });

  /// Workflow steps produced by recovery.
  final List<WorkflowStepResult> steps;

  /// Failure step when recovery failed.
  final WorkflowStepResult? failureStep;

  /// Installable artifacts produced by recovery.
  final List<String> artifactPaths;

  /// Effective signing mode when recovery changed it.
  final String? signingMode;

  /// Whether recovery made a failed build usable.
  bool get recovered => failureStep == null && artifactPaths.isNotEmpty;
}

/// Platform-specific build artifacts.
class PlatformBuildArtifacts {
  /// Creates a platform build artifact result.
  const PlatformBuildArtifacts({this.artifactPaths = const []});

  /// Installable artifacts produced by the build.
  final List<String> artifactPaths;
}

/// Prepares a platform before `flutter build`.
Future<PlatformBuildPreparation> preparePlatformBuild({
  required String platform,
  required FluohEnvironment environment,
  required Directory projectDirectory,
  required String displayPath,
  required String displayLabel,
  required TerminalOutput output,
  required String usage,
  required bool autoSign,
  required String? Function(String code) nextCommandForDiagnostic,
}) {
  return _platformBuildPreparer(platform).prepare(
    environment: environment,
    projectDirectory: projectDirectory,
    displayPath: displayPath,
    displayLabel: displayLabel,
    output: output,
    usage: usage,
    autoSign: autoSign,
    nextCommandForDiagnostic: nextCommandForDiagnostic,
  );
}

_PlatformBuildPreparer _platformBuildPreparer(String platform) {
  return switch (platform) {
    'ohos' => const _OhosBuildPreparer(),
    _ => const _NoopBuildPreparer(),
  };
}

abstract class _PlatformBuildPreparer {
  const _PlatformBuildPreparer();

  Future<PlatformBuildPreparation> prepare({
    required FluohEnvironment environment,
    required Directory projectDirectory,
    required String displayPath,
    required String displayLabel,
    required TerminalOutput output,
    required String usage,
    required bool autoSign,
    required String? Function(String code) nextCommandForDiagnostic,
  });
}

abstract class _PlatformBuildPreparationDelegate {
  const _PlatformBuildPreparationDelegate();

  Future<PlatformBuildRecovery> recoverFailedBuild({
    required SelectedToolResult buildResult,
    required DateTime modifiedAfter,
  });

  Future<PlatformBuildArtifacts> collectSuccessfulBuildArtifacts({
    required DateTime modifiedAfter,
  });

  Future<void> restoreIfNeeded();
}

class _NoopBuildPreparer extends _PlatformBuildPreparer {
  const _NoopBuildPreparer();

  @override
  Future<PlatformBuildPreparation> prepare({
    required FluohEnvironment environment,
    required Directory projectDirectory,
    required String displayPath,
    required String displayLabel,
    required TerminalOutput output,
    required String usage,
    required bool autoSign,
    required String? Function(String code) nextCommandForDiagnostic,
  }) async {
    return const PlatformBuildPreparation._(
      delegate: _NoopBuildPreparationDelegate(),
    );
  }
}

class _NoopBuildPreparationDelegate extends _PlatformBuildPreparationDelegate {
  const _NoopBuildPreparationDelegate();

  @override
  Future<PlatformBuildRecovery> recoverFailedBuild({
    required SelectedToolResult buildResult,
    required DateTime modifiedAfter,
  }) async {
    return const PlatformBuildRecovery();
  }

  @override
  Future<PlatformBuildArtifacts> collectSuccessfulBuildArtifacts({
    required DateTime modifiedAfter,
  }) async {
    return const PlatformBuildArtifacts();
  }

  @override
  Future<void> restoreIfNeeded() async {}
}

class _OhosBuildPreparer extends _PlatformBuildPreparer {
  const _OhosBuildPreparer();

  @override
  Future<PlatformBuildPreparation> prepare({
    required FluohEnvironment environment,
    required Directory projectDirectory,
    required String displayPath,
    required String displayLabel,
    required TerminalOutput output,
    required String usage,
    required bool autoSign,
    required String? Function(String code) nextCommandForDiagnostic,
  }) async {
    final ohosDirectory = Directory('${projectDirectory.path}/ohos');
    await stabilizeOhosResourceLayout(ohosDirectory);

    if (!autoSign) {
      return PlatformBuildPreparation._(
        delegate: _OhosBuildPreparationDelegate(
          environment: environment,
          projectDirectory: projectDirectory,
          ohosDirectory: ohosDirectory,
          displayPath: displayPath,
          displayLabel: displayLabel,
          output: output,
          usage: usage,
          nextCommandForDiagnostic: nextCommandForDiagnostic,
        ),
      );
    }

    final expectedPath = displayPath == '.' ? 'ohos' : '$displayPath/ohos';
    if (!await ohosDirectory.exists()) {
      final reason = displayPath == '.'
          ? 'Missing OHOS project.'
          : 'Missing OHOS example project.';
      return PlatformBuildPreparation._(
        failureStep: _diagnosticStep(
          name: 'ohos-auto-sign',
          path: displayPath,
          command: 'prepare OHOS debug signing',
          code: 'ohos.ohos_project_missing',
          message: reason,
          reason: '$reason Expected $expectedPath.',
          details: {'expectedPath': expectedPath},
          nextCommand: nextCommandForDiagnostic('ohos.ohos_project_missing'),
        ),
        delegate: const _NoopBuildPreparationDelegate(),
      );
    }

    output.step('Preparing temporary OHOS debug signing in $displayLabel');
    late final OhosDebugSigningMaterial signingMaterial;
    try {
      signingMaterial = await prepareOhosDebugSigning(
        environment: environment,
        ohosDirectory: ohosDirectory,
        output: output,
        usage: usage,
      );
    } on UsageException catch (error) {
      return PlatformBuildPreparation._(
        failureStep: _diagnosticStep(
          name: 'ohos-auto-sign',
          path: displayPath,
          command: 'prepare OHOS debug signing',
          code: 'ohos.toolchain_missing',
          message: 'Could not locate the local OpenHarmony toolchain.',
          reason: error.message,
          details: {'error': error.message},
          nextCommand: nextCommandForDiagnostic('ohos.toolchain_missing'),
        ),
        delegate: const _NoopBuildPreparationDelegate(),
      );
    } on Object catch (error) {
      final code = error is OhosSigningException
          ? 'ohos.signing_profile_failed'
          : 'ohos.auto_sign_failed';
      return PlatformBuildPreparation._(
        failureStep: _diagnosticStep(
          name: 'ohos-auto-sign',
          path: displayPath,
          command: 'prepare OHOS debug signing',
          code: code,
          message: 'OHOS automatic debug signing failed.',
          reason: error.toString(),
          details: {'error': error.toString()},
          nextCommand: nextCommandForDiagnostic(code),
        ),
        delegate: const _NoopBuildPreparationDelegate(),
      );
    }

    late final OhosBuildProfileSigningSession signingSession;
    try {
      signingSession = await applyTemporaryOhosSigning(
        ohosDirectory: ohosDirectory,
        config: signingMaterial.signingConfig,
      );
    } on Object catch (error) {
      return PlatformBuildPreparation._(
        failureStep: _diagnosticStep(
          name: 'ohos-auto-sign',
          path: displayPath,
          command: 'patch OHOS build-profile signing',
          code: 'ohos.build_profile_patch_failed',
          message: 'Could not patch OHOS build-profile signing.',
          reason: error.toString(),
          details: {
            ..._signingDetails(signingMaterial),
            'error': error.toString(),
          },
          nextCommand: nextCommandForDiagnostic(
            'ohos.build_profile_patch_failed',
          ),
        ),
        delegate: const _NoopBuildPreparationDelegate(),
      );
    }

    if (signingMaterial.permissionProfile.restrictedPermissions.isNotEmpty) {
      output.detail(
        'Restricted permissions: '
        '${signingMaterial.permissionProfile.restrictedPermissions.join(', ')}',
      );
    }

    return PlatformBuildPreparation._(
      steps: [
        WorkflowStepResult(
          name: 'ohos-auto-sign',
          path: displayPath,
          command: 'prepare OHOS debug signing',
          status: 'passed',
          exitCode: 0,
          details: _signingDetails(signingMaterial),
        ),
      ],
      delegate: _OhosBuildPreparationDelegate(
        environment: environment,
        projectDirectory: projectDirectory,
        ohosDirectory: ohosDirectory,
        displayPath: displayPath,
        displayLabel: displayLabel,
        output: output,
        usage: usage,
        signingMaterial: signingMaterial,
        signingSession: signingSession,
        nextCommandForDiagnostic: nextCommandForDiagnostic,
      ),
    );
  }
}

class _OhosBuildPreparationDelegate extends _PlatformBuildPreparationDelegate {
  const _OhosBuildPreparationDelegate({
    required this.environment,
    required this.projectDirectory,
    required this.ohosDirectory,
    required this.displayPath,
    required this.displayLabel,
    required this.output,
    required this.usage,
    required this.nextCommandForDiagnostic,
    this.signingMaterial,
    this.signingSession,
  });

  final FluohEnvironment environment;
  final Directory projectDirectory;
  final Directory ohosDirectory;
  final String displayPath;
  final String displayLabel;
  final TerminalOutput output;
  final String usage;
  final OhosDebugSigningMaterial? signingMaterial;
  final OhosBuildProfileSigningSession? signingSession;
  final String? Function(String code) nextCommandForDiagnostic;

  @override
  Future<PlatformBuildRecovery> recoverFailedBuild({
    required SelectedToolResult buildResult,
    required DateTime modifiedAfter,
  }) async {
    final material = signingMaterial;
    if (material == null) {
      return const PlatformBuildRecovery();
    }

    output.step('Signing generated unsigned OHOS HAP in $displayLabel');
    late final List<File> signedHaps;
    try {
      signedHaps = await signGeneratedUnsignedHaps(
        environment: environment,
        exampleDirectory: projectDirectory,
        signingMaterial: material,
        output: output,
        modifiedAfter: modifiedAfter,
        usage: usage,
      );
    } on Object catch (error) {
      return PlatformBuildRecovery(
        failureStep: _diagnosticStep(
          name: 'ohos-direct-sign',
          path: displayPath,
          command: 'sign generated unsigned OHOS HAP',
          code: 'ohos.direct_sign_failed',
          message: 'Could not directly sign generated unsigned OHOS HAP.',
          reason: error.toString(),
          details: {
            ..._signingDetails(material),
            ..._toolOutputDetails(buildResult),
            'error': error.toString(),
          },
          nextCommand: nextCommandForDiagnostic('ohos.direct_sign_failed'),
        ),
      );
    }
    if (signedHaps.isEmpty) {
      return const PlatformBuildRecovery();
    }

    output.warning(
      'Flutter HAP build failed during Hvigor signing; '
      'fluoh signed the generated unsigned HAP directly.',
    );
    final artifactPaths = _filePaths(signedHaps);
    return PlatformBuildRecovery(
      steps: [
        WorkflowStepResult(
          name: 'ohos-direct-sign',
          path: displayPath,
          command: 'sign generated unsigned OHOS HAP',
          status: 'passed',
          exitCode: 0,
          details: {..._signingDetails(material), 'signedHaps': artifactPaths},
        ),
      ],
      artifactPaths: artifactPaths,
      signingMode: 'direct-sign-fallback',
    );
  }

  @override
  Future<PlatformBuildArtifacts> collectSuccessfulBuildArtifacts({
    required DateTime modifiedAfter,
  }) async {
    await stabilizeOhosResourceLayout(ohosDirectory);
    final haps = await findInstallableOhosHaps(
      exampleDirectory: projectDirectory,
      modifiedAfter: modifiedAfter,
    );
    return PlatformBuildArtifacts(artifactPaths: _filePaths(haps));
  }

  @override
  Future<void> restoreIfNeeded() async {
    final session = signingSession;
    if (session == null) {
      return;
    }
    await session.restore();
    final profilePath = displayPath == '.'
        ? 'ohos/build-profile.json5'
        : '$displayPath/ohos/build-profile.json5';
    output.detail('Restored $profilePath');
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
    'requestedPermissions': profile.requestedPermissions,
    'restrictedPermissions': profile.restrictedPermissions,
    'apl': profile.apl,
    'signingConfig': signingMaterial.signingConfig.name,
    'profile': signingMaterial.signingConfig.profile,
  };
}

Map<String, Object?> _toolOutputDetails(SelectedToolResult result) {
  return {
    if (result.stdout.trim().isNotEmpty) 'stdoutTail': result.stdout,
    if (result.stderr.trim().isNotEmpty) 'stderrTail': result.stderr,
    if (result.combinedOutput.trim().isNotEmpty)
      'outputTail': result.combinedOutput,
  };
}

List<String> _filePaths(List<File> files) {
  return [for (final file in files) file.path];
}
