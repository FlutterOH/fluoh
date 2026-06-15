import 'dart:io';

/// Finds the Android Debug Bridge executable for workflow automation.
///
/// Resolution order is `FLUOH_ANDROID_ADB`, Android SDK environment roots,
/// the HOME-based SDK fallback, then PATH.
Future<File?> findWorkflowAndroidAdb(Map<String, String> environment) async {
  final configured = environment['FLUOH_ANDROID_ADB']?.trim();
  if (configured != null && configured.isNotEmpty) {
    final file = File(configured);
    return await file.exists() ? file : null;
  }
  final sdkRoot = _workflowAndroidSdkRootPath(environment);
  if (sdkRoot != null && sdkRoot.isNotEmpty) {
    final name = Platform.isWindows ? 'adb.exe' : 'adb';
    final file = File('$sdkRoot/platform-tools/$name');
    if (await file.exists()) {
      return file;
    }
  }
  return findWorkflowExecutableOnPath('adb', environment);
}

String? _workflowAndroidSdkRootPath(Map<String, String> environment) {
  for (final key in const ['ANDROID_SDK_ROOT', 'ANDROID_HOME']) {
    final value = environment[key]?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  final home = environment['HOME']?.trim();
  if (home != null && home.isNotEmpty) {
    return '$home/Library/Android/sdk';
  }
  return null;
}

/// Finds the Xcode xcrun executable for workflow automation.
///
/// Resolution order is `FLUOH_XCRUN`, `/usr/bin/xcrun` on macOS, then PATH.
Future<File?> findWorkflowXcrun(Map<String, String> environment) async {
  final configured = environment['FLUOH_XCRUN']?.trim();
  if (configured != null && configured.isNotEmpty) {
    final file = File(configured);
    return await file.exists() ? file : null;
  }
  if (Platform.isMacOS) {
    final systemXcrun = File('/usr/bin/xcrun');
    if (await systemXcrun.exists()) {
      return systemXcrun;
    }
  }
  return findWorkflowExecutableOnPath('xcrun', environment);
}

/// Finds an executable on PATH for workflow automation.
///
/// The supplied workflow environment wins over the current process
/// environment, matching how workflow tools are launched.
Future<File?> findWorkflowExecutableOnPath(
  String executable,
  Map<String, String> environment,
) async {
  final path = environment['PATH'] ?? Platform.environment['PATH'];
  if (path == null || path.trim().isEmpty) {
    return null;
  }
  final separator = Platform.isWindows ? ';' : ':';
  final candidates = Platform.isWindows
      ? [executable, '$executable.exe', '$executable.bat', '$executable.cmd']
      : [executable];
  for (final directory in path.split(separator)) {
    if (directory.trim().isEmpty) {
      continue;
    }
    for (final candidate in candidates) {
      final file = File(
        '${directory.trim()}${Platform.pathSeparator}$candidate',
      );
      if (await _isExecutablePathCandidate(file)) {
        return file;
      }
    }
  }
  return null;
}

Future<bool> _isExecutablePathCandidate(File file) async {
  final stat = await file.stat();
  if (stat.type != FileSystemEntityType.file) {
    return false;
  }
  if (Platform.isWindows) {
    return true;
  }
  return (stat.mode & 0x49) != 0;
}
