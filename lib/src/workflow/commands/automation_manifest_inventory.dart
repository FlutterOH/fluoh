part of 'workflow_commands.dart';

Future<List<_AutomationManifestPermission>> _manifestPermissions(
  Directory root, {
  required Directory? example,
}) async {
  final permissions = <_AutomationManifestPermission>[];
  final seen = <String>{};
  Future<void> add({
    required String platform,
    required String source,
    required File file,
    required Iterable<String> names,
  }) async {
    for (final name in names) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final key = '$platform\u0000$source\u0000$trimmed\u0000${file.path}';
      if (!seen.add(key)) {
        continue;
      }
      permissions.add(
        _AutomationManifestPermission(
          platform: platform,
          name: trimmed,
          path: file.path,
          source: source,
        ),
      );
    }
  }

  for (final sourceRoot in [
    (source: 'package', directory: root),
    if (example != null) (source: 'example', directory: example),
  ]) {
    for (final file in [
      File('${sourceRoot.directory.path}/android/src/main/AndroidManifest.xml'),
      File(
        '${sourceRoot.directory.path}/android/app/src/main/AndroidManifest.xml',
      ),
    ]) {
      final content = await _readFileIfExists(file);
      if (content != null) {
        await add(
          platform: 'android',
          source: sourceRoot.source,
          file: file,
          names: _androidManifestPermissions(content),
        );
      }
    }

    for (final file in await _filesNamed(
      Directory('${sourceRoot.directory.path}/ios'),
      'Info.plist',
    )) {
      final content = await _readFileIfExists(file);
      if (content != null) {
        await add(
          platform: 'ios',
          source: sourceRoot.source,
          file: file,
          names: _iosUsageDescriptionPermissions(content),
        );
      }
    }

    for (final file in await _filesNamed(
      Directory('${sourceRoot.directory.path}/ohos'),
      'module.json5',
    )) {
      final content = await _readFileIfExists(file);
      if (content != null) {
        await add(
          platform: 'ohos',
          source: sourceRoot.source,
          file: file,
          names: _ohosManifestPermissions(content),
        );
      }
    }
  }
  permissions.sort((a, b) {
    final platformOrder = a.platform.compareTo(b.platform);
    if (platformOrder != 0) {
      return platformOrder;
    }
    final nameOrder = a.name.compareTo(b.name);
    if (nameOrder != 0) {
      return nameOrder;
    }
    return a.path.compareTo(b.path);
  });
  return permissions;
}

Future<String?> _readFileIfExists(File file) async {
  if (!await file.exists()) {
    return null;
  }
  try {
    return await file.readAsString();
  } on FileSystemException {
    return null;
  }
}

Future<List<File>> _filesNamed(Directory directory, String name) async {
  if (!await directory.exists()) {
    return const [];
  }
  final files = <File>[];
  try {
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File && entity.uri.pathSegments.last == name) {
        files.add(entity);
      }
    }
  } on FileSystemException {
    return files;
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

Iterable<String> _androidManifestPermissions(String content) sync* {
  final regex = RegExp(
    r'''<uses-permission\b[^>]*\bandroid:name\s*=\s*["']([^"']+)["']''',
    multiLine: true,
  );
  for (final match in regex.allMatches(content)) {
    yield match.group(1)!;
  }
}

Iterable<String> _iosUsageDescriptionPermissions(String content) sync* {
  final regex = RegExp(r'<key>(NS[A-Za-z0-9]+UsageDescription)</key>');
  for (final match in regex.allMatches(content)) {
    yield match.group(1)!;
  }
}

Iterable<String> _ohosManifestPermissions(String content) sync* {
  final regex = RegExp(r'ohos\.permission\.[A-Za-z0-9_.$]+');
  for (final match in regex.allMatches(content)) {
    yield match.group(0)!;
  }
}

String _permissionCoverageItem(String platform, String value) {
  var normalized = value.trim();
  if (platform == 'ios') {
    normalized = normalized
        .replaceFirst(RegExp(r'^NS'), '')
        .replaceFirst(RegExp(r'UsageDescription$'), '');
  } else if (normalized.contains('.')) {
    normalized = normalized.split('.').last;
  }
  final token = _normalizedCoveragePath(normalized);
  if (token.contains('camera')) {
    return 'camera';
  }
  if (token.contains('readmediaaudio') || token == 'audio') {
    return 'audio';
  }
  if (token.contains('recordaudio') || token.contains('microphone')) {
    return 'microphone';
  }
  if (token.contains('speechrecognition')) {
    return 'speech';
  }
  if (token.contains('applemusic') ||
      token.contains('medialibrary') ||
      token == 'media') {
    return 'mediaLibrary';
  }
  if (token.contains('apptrackingtransparency') ||
      token.contains('usertracking')) {
    return 'appTrackingTransparency';
  }
  if (token.contains('siri')) {
    return 'assistant';
  }
  if (token.contains('backgroundlocation') ||
      token.contains('accessbackgroundlocation') ||
      token.contains('locationalways')) {
    return 'locationAlways';
  }
  if (token.contains('locationwheninuse')) {
    return 'locationWhenInUse';
  }
  if (token.contains('finelocation') ||
      token.contains('coarselocation') ||
      token.contains('location')) {
    return 'location';
  }
  if (token.contains('writeexternalstorage')) {
    return 'storage';
  }
  if (token.contains('readmediaimages') ||
      token.contains('readexternalstorage') ||
      token.contains('photo') ||
      token.contains('image')) {
    return 'photos';
  }
  if (token.contains('readmediavideo') || token.contains('video')) {
    return 'videos';
  }
  if (token.contains('getaccounts')) {
    return 'contacts';
  }
  if (token.contains('contact')) {
    return 'contacts';
  }
  if (token.contains('calendar')) {
    return 'calendar';
  }
  if (token.contains('bluetooth')) {
    return 'bluetooth';
  }
  if (token.contains('accessnotificationpolicy') ||
      token.contains('notificationcontroller')) {
    return 'accessNotificationPolicy';
  }
  if (token.contains('postnotifications') || token.contains('notification')) {
    return 'notification';
  }
  if (token.contains('sensor') || token.contains('motion')) {
    return 'sensors';
  }
  if (token.contains('activityrecognition')) {
    return 'activityRecognition';
  }
  if (token.contains('addvoicemail') ||
      token.contains('usesip') ||
      token.contains('phone') ||
      token.contains('call')) {
    return 'phone';
  }
  if (token.contains('receivemms') ||
      token.contains('receivewappush') ||
      token.contains('sms')) {
    return 'sms';
  }
  if (token.contains('ignorebatteryoptimizations')) {
    return 'ignoreBatteryOptimizations';
  }
  if (token.contains('installpackages')) {
    return 'requestInstallPackages';
  }
  if (token.contains('manageexternalstorage')) {
    return 'manageExternalStorage';
  }
  if (token.contains('systemalertwindow')) {
    return 'systemAlertWindow';
  }
  if (token.contains('scheduleexactalarm')) {
    return 'scheduleExactAlarm';
  }
  if (token.contains('nearbywifidevices')) {
    return 'nearbyWifiDevices';
  }
  return token.isEmpty ? value.trim() : token;
}
