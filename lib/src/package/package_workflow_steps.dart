part of 'package_workflow_runner.dart';

String _platformForExampleTarget(String target) {
  return switch (target) {
    'hap' => 'ohos',
    'apk' => 'android',
    'ios' => 'ios',
    'macos' => 'macos',
    'linux' => 'linux',
    'web' => 'web',
    'windows' => 'windows',
    _ => throw ArgumentError.value(target, 'target', 'Unsupported target.'),
  };
}

WorkflowStepResult _integrationDiscoveryStep({
  required String name,
  required String path,
  required String packageName,
}) {
  return WorkflowStepResult(
    name: name,
    path: path,
    command: 'flutter test integration_test -d <device>',
    status: 'skipped',
    reason: 'requires a platform run target',
    details: {
      'testDirectory': '$path/integration_test',
      'interactionEvidence': {
        'status': 'available',
        'method': 'integration_test',
        'execution': 'run fluoh run with a concrete platform and device',
      },
      'suggestedCommands': integrationDiscoveryRunCommands(
        packageName: packageName,
      ),
      'manualAssistedFallback': {
        'when':
            'system UI, permissions, pickers, external apps, or platform tooling gaps block automatic execution',
        'requiredEvidence':
            'record user steps plus tool-verified logs, session status, stable text, semantics, or app log markers',
      },
    },
  );
}

WorkflowStepResult _commandStep({
  required String name,
  required String packageName,
  required String path,
  required bool flutter,
  required List<String> arguments,
  required SelectedToolResult result,
  int? effectiveExitCode,
  Map<String, Object?> details = const {},
  String? nextCommand,
  String? traceDir,
}) {
  final exitCode = effectiveExitCode ?? result.exitCode;
  return WorkflowStepResult(
    name: name,
    path: path,
    command: '${flutter ? 'flutter' : 'dart'} ${arguments.join(' ')}',
    status: exitCode == 0 ? 'passed' : 'failed',
    exitCode: exitCode,
    details: {
      ...details,
      if (result.exitCode != exitCode) 'originalExitCode': result.exitCode,
      if (result.exitCode != exitCode) ..._commandOutputDetails(result),
    },
    diagnostics: _diagnosticsForCommandStep(
      name: name,
      flutter: flutter,
      arguments: arguments,
      result: result,
      effectiveExitCode: exitCode,
      packageName: packageName,
      nextCommand: nextCommand,
      traceDir: traceDir,
    ),
  );
}

List<WorkflowDiagnostic> _diagnosticsForCommandStep({
  required String name,
  required bool flutter,
  required List<String> arguments,
  required SelectedToolResult result,
  required int effectiveExitCode,
  required String packageName,
  String? nextCommand,
  String? traceDir,
}) {
  if (effectiveExitCode == 0) {
    return const [];
  }
  final command = '${flutter ? 'flutter' : 'dart'} ${arguments.join(' ')}';
  final sdkConstraint = _dartSdkConstraintFailure(result);
  final isPubGetStep = name == 'package-pub-get' || name == 'example-pub-get';
  final code = switch (name) {
    _ when isPubGetStep && sdkConstraint != null =>
      'dart.sdk_constraint_unsatisfied',
    'package-pub-get' || 'example-pub-get' => 'dart.pub_get_failed',
    'package-analyze' || 'example-analyze' => 'dart.analysis_failed',
    'package-test' || 'example-test' => 'dart.test_failed',
    'example-integration-ohos' => 'ohos.integration_test_failed',
    'example-integration-android' => 'android.integration_test_failed',
    'example-integration-ios' => 'ios.integration_test_failed',
    'example-integration-macos' => 'macos.integration_test_failed',
    'example-integration-linux' => 'linux.integration_test_failed',
    'example-integration-web' => 'web.integration_test_failed',
    'example-integration-windows' => 'windows.integration_test_failed',
    _
        when arguments.length >= 2 &&
            arguments[0] == 'build' &&
            arguments[1] == 'hap' =>
      'ohos.hap_build_failed',
    _
        when arguments.length >= 2 &&
            arguments[0] == 'build' &&
            arguments[1] == 'apk' =>
      'android.apk_build_failed',
    _
        when arguments.length >= 2 &&
            arguments[0] == 'build' &&
            arguments[1] == 'ios' =>
      'ios.build_failed',
    _
        when arguments.length >= 2 &&
            arguments[0] == 'build' &&
            arguments[1] == 'macos' =>
      'macos.build_failed',
    _
        when arguments.length >= 2 &&
            arguments[0] == 'build' &&
            arguments[1] == 'linux' =>
      'linux.build_failed',
    _
        when arguments.length >= 2 &&
            arguments[0] == 'build' &&
            arguments[1] == 'web' =>
      'web.build_failed',
    _
        when arguments.length >= 2 &&
            arguments[0] == 'build' &&
            arguments[1] == 'windows' =>
      'windows.build_failed',
    _ => 'command.failed',
  };
  final message = switch (code) {
    'dart.sdk_constraint_unsatisfied' =>
      'Package SDK constraint is higher than the selected Dart SDK.',
    'dart.pub_get_failed' => 'Dependency resolution failed.',
    'dart.analysis_failed' => 'Static analysis failed.',
    'dart.test_failed' => 'Tests failed.',
    'ohos.integration_test_failed' => 'OHOS integration tests failed.',
    'android.integration_test_failed' => 'Android integration tests failed.',
    'ios.integration_test_failed' => 'iOS integration tests failed.',
    'macos.integration_test_failed' => 'macOS integration tests failed.',
    'linux.integration_test_failed' => 'Linux integration tests failed.',
    'web.integration_test_failed' => 'Web integration tests failed.',
    'windows.integration_test_failed' => 'Windows integration tests failed.',
    'ohos.hap_build_failed' => 'OHOS HAP build failed.',
    'android.apk_build_failed' => 'Android APK build failed.',
    'ios.build_failed' => 'iOS build failed.',
    'macos.build_failed' => 'macOS build failed.',
    'linux.build_failed' => 'Linux build failed.',
    'web.build_failed' => 'Web build failed.',
    'windows.build_failed' => 'Windows build failed.',
    _ => 'Command failed.',
  };
  return [
    WorkflowDiagnostic(
      code: code,
      message: message,
      details: {
        'command': command,
        'exitCode': effectiveExitCode,
        'sdkConstraint': ?sdkConstraint,
        if (code == 'dart.sdk_constraint_unsatisfied')
          'supportPolicy': _lowSdkCompatibilityPolicy(packageName),
        ..._commandOutputDetails(result),
      },
      nextCommand:
          nextCommand ??
          _nextCommandForDiagnosticCode(code, packageName, traceDir: traceDir),
    ),
  ];
}

Map<String, Object?> _lowSdkCompatibilityPolicy(String packageName) {
  return {
    'defaultAction': 'implement-selected-upstream-for-selected-sdk',
    'keepSelectedUpstream': true,
    'adjustPackageForSelectedSdk': true,
    'upstreamDowngradeRequiresApproval': true,
    'suggestedEdits': [
      'Update pubspec.yaml environment.sdk only when the selected Dart SDK can support the package after code changes.',
      'Patch package and example configuration for the selected FlutterOH SDK.',
      'Replace Dart language, SDK API, or dependency usage that requires a newer Dart SDK.',
      'Rerun fluoh verify --package $packageName --json after each compatibility edit.',
    ],
  };
}

String? _suggestedEnvironmentSdkConstraint(String dartVersion) {
  final match = RegExp(r'^(\d+)\.(\d+)\.').firstMatch(dartVersion);
  if (match == null) {
    return null;
  }
  final major = int.tryParse(match.group(1)!);
  final minor = int.tryParse(match.group(2)!);
  if (major == null || minor == null) {
    return null;
  }
  return '>=$major.$minor.0 <${major + 1}.0.0';
}

Map<String, Object?>? _dartSdkConstraintFailure(SelectedToolResult result) {
  final output = result.combinedOutput;
  final current = RegExp(
    r'The current Dart SDK version is\s+([^\s.]+(?:\.[^\s.]+)*)\.',
  ).firstMatch(output);
  final required = RegExp(
    r'requires SDK version\s+(.+?),\s+version solving failed',
  ).firstMatch(output);
  if (current == null || required == null) {
    return null;
  }
  final suggestedFlutter = RegExp(
    r'Try using the Flutter SDK version:\s*([^\s.]+(?:\.[^\s.]+)*)',
  ).firstMatch(output);
  final currentVersion = current.group(1);
  return {
    'currentDartVersion': currentVersion,
    'requiredDartConstraint': required.group(1),
    if (currentVersion != null)
      'suggestedEnvironmentSdkConstraint': _suggestedEnvironmentSdkConstraint(
        currentVersion,
      ),
    if (suggestedFlutter != null)
      'suggestedFlutterSdkVersion': suggestedFlutter.group(1),
  };
}

String? _nextCommandForDiagnosticCode(
  String code,
  String packageName, {
  String? traceDir,
}) {
  final baseline = 'fluoh verify --package $packageName';
  final verifyCommand = _appendTraceDir('$baseline --json', traceDir);
  return switch (code) {
    'dart.sdk_constraint_unsatisfied' => verifyCommand,
    'dart.pub_get_failed' => 'fluoh deps get',
    'dart.analysis_failed' ||
    'dart.test_failed' ||
    'command.failed' => verifyCommand,
    _ => _platformPackageRepairCommand(code, packageName, traceDir: traceDir),
  };
}

String? _buildNextCommandForDiagnosticCode({
  required String code,
  required String packageName,
  required PlatformWorkflowPolicy policy,
  required bool debug,
  required bool autoSign,
  String? traceDir,
}) {
  final suffixSeparator = code.indexOf('.');
  final suffix = suffixSeparator < 0
      ? code
      : code.substring(suffixSeparator + 1);
  if (const {
    'hap_build_failed',
    'build_profile_patch_failed',
    'direct_sign_failed',
    'signing_profile_failed',
    'auto_sign_failed',
  }.contains(suffix)) {
    return policy.buildCommand(
      packageName: packageName,
      debug: debug,
      autoSign: autoSign,
      traceDir: traceDir,
    );
  }
  return _nextCommandForDiagnosticCode(code, packageName, traceDir: traceDir);
}

String? _platformPackageRepairCommand(
  String code,
  String packageName, {
  String? traceDir,
}) {
  final separator = code.indexOf('.');
  if (separator <= 0) {
    return null;
  }
  final platform = code.substring(0, separator);
  if (!workflowPlatformNames.contains(platform)) {
    return null;
  }
  return platformWorkflowPolicy(
    platform,
  ).packageRepairCommand(code, packageName, traceDir: traceDir);
}

String _packageRunNextCommand({
  required String packageName,
  required String platform,
  required String? deviceId,
  required bool startEmulator,
  required String? emulatorName,
  String? traceDir,
}) {
  return platformWorkflowPolicy(platform).runCommand(
    packageName: packageName,
    deviceId: deviceId,
    startEmulator: startEmulator,
    emulatorName: emulatorName,
    traceDir: traceDir,
  );
}

String _appendTraceDir(String command, String? traceDir) {
  if (traceDir == null || traceDir.isEmpty) {
    return command;
  }
  return '$command --trace-dir $traceDir';
}

bool _isStaleIosPrecompiledHeaderFailure(SelectedToolResult result) {
  final output = result.combinedOutput.toLowerCase();
  return output.contains('precompiled header') &&
      output.contains('has been modified since');
}

Map<String, Object?> _commandOutputDetails(SelectedToolResult result) {
  return {
    if (result.stdout.trim().isNotEmpty) 'stdoutTail': result.stdout,
    if (result.stderr.trim().isNotEmpty) 'stderrTail': result.stderr,
    if (result.combinedOutput.trim().isNotEmpty)
      'outputTail': result.combinedOutput,
  };
}

Future<SelectedToolResult> _runToolCommand({
  required FluohEnvironment environment,
  required Directory directory,
  required String displayPath,
  required bool flutter,
  required List<String> arguments,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required TerminalOutput output,
  required String usage,
}) async {
  final commandEnvironment = FluohEnvironment(
    homeDirectory: environment.homeDirectory,
    workingDirectory: directory,
    processEnvironment: environment.processEnvironment,
  );

  output.step(
    'Running ${flutter ? 'flutter' : 'dart'} ${arguments.join(' ')} in '
    '$displayPath',
  );
  return flutter
      ? runSelectedFlutterResult(
          environment: commandEnvironment,
          arguments: arguments,
          workingDirectory: directory,
          stdout: stdout,
          stderr: stderr,
          output: output,
          usage: usage,
        )
      : runSelectedDartResult(
          environment: commandEnvironment,
          arguments: arguments,
          workingDirectory: directory,
          stdout: stdout,
          stderr: stderr,
          output: output,
          usage: usage,
        );
}
