part of 'platform_environment.dart';

/// Normalizes Apple OS versions reported by Xcode command-line tools.
String normalizeAppleOperatingSystemVersion(String value) {
  return value
      .trim()
      .replaceFirst(RegExp(r'^Version\s+', caseSensitive: false), '')
      .replaceAllMapped(
        RegExp(r'\s*\((?:Build\s+)?([^)]+)\)', caseSensitive: false),
        (match) => ' ${match.group(1)}',
      );
}

/// Returns the Flutter-style target name used in human output and JSON.
String platformTargetDisplayName(PlatformTarget target, {String? listingKind}) {
  if (listingKind == 'emulator' && target.kind == 'emulator') {
    return platformTargetEmulatorName(target);
  }
  final connection = platformTargetConnection(target);
  final qualifiers = [?connection, platformTargetCategory(target)];
  return '${target.name} ${qualifiers.map((item) => '($item)').join(' ')}';
}

/// Returns the platform column value for a target row.
String platformTargetDisplayPlatform(PlatformTarget target) {
  if (target.platform == FluohPlatform.web) {
    return 'web-javascript';
  }
  if (target.platform == FluohPlatform.linux ||
      target.platform == FluohPlatform.macos ||
      target.platform == FluohPlatform.windows) {
    return target.details['runtime']?.toString() ?? target.platform.cliName;
  }
  return target.platform.cliName;
}

/// Returns the broad device category shown as a target name qualifier.
String platformTargetCategory(PlatformTarget target) {
  return switch (target.platform) {
    FluohPlatform.android ||
    FluohPlatform.ios ||
    FluohPlatform.ohos => 'mobile',
    FluohPlatform.linux ||
    FluohPlatform.macos ||
    FluohPlatform.windows => 'desktop',
    FluohPlatform.web => 'web',
  };
}

/// Returns a connection qualifier such as `wireless`, when one is relevant.
String? platformTargetConnection(PlatformTarget target) {
  if (target.platform != FluohPlatform.ios || target.kind != 'device') {
    return null;
  }
  return isWirelessTransport(target.details['transport']) ? 'wireless' : null;
}

/// Returns the final details column used for device rows.
String platformTargetSummary(PlatformTarget target) {
  return switch (target.platform) {
    FluohPlatform.android => target.state ?? '',
    FluohPlatform.ios => _iosTargetSummary(target),
    FluohPlatform.linux => _desktopTargetSummary(target, 'Linux'),
    FluohPlatform.macos => _macosTargetSummary(target),
    FluohPlatform.ohos =>
      target.details['details']?.toString() ?? target.state ?? '',
    FluohPlatform.web => _webTargetSummary(target),
    FluohPlatform.windows => _desktopTargetSummary(target, 'Windows'),
  };
}

/// Returns the display name used by `fluoh emulators`.
String platformTargetEmulatorName(PlatformTarget target) {
  if (target.platform == FluohPlatform.android) {
    return target.name.replaceAll('_', ' ');
  }
  return target.name;
}

/// Returns the manufacturer column for emulator rows, when known.
String? platformTargetManufacturer(PlatformTarget target) {
  if (target.kind != 'emulator') {
    return null;
  }
  return switch (target.platform) {
    FluohPlatform.ios => 'Apple',
    FluohPlatform.ohos => 'Huawei',
    FluohPlatform.android => 'Google',
    FluohPlatform.linux ||
    FluohPlatform.macos ||
    FluohPlatform.web ||
    FluohPlatform.windows => null,
  };
}

String _iosTargetSummary(PlatformTarget target) {
  if (target.kind == 'emulator') {
    final runtime = target.details['runtime']?.toString();
    return runtime == null || runtime.isEmpty
        ? 'simulator'
        : '$runtime (simulator)';
  }
  final osVersion = target.details['osVersion']?.toString();
  return osVersion == null || osVersion.isEmpty
      ? 'iOS'
      : 'iOS ${normalizeAppleOperatingSystemVersion(osVersion)}';
}

String _macosTargetSummary(PlatformTarget target) {
  final osVersion = target.details['osVersion']?.toString();
  final runtime = target.details['runtime']?.toString();
  final version = osVersion == null || osVersion.isEmpty
      ? 'macOS'
      : 'macOS ${normalizeAppleOperatingSystemVersion(osVersion)}';
  return runtime == null || runtime.isEmpty ? version : '$version $runtime';
}

String _desktopTargetSummary(PlatformTarget target, String label) {
  final osVersion = target.details['osVersion']?.toString();
  final runtime = target.details['runtime']?.toString();
  final version = osVersion == null || osVersion.isEmpty
      ? label
      : '$label $osVersion';
  return runtime == null || runtime.isEmpty ? version : '$version $runtime';
}

String _webTargetSummary(PlatformTarget target) {
  final runtime = target.details['runtime']?.toString();
  final version = target.details['version']?.toString();
  if (version != null && version.isNotEmpty) {
    return version;
  }
  return runtime == null || runtime.isEmpty ? 'web' : runtime;
}

/// Whether a raw Apple device transport value represents a wireless target.
bool isWirelessTransport(Object? value) {
  final transport = _stringValue(value)?.toLowerCase();
  if (transport == null || transport.isEmpty) {
    return false;
  }
  return transport == 'network' ||
      transport == 'wifi' ||
      transport == 'wi-fi' ||
      transport == 'wireless' ||
      transport.contains('network') ||
      transport.contains('wifi') ||
      transport.contains('wireless');
}

/// Extracts the compact OpenHarmony Emulator version from tool output.
String? normalizeOhosEmulatorVersion(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  for (final pattern in [
    RegExp(r'Emulator\s*:\s*(.+)$', caseSensitive: false),
    RegExp(r'Emulator\s+version\s*:?\s*(.+)$', caseSensitive: false),
    RegExp(r'Version\s*:?\s*(.+)$', caseSensitive: false),
  ]) {
    final match = pattern.firstMatch(trimmed);
    final parsed = match?.group(1)?.trim();
    if (parsed != null && parsed.isNotEmpty) {
      return parsed;
    }
  }
  final version = RegExp(
    r'\d+(?:\.\d+){1,}(?:[-+][0-9A-Za-z.-]+)?',
  ).firstMatch(trimmed)?.group(0);
  return version ?? trimmed;
}

bool _isTruthy(Object? value) {
  if (value is bool) {
    return value;
  }
  final text = _stringValue(value)?.toLowerCase();
  return text == 'true' || text == 'yes' || text == '1';
}

bool _isFalsey(Object? value) {
  if (value is bool) {
    return !value;
  }
  final text = _stringValue(value)?.toLowerCase();
  return text == 'false' || text == 'no' || text == '0';
}

String? _stringValue(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

class _CommandRun {
  const _CommandRun({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}
