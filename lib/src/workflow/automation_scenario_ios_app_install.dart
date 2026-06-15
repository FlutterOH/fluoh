part of 'automation_scenario.dart';

Future<_IosAppInstallCheck> _ensureIosAppInstalled(
  _ScenarioExecutionContext context, {
  required String bundleId,
}) async {
  final targetId = context.targetId;
  if (targetId == null || targetId.trim().isEmpty) {
    return const _IosAppInstallCheck(
      passed: false,
      status: 'missingTarget',
      reason: 'iOS scenario target did not expose a simulator id',
    );
  }
  final xcrun = await findWorkflowXcrun(context.environment.processEnvironment);
  if (xcrun == null) {
    return const _IosAppInstallCheck(
      passed: false,
      status: 'missingXcrun',
      reason: 'xcrun was not found',
    );
  }
  final foreground = await _foregroundIosSimulatorIfNeeded(
    context,
    targetId: targetId,
  );

  final rebuild = await _rebuildIosSimulatorAppIfNeeded(context, bundleId);
  if (!rebuild.passed) {
    return _IosAppInstallCheck(
      passed: false,
      status: 'prebuildFailed',
      command: rebuild.command,
      reason: rebuild.reason ?? 'flutter build ios --simulator --debug failed',
      details: {
        'bundleId': bundleId,
        'targetId': targetId,
        'foreground': foreground.toJson(),
        'prebuild': rebuild.toJson(),
      },
    );
  }

  final checkArgs = ['simctl', 'get_app_container', targetId, bundleId, 'app'];
  final check = rebuild.performed
      ? null
      : await _runTool(
          xcrun.path,
          checkArgs,
          environment: context.environment.processEnvironment,
          workingDirectory: context.environment.workingDirectory,
        );
  Future<_ToolRun?> launchIfNeeded() async {
    final launchKey = '$targetId:$bundleId';
    if (context.launchedIosApps.contains(launchKey)) {
      return null;
    }
    final launchArgs = ['simctl', 'launch', targetId, bundleId];
    final launch = await _runTool(
      xcrun.path,
      launchArgs,
      environment: context.environment.processEnvironment,
      workingDirectory: context.environment.workingDirectory,
      timeout: const Duration(seconds: 60),
    );
    if (launch.exitCode == 0) {
      context.launchedIosApps.add(launchKey);
    }
    return launch;
  }

  if (check != null && check.exitCode == 0) {
    final launch = await launchIfNeeded();
    return _IosAppInstallCheck(
      passed: launch == null || launch.exitCode == 0,
      status: launch != null && launch.exitCode != 0
          ? 'launchFailed'
          : 'alreadyInstalled',
      command: launch != null && launch.exitCode != 0
          ? launch.command
          : check.command,
      reason: launch != null && launch.exitCode != 0
          ? 'simctl launch failed for $bundleId'
          : null,
      details: {
        'foreground': foreground.toJson(),
        'prebuild': rebuild.toJson(),
        'getAppContainer': check.toDetails(),
        if (launch != null) 'launch': launch.toDetails(),
      },
    );
  }

  final appBundle = await _findIosSimulatorAppBundle(context, bundleId);
  if (appBundle == null) {
    final appBundleCandidates = await _iosSimulatorAppBundleCandidates(context);
    return _IosAppInstallCheck(
      passed: false,
      status: 'missingAppBundle',
      command: check?.command ?? rebuild.command,
      reason:
          'iOS app $bundleId is not installed and no matching simulator app bundle was found under build/ios.',
      details: {
        'bundleId': bundleId,
        'targetId': targetId,
        'foreground': foreground.toJson(),
        'prebuild': rebuild.toJson(),
        if (check != null) 'getAppContainer': check.toDetails(),
        if (appBundleCandidates.isNotEmpty)
          'candidateAppBundles': [
            for (final candidate in appBundleCandidates) candidate.toJson(),
          ],
        'searchedRoots': _iosAppSearchRoots(
          context,
        ).map((root) => root.path).toList(),
      },
    );
  }

  final launchKey = '$targetId:$bundleId';
  _ToolRun? terminate;
  _ToolRun? uninstall;
  if (rebuild.performed) {
    terminate = await _runTool(
      xcrun.path,
      ['simctl', 'terminate', targetId, bundleId],
      environment: context.environment.processEnvironment,
      workingDirectory: context.environment.workingDirectory,
    );
    uninstall = await _runTool(
      xcrun.path,
      ['simctl', 'uninstall', targetId, bundleId],
      environment: context.environment.processEnvironment,
      workingDirectory: context.environment.workingDirectory,
    );
    context.launchedIosApps.remove(launchKey);
  }

  final installArgs = ['simctl', 'install', targetId, appBundle.path];
  final install = await _runTool(
    xcrun.path,
    installArgs,
    environment: context.environment.processEnvironment,
    workingDirectory: context.environment.workingDirectory,
    timeout: const Duration(seconds: 120),
  );
  final launch = install.exitCode == 0 ? await launchIfNeeded() : null;
  return _IosAppInstallCheck(
    passed: install.exitCode == 0 && (launch == null || launch.exitCode == 0),
    status: install.exitCode != 0
        ? 'installFailed'
        : launch != null && launch.exitCode != 0
        ? 'launchFailed'
        : 'installed',
    command: launch != null && launch.exitCode != 0
        ? launch.command
        : install.command,
    reason: install.exitCode != 0
        ? 'simctl install failed for ${appBundle.path}'
        : launch != null && launch.exitCode != 0
        ? 'simctl launch failed for $bundleId'
        : null,
    details: {
      'bundleId': bundleId,
      'targetId': targetId,
      'appBundle': appBundle.path,
      'foreground': foreground.toJson(),
      'prebuild': rebuild.toJson(),
      if (check != null) 'getAppContainer': check.toDetails(),
      if (terminate != null) 'terminate': terminate.toDetails(),
      if (uninstall != null) 'uninstall': uninstall.toDetails(),
      'install': install.toDetails(),
      if (launch != null) 'launch': launch.toDetails(),
    },
  );
}

Future<_IosSimulatorForegroundResult> _foregroundIosSimulatorIfNeeded(
  _ScenarioExecutionContext context, {
  required String targetId,
}) async {
  final mode = context
      .environment
      .processEnvironment['FLUOH_IOS_FOREGROUND_SIMULATOR']
      ?.trim()
      .toLowerCase();
  if (mode == '0' || mode == 'false' || mode == 'off' || mode == 'no') {
    return const _IosSimulatorForegroundResult(status: 'disabled');
  }
  if (context.foregroundedIosSimulators.contains(targetId)) {
    return const _IosSimulatorForegroundResult(status: 'alreadyForegrounded');
  }
  final open = await _openSimulatorTool(context.environment.processEnvironment);
  if (open == null) {
    return const _IosSimulatorForegroundResult(status: 'missingOpen');
  }
  final args = ['-a', 'Simulator', '--args', '-CurrentDeviceUDID', targetId];
  final result = await _runTool(
    open.path,
    args,
    environment: context.environment.processEnvironment,
    workingDirectory: context.environment.workingDirectory,
    timeout: const Duration(seconds: 15),
  );
  if (result.exitCode == 0) {
    context.foregroundedIosSimulators.add(targetId);
  }
  return _IosSimulatorForegroundResult(
    status: result.exitCode == 0 ? 'foregrounded' : 'failed',
    command: result.command,
    details: result.toDetails(),
  );
}

Future<_IosAppPrebuildResult> _rebuildIosSimulatorAppIfNeeded(
  _ScenarioExecutionContext context,
  String bundleId,
) async {
  final key = '${context.targetId}:$bundleId';
  if (context.rebuiltIosApps.contains(key)) {
    return const _IosAppPrebuildResult(passed: true, status: 'alreadyRebuilt');
  }
  final project = await _findIosFlutterProjectForBundle(context, bundleId);
  if (project == null) {
    return const _IosAppPrebuildResult(passed: true, status: 'notFound');
  }
  final sdkVersion = await SdkManager(context.environment).currentSdkVersion();
  if (sdkVersion == null || sdkVersion.trim().isEmpty) {
    return const _IosAppPrebuildResult(passed: true, status: 'noSelectedSdk');
  }
  final flutter = File(
    '${context.environment.sdksDirectory.path}/$sdkVersion/bin/flutter',
  );
  if (!await flutter.exists()) {
    return _IosAppPrebuildResult(
      passed: true,
      status: 'missingSelectedFlutter',
      details: {'flutter': flutter.path, 'sdkVersion': sdkVersion},
    );
  }
  final args = ['build', 'ios', '--simulator', '--debug'];
  final result = await _runTool(
    flutter.path,
    args,
    environment: selectedToolProcessEnvironment(
      environment: context.environment,
      tool: flutter,
    ),
    workingDirectory: project,
    timeout: const Duration(minutes: 10),
  );
  if (result.exitCode == 0) {
    context.rebuiltIosApps.add(key);
  }
  return _IosAppPrebuildResult(
    passed: result.exitCode == 0,
    status: result.exitCode == 0 ? 'rebuilt' : 'failed',
    command: result.command,
    reason: result.exitCode == 0
        ? null
        : 'flutter build ios --simulator --debug failed before XCTest',
    details: {
      'project': project.path,
      'sdkVersion': sdkVersion,
      'flutter': flutter.path,
      ...result.toDetails(),
    },
  );
}

class _IosSimulatorForegroundResult {
  const _IosSimulatorForegroundResult({
    required this.status,
    this.command,
    this.details = const {},
  });

  final String status;
  final String? command;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() {
    return {
      'status': status,
      if (command != null) 'command': command,
      ...details,
    };
  }
}

Future<Directory?> _findIosFlutterProjectForBundle(
  _ScenarioExecutionContext context,
  String bundleId,
) async {
  final candidates = <_IosFlutterProjectCandidate>[];
  for (final root in _iosAppSearchRoots(context)) {
    final pubspec = File('${root.path}/pubspec.yaml');
    final ios = Directory('${root.path}/ios');
    if (!await pubspec.exists() || !await ios.exists()) {
      continue;
    }
    var priority = 20;
    final releaseBundle = Directory(
      '${root.path}/build/ios/iphonesimulator/Runner.app',
    );
    final debugBundle = Directory(
      '${root.path}/build/ios/Debug-iphonesimulator/Runner.app',
    );
    if ((await _iosAppBundleIdentifier(releaseBundle)) == bundleId) {
      priority = 0;
    } else if ((await _iosAppBundleIdentifier(debugBundle)) == bundleId) {
      priority = 10;
    }
    candidates.add(_IosFlutterProjectCandidate(root.absolute, priority));
  }
  if (candidates.isEmpty) {
    return null;
  }
  candidates.sort((a, b) {
    final priority = a.priority.compareTo(b.priority);
    if (priority != 0) {
      return priority;
    }
    return a.directory.path.compareTo(b.directory.path);
  });
  return candidates.first.directory;
}

class _IosFlutterProjectCandidate {
  const _IosFlutterProjectCandidate(this.directory, this.priority);

  final Directory directory;
  final int priority;
}

class _IosAppPrebuildResult {
  const _IosAppPrebuildResult({
    required this.passed,
    required this.status,
    this.command,
    this.reason,
    this.details = const {},
  });

  final bool passed;
  final String status;
  final String? command;
  final String? reason;
  final Map<String, Object?> details;

  bool get performed => status == 'rebuilt';

  Map<String, Object?> toJson() {
    return {
      'status': status,
      if (command != null) 'command': command,
      if (reason != null) 'reason': reason,
      ...details,
    };
  }
}

Future<Directory?> _findIosSimulatorAppBundle(
  _ScenarioExecutionContext context,
  String bundleId,
) async {
  final ordered = await _iosSimulatorAppBundleCandidates(context);
  for (final candidate in ordered) {
    if (candidate.bundleIdentifier == bundleId) {
      return candidate.directory;
    }
  }
  return null;
}

Future<List<_IosAppBundleCandidate>> _iosSimulatorAppBundleCandidates(
  _ScenarioExecutionContext context,
) async {
  final candidates = <_IosAppBundleCandidate>[];
  for (final root in _iosAppSearchRoots(context)) {
    Future<void> addCandidate(String path, int priority) async {
      final candidate = Directory(path);
      if (await candidate.exists()) {
        candidates.add(_IosAppBundleCandidate(candidate.absolute, priority));
      }
    }

    await addCandidate('${root.path}/build/ios/iphonesimulator/Runner.app', 0);
    await addCandidate(
      '${root.path}/build/ios/Debug-iphonesimulator/Runner.app',
      10,
    );
    final buildIos = Directory('${root.path}/build/ios');
    if (await buildIos.exists()) {
      try {
        await for (final entity in buildIos.list(recursive: true)) {
          if (entity is Directory &&
              entity.path.endsWith('.app') &&
              entity.path.contains('iphonesimulator')) {
            candidates.add(
              _IosAppBundleCandidate(
                entity.absolute,
                entity.path.contains('/iphonesimulator/Runner.app')
                    ? 0
                    : entity.path.contains('/Debug-iphonesimulator/')
                    ? 10
                    : 20,
              ),
            );
          }
        }
      } on FileSystemException {
        // Keep the deterministic candidates collected above.
      }
    }
  }

  final unique = <String, _IosAppBundleCandidate>{};
  for (final candidate in candidates) {
    final existing = unique[candidate.directory.path];
    if (existing == null || candidate.priority < existing.priority) {
      unique[candidate.directory.path] = candidate;
    }
  }
  final ordered = unique.values.toList()
    ..sort((a, b) {
      final priority = a.priority.compareTo(b.priority);
      if (priority != 0) {
        return priority;
      }
      return a.directory.path.compareTo(b.directory.path);
    });
  final withBundleIds = <_IosAppBundleCandidate>[];
  for (final candidate in ordered) {
    withBundleIds.add(
      _IosAppBundleCandidate(
        candidate.directory,
        candidate.priority,
        bundleIdentifier: await _iosAppBundleIdentifier(candidate.directory),
      ),
    );
  }
  return withBundleIds;
}

class _IosAppBundleCandidate {
  const _IosAppBundleCandidate(
    this.directory,
    this.priority, {
    this.bundleIdentifier,
  });

  final Directory directory;
  final int priority;
  final String? bundleIdentifier;

  Map<String, Object?> toJson() {
    return {
      'path': directory.path,
      'priority': priority,
      if (bundleIdentifier != null) 'bundleIdentifier': bundleIdentifier,
    };
  }
}

List<Directory> _scenarioSearchRoots(_ScenarioExecutionContext context) {
  final roots = <String, Directory>{
    context.environment.workingDirectory.absolute.path:
        context.environment.workingDirectory.absolute,
  };
  for (final step in context.target.steps.reversed) {
    final path = step.path.trim();
    if (path.isEmpty || path == '.') {
      continue;
    }
    final directory = Directory(
      path.startsWith('/')
          ? path
          : '${context.environment.workingDirectory.path}/$path',
    ).absolute;
    roots[directory.path] = directory;
  }
  return roots.values.toList()..sort((a, b) => a.path.compareTo(b.path));
}

List<Directory> _iosAppSearchRoots(_ScenarioExecutionContext context) {
  return _scenarioSearchRoots(context);
}

Future<String?> _iosAppBundleIdentifier(Directory appBundle) async {
  final infoPlist = File('${appBundle.path}/Info.plist');
  if (!await infoPlist.exists()) {
    return null;
  }
  try {
    final content = await infoPlist.readAsString();
    final match = RegExp(
      r'<key>\s*CFBundleIdentifier\s*</key>\s*<string>([^<]+)</string>',
      multiLine: true,
      dotAll: true,
    ).firstMatch(content);
    final value = match?.group(1)?.trim();
    if (value != null && value.isNotEmpty) {
      return _decodeXmlEntities(value);
    }
  } on FormatException {
    // Binary plists are handled by PlistBuddy below when available.
  } on FileSystemException {
    return null;
  }
  if (!Platform.isMacOS) {
    return null;
  }
  final plistBuddy = File('/usr/libexec/PlistBuddy');
  if (!await plistBuddy.exists()) {
    return null;
  }
  try {
    final result = await Process.run(plistBuddy.path, [
      '-c',
      'Print CFBundleIdentifier',
      infoPlist.path,
    ]).timeout(const Duration(seconds: 5));
    if (result.exitCode == 0) {
      final value = result.stdout.toString().trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
  } on Object {
    return null;
  }
  return null;
}

String _decodeXmlEntities(String value) {
  return value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

class _IosAppInstallCheck {
  const _IosAppInstallCheck({
    required this.passed,
    required this.status,
    this.command,
    this.reason,
    this.details = const {},
  });

  final bool passed;
  final String status;
  final String? command;
  final String? reason;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() {
    return {
      'status': status,
      if (command != null) 'command': command,
      if (reason != null) 'reason': reason,
      ...details,
    };
  }
}
