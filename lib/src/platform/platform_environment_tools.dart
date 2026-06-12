part of 'platform_environment.dart';

Future<String?> _latestAndroidPlatform(io.Directory? sdkRoot) async {
  if (sdkRoot == null) {
    return null;
  }
  final platforms = io.Directory('${sdkRoot.path}/platforms');
  if (!await platforms.exists()) {
    return null;
  }
  final versions = <String>[];
  await for (final entity in platforms.list(followLinks: false)) {
    if (entity is! io.Directory) {
      continue;
    }
    final name = _pathBaseName(entity.path);
    if (RegExp(r'^android-\d+$').hasMatch(name)) {
      versions.add(name);
    }
  }
  versions.sort(_compareAndroidPackageVersions);
  return versions.lastOrNull;
}

Future<String?> _latestBuildToolsVersion(io.Directory? sdkRoot) async {
  if (sdkRoot == null) {
    return null;
  }
  final buildTools = io.Directory('${sdkRoot.path}/build-tools');
  if (!await buildTools.exists()) {
    return null;
  }
  final versions = <String>[];
  await for (final entity in buildTools.list(followLinks: false)) {
    if (entity is! io.Directory) {
      continue;
    }
    final name = _pathBaseName(entity.path);
    if (RegExp(r'^\d+(?:\.\d+)*(?:[-_A-Za-z0-9.]*)?$').hasMatch(name)) {
      versions.add(name);
    }
  }
  versions.sort(_compareAndroidPackageVersions);
  return versions.lastOrNull;
}

Future<bool?> _androidLicensesAccepted(io.Directory? sdkRoot) async {
  if (sdkRoot == null) {
    return null;
  }
  final licenses = io.Directory('${sdkRoot.path}/licenses');
  if (!await licenses.exists()) {
    return false;
  }
  await for (final entity in licenses.list(followLinks: false)) {
    if (entity is io.File) {
      final content = await entity.readAsString().catchError((_) => '');
      if (content.trim().isNotEmpty) {
        return true;
      }
    }
  }
  return false;
}

Future<io.File?> _androidAdb(Map<String, String> env) async {
  final sdkRoot = _androidSdkRoot(env);
  return _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_ANDROID_ADB',
    candidates: [if (sdkRoot != null) '${sdkRoot.path}/platform-tools/adb'],
    fallbackName: 'adb',
  );
}

Future<io.File?> _androidEmulator(Map<String, String> env) async {
  final sdkRoot = _androidSdkRoot(env);
  return _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_ANDROID_EMULATOR',
    candidates: [if (sdkRoot != null) '${sdkRoot.path}/emulator/emulator'],
    fallbackName: 'emulator',
  );
}

io.Directory? _androidSdkRoot(Map<String, String> env) {
  for (final key in const ['ANDROID_SDK_ROOT', 'ANDROID_HOME']) {
    final value = env[key];
    if (_nonEmpty(value)) {
      return io.Directory(value!.trim());
    }
  }
  final home = env['HOME'];
  if (_nonEmpty(home)) {
    return io.Directory('${home!.trim()}/Library/Android/sdk');
  }
  return null;
}

Future<io.File?> _xcrun(Map<String, String> env) {
  return _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_XCRUN',
    candidates: const [],
    fallbackName: 'xcrun',
  );
}

Future<io.File?> _openSimulatorTool(Map<String, String> env) async {
  final configured = env['FLUOH_OPEN']?.trim();
  if (_nonEmpty(configured)) {
    final file = io.File(configured!.trim());
    return await file.exists() ? file : null;
  }
  final configuredXcrun = env['FLUOH_XCRUN']?.trim();
  if (_nonEmpty(configuredXcrun)) {
    return null;
  }
  if (!io.Platform.isMacOS) {
    return null;
  }
  final systemOpen = io.File('/usr/bin/open');
  if (await systemOpen.exists()) {
    return systemOpen;
  }
  return _findExecutable(
    environment: env,
    environmentKey: 'FLUOH_OPEN',
    candidates: const [],
    fallbackName: 'open',
  );
}

Future<String?> _xcodeDeveloperDirectory(Map<String, String> env) async {
  final developerDir = env['DEVELOPER_DIR'];
  if (_nonEmpty(developerDir) &&
      await io.Directory(developerDir!.trim()).exists()) {
    return developerDir.trim();
  }
  final result = await _runTool('xcode-select', const ['-p'], environment: env);
  if (result.exitCode != 0) {
    return null;
  }
  final path = result.stdout.trim();
  return path.isEmpty ? null : path;
}

Future<io.File?> _findWebChromeExecutable(Map<String, String> env) async {
  for (final key in const ['FLUOH_WEB_CHROME', 'CHROME_EXECUTABLE']) {
    final value = env[key];
    if (_nonEmpty(value)) {
      final file = io.File(value!.trim());
      return await file.exists() ? file : null;
    }
  }
  final candidates = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    if (_nonEmpty(env['LOCALAPPDATA']))
      '${env['LOCALAPPDATA']!.trim()}\\Google\\Chrome\\Application\\chrome.exe',
    if (_nonEmpty(env['PROGRAMFILES']))
      '${env['PROGRAMFILES']!.trim()}\\Google\\Chrome\\Application\\chrome.exe',
    if (_nonEmpty(env['PROGRAMFILES(X86)']))
      '${env['PROGRAMFILES(X86)']!.trim()}\\Google\\Chrome\\Application\\chrome.exe',
  ];
  for (final candidate in candidates) {
    final file = io.File(candidate);
    if (await file.exists()) {
      return file;
    }
  }
  final lookupCommand = io.Platform.isWindows ? 'where' : 'which';
  for (final name in const [
    'google-chrome',
    'chrome',
    'chromium',
    'chromium-browser',
  ]) {
    final lookup = await _runTool(
      lookupCommand,
      [name],
      environment: env,
      timeout: const Duration(seconds: 3),
    );
    if (lookup.exitCode != 0) {
      continue;
    }
    final path = lookup.stdout.trim().split(RegExp(r'\r\n?|\n')).firstOrNull;
    if (!_nonEmpty(path)) {
      continue;
    }
    final file = io.File(path!.trim());
    if (await file.exists()) {
      return file;
    }
  }
  return null;
}

Future<io.File?> _findExecutable({
  required Map<String, String> environment,
  required String environmentKey,
  required List<String> candidates,
  required String fallbackName,
}) async {
  final explicit = environment[environmentKey];
  if (_nonEmpty(explicit)) {
    final file = io.File(explicit!.trim());
    return await file.exists() ? file : null;
  }
  for (final candidate in candidates) {
    final file = io.File(candidate);
    if (await file.exists()) {
      return file;
    }
  }
  final lookupCommand = io.Platform.isWindows ? 'where' : 'which';
  final which = await _runTool(
    lookupCommand,
    [fallbackName],
    environment: environment,
    timeout: const Duration(seconds: 3),
  );
  if (which.exitCode != 0) {
    return null;
  }
  final path = which.stdout.trim().split(RegExp(r'\r\n?|\n')).firstOrNull;
  if (!_nonEmpty(path)) {
    return null;
  }
  final file = io.File(path!.trim());
  return await file.exists() ? file : null;
}

PlatformToolCheck _toolCheck({
  required String id,
  required String label,
  required io.File? executable,
  required String missingMessage,
  String? version,
  Map<String, Object?> details = const {},
}) {
  return PlatformToolCheck(
    id: id,
    label: label,
    ok: executable != null,
    message: executable == null ? missingMessage : '$label was found',
    path: executable?.path,
    version: version,
    details: details,
  );
}

PlatformToolCheck _fileCheck({
  required String id,
  required String label,
  required io.File file,
  required String missingMessage,
  String? version,
}) {
  final exists = file.existsSync();
  return PlatformToolCheck(
    id: id,
    label: label,
    ok: exists,
    message: exists ? '$label was found' : missingMessage,
    path: file.path,
    version: version,
  );
}

Future<String?> _toolVersion(
  io.File? executable,
  List<String> arguments, {
  required Map<String, String> environment,
  String? Function(String output)? parser,
  Duration timeout = const Duration(seconds: 3),
}) async {
  if (executable == null) {
    return null;
  }
  return _commandVersion(
    executable.path,
    arguments,
    environment: environment,
    parser: parser,
    timeout: timeout,
  );
}

Future<String?> _commandVersion(
  String executable,
  List<String> arguments, {
  required Map<String, String> environment,
  String? Function(String output)? parser,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final result = await _runTool(
    executable,
    arguments,
    environment: environment,
    timeout: timeout,
  );
  if (result.exitCode != 0) {
    return null;
  }
  final output = [result.stdout, result.stderr].join('\n');
  return parser?.call(output) ?? _firstNonEmptyLine(output);
}

String? _adbVersion(String output) {
  final match = RegExp(
    r'Android Debug Bridge version\s+([^\s]+)',
  ).firstMatch(output);
  return match?.group(1) ?? _firstNonEmptyLine(output);
}

String? _androidEmulatorVersion(String output) {
  final match = RegExp(
    r'Android emulator version\s+([^\s]+)',
  ).firstMatch(output);
  return match?.group(1) ?? _firstNonEmptyLine(output);
}

Future<String?> _openHarmonySdkVersion(io.Directory sdk) async {
  for (final path in [
    '${sdk.path}/oh-uni-package.json',
    '${sdk.path}/ets/oh-uni-package.json',
  ]) {
    final file = io.File(path);
    if (!await file.exists()) {
      continue;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) {
        final version = decoded['version']?.toString().trim();
        if (_nonEmpty(version)) {
          return version;
        }
      }
    } on Object {
      return null;
    }
  }
  return null;
}

String? _ohosHdcVersion(String output) {
  final value = _firstNonEmptyLine(output);
  if (value == null) {
    return null;
  }
  final match = RegExp(r'^Ver:\s*(.+)$').firstMatch(value.trim());
  return match?.group(1)?.trim() ?? value;
}

String? _ohosEmulatorVersion(String output) {
  final value = _firstNonEmptyLine(output);
  if (value == null) {
    return null;
  }
  return normalizeOhosEmulatorVersion(value);
}

String? _javaVersion(String output) {
  final runtime = RegExp(
    r'^(.+Runtime Environment .+)$',
    multiLine: true,
  ).firstMatch(output);
  if (runtime != null) {
    return runtime.group(1)?.trim();
  }
  final match = RegExp(r'version "([^"]+)"').firstMatch(output);
  return match?.group(1) ?? _firstNonEmptyLine(output);
}

Future<String?> _javaReleaseFileVersion(io.File? java) async {
  if (java == null) {
    return null;
  }
  final release = io.File('${java.parent.parent.path}/release');
  if (!await release.exists()) {
    return null;
  }
  final content = await release.readAsString().catchError((_) => '');
  final runtime = RegExp(
    r'^JAVA_RUNTIME_VERSION="([^"]+)"$',
    multiLine: true,
  ).firstMatch(content)?.group(1)?.trim();
  if (_nonEmpty(runtime)) {
    return runtime;
  }
  return RegExp(
    r'^JAVA_VERSION="([^"]+)"$',
    multiLine: true,
  ).firstMatch(content)?.group(1)?.trim();
}

String? _xcrunVersion(String output) {
  final match = RegExp(
    r'xcrun version\s+([^\s.]+(?:\.[^\s.]+)*)',
  ).firstMatch(output);
  return match?.group(1) ?? _firstNonEmptyLine(output);
}

String? _xcodeVersion(String output) {
  final match = RegExp(r'^Xcode\s+(.+)$', multiLine: true).firstMatch(output);
  return match?.group(1)?.trim() ?? _firstNonEmptyLine(output);
}

String? _xcodeBuildVersion(String output) {
  final match = RegExp(
    r'^Build version\s+(.+)$',
    multiLine: true,
  ).firstMatch(output);
  return match?.group(1)?.trim();
}

String? _firstNonEmptyLine(String output) {
  for (final line in const LineSplitter().convert(output)) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

PlatformTarget? _selectTarget(List<PlatformTarget> targets, String? requested) {
  final query = requested?.trim();
  if (query != null && query.isNotEmpty) {
    for (final target in targets) {
      if (target.id == query || target.name == query) {
        return target;
      }
    }
    return null;
  }
  return targets.length == 1 ? targets.single : null;
}

String _targetSelectionMessage(
  String label,
  List<PlatformTarget> targets,
  String? requested,
) {
  final query = requested?.trim();
  if (query != null && query.isNotEmpty) {
    return '$label $query was not found. Available: ${_targetNames(targets)}';
  }
  if (targets.isEmpty) {
    return 'No $label is available';
  }
  return 'Multiple ${label}s are available; pass --emulator with one of: ${_targetNames(targets)}';
}

String _targetNames(List<PlatformTarget> targets) {
  return targets.isEmpty
      ? 'none'
      : targets.map((target) => target.id).join(', ');
}

String _androidDeviceName(List<String> details, String fallback) {
  for (final detail in details) {
    if (detail.startsWith('model:')) {
      return detail.substring('model:'.length).replaceAll('_', ' ');
    }
  }
  return fallback;
}

String _pathBaseName(String path) {
  final normalized = path.replaceAll(r'\', '/');
  final trimmed = normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  final slash = trimmed.lastIndexOf('/');
  return slash == -1 ? trimmed : trimmed.substring(slash + 1);
}

int _compareAndroidPackageVersions(String left, String right) {
  final leftNumbers = _versionNumbers(left);
  final rightNumbers = _versionNumbers(right);
  final maxLength = leftNumbers.length > rightNumbers.length
      ? leftNumbers.length
      : rightNumbers.length;
  for (var index = 0; index < maxLength; index += 1) {
    final leftValue = index < leftNumbers.length ? leftNumbers[index] : 0;
    final rightValue = index < rightNumbers.length ? rightNumbers[index] : 0;
    if (leftValue != rightValue) {
      return leftValue.compareTo(rightValue);
    }
  }
  return left.compareTo(right);
}

List<int> _versionNumbers(String value) {
  return [
    for (final match in RegExp(r'\d+').allMatches(value))
      int.tryParse(match.group(0) ?? '') ?? 0,
  ];
}

bool _isAndroidStudioBundledJdk(String path) {
  final normalized = path.replaceAll(r'\', '/').toLowerCase();
  return normalized.contains('android studio.app/contents/jbr/') ||
      normalized.contains('android studio.app/contents/jre/');
}

List<String> _androidStudioBundledJavaCandidates(Map<String, String> env) {
  final configured = env['FLUOH_ANDROID_STUDIO'];
  final roots = _nonEmpty(configured)
      ? <String>[configured!.trim()]
      : <String>[
          if (io.Platform.isMacOS) ...[
            '/Applications/Android Studio.app',
            '/Applications/Android Studio Preview.app',
            if (_nonEmpty(env['HOME']))
              '${env['HOME']!.trim()}/Applications/Android Studio.app',
            if (_nonEmpty(env['HOME']))
              '${env['HOME']!.trim()}/Applications/Android Studio Preview.app',
          ],
        ];
  return [
    for (final root in roots) ...[
      '$root/Contents/jbr/Contents/Home/bin/java',
      '$root/Contents/jre/Contents/Home/bin/java',
    ],
  ];
}

Future<_CommandRun> _runTool(
  String executable,
  List<String> arguments, {
  required Map<String, String> environment,
  Duration timeout = const Duration(seconds: 15),
}) async {
  try {
    final result = await io.Process.run(
      executable,
      arguments,
      environment: environment,
    ).timeout(timeout);
    return _CommandRun(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  } on Object catch (error) {
    return _CommandRun(exitCode: 1, stdout: '', stderr: error.toString());
  }
}

String _commandFailureMessage(String command, _CommandRun result) {
  final output = [
    result.stderr.trim(),
    result.stdout.trim(),
  ].where((item) => item.isNotEmpty).join('\n');
  return output.isEmpty
      ? '$command failed with exit code ${result.exitCode}.'
      : '$command failed with exit code ${result.exitCode}: $output';
}

bool _nonEmpty(String? value) => value != null && value.trim().isNotEmpty;

Map<String, Object?> _optionalDetail(String key, Object? value) {
  return value == null ? const {} : {key: value};
}

Map<Object?, Object?> _objectMap(Object? value) {
  return value is Map ? value : const {};
}

Object? _decodeJsonOutput(String output) {
  try {
    return jsonDecode(output);
  } on FormatException {
    final start = output.indexOf('[');
    final end = output.lastIndexOf(']');
    if (start == -1 || end <= start) {
      rethrow;
    }
    return jsonDecode(output.substring(start, end + 1));
  }
}

bool _isIosDevicePlatform(String platform) {
  return platform == 'ios' ||
      platform.contains('iphoneos') ||
      platform.contains('ipados');
}
