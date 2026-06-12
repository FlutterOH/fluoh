part of 'platform_environment.dart';

/// Platforms understood by project and package workflows.
enum FluohPlatform {
  /// Android tooling and targets.
  android,

  /// iOS tooling and targets.
  ios,

  /// Linux desktop tooling and targets.
  linux,

  /// macOS host tooling.
  macos,

  /// OpenHarmony tooling and targets.
  ohos,

  /// Flutter web tooling and browser targets.
  web,

  /// Windows desktop tooling and targets.
  windows,
}

/// Convenience methods for [FluohPlatform].
extension FluohPlatformName on FluohPlatform {
  /// Lowercase command-line name for this platform.
  String get cliName {
    return switch (this) {
      FluohPlatform.android => 'android',
      FluohPlatform.ios => 'ios',
      FluohPlatform.linux => 'linux',
      FluohPlatform.macos => 'macos',
      FluohPlatform.ohos => 'ohos',
      FluohPlatform.web => 'web',
      FluohPlatform.windows => 'windows',
    };
  }
}

/// Native toolchain diagnostics for one platform.
class PlatformDoctorReport {
  /// Creates a platform doctor report.
  const PlatformDoctorReport({required this.platform, required this.checks});

  /// Platform this report describes.
  final FluohPlatform platform;

  /// Tool checks collected for the platform.
  final List<PlatformToolCheck> checks;

  /// Whether all checks passed.
  bool get ok => checks.every((check) => check.ok);

  /// Converts this report to the command JSON contract.
  Map<String, Object?> toJson() {
    return {
      'platform': platform.cliName,
      'ok': ok,
      'checks': checks.map((check) => check.toJson()).toList(),
    };
  }
}

/// Result of one native toolchain check.
class PlatformToolCheck {
  /// Creates a native toolchain check result.
  const PlatformToolCheck({
    required this.id,
    required this.label,
    required this.ok,
    required this.message,
    this.path,
    this.version,
    this.command,
    this.details = const {},
  });

  /// Stable check identifier.
  final String id;

  /// User-facing tool label.
  final String label;

  /// Whether the check passed.
  final bool ok;

  /// Human-readable check result.
  final String message;

  /// Tool or SDK path, when available.
  final String? path;

  /// Tool or SDK version, when available.
  final String? version;

  /// Command used for this check, when relevant.
  final List<String>? command;

  /// Additional structured check data.
  final Map<String, Object?> details;

  /// Converts this check to the command JSON contract.
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'label': label,
      'status': ok ? 'ok' : 'warning',
      'message': message,
      if (path != null) 'path': path,
      if (version != null) 'version': version,
      if (command != null) 'command': command,
      if (details.isNotEmpty) 'details': details,
    };
  }
}

/// Device listing report for devices or emulators on one platform.
class PlatformTargetReport {
  /// Creates a device listing report.
  const PlatformTargetReport({
    required this.platform,
    required this.kind,
    required this.ok,
    required this.targets,
    this.message,
  });

  /// Platform this report describes.
  final FluohPlatform platform;

  /// Listing kind, usually `device` or `emulator`.
  final String kind;

  /// Whether target discovery succeeded.
  final bool ok;

  /// Targets found for this platform.
  final List<PlatformTarget> targets;

  /// Warning or error message when discovery failed.
  final String? message;

  /// Converts this report to the command JSON contract.
  Map<String, Object?> toJson() {
    return {
      'platform': platform.cliName,
      'kind': kind,
      'ok': ok,
      'targets': targets
          .map((target) => target.toJson(listingKind: kind))
          .toList(),
      if (message != null) 'message': message,
    };
  }
}

/// Connected device, simulator, or emulator discovered by platform tooling.
class PlatformTarget {
  /// Creates a discovered platform target.
  const PlatformTarget({
    required this.platform,
    required this.id,
    required this.name,
    required this.kind,
    this.state,
    this.details = const {},
  });

  /// Platform that owns this target.
  final FluohPlatform platform;

  /// Stable target identifier used by platform tools.
  final String id;

  /// User-facing target name.
  final String name;

  /// Target kind, usually `device` or `emulator`.
  final String kind;

  /// Raw target state reported by platform tooling.
  final String? state;

  /// Platform-specific target details.
  final Map<String, Object?> details;

  /// Converts this target to the machine-output shape used by target reports.
  ///
  /// The optional [listingKind] lets display fields match the command context.
  /// For example, Android `emulator-*` targets discovered by `devices` are
  /// rendered as connected mobile devices, while AVDs discovered by
  /// `emulators` are rendered as emulator rows.
  Map<String, Object?> toJson({String? listingKind}) {
    final connection = platformTargetConnection(this);
    final manufacturer = platformTargetManufacturer(this);
    final summary = platformTargetSummary(this);
    return {
      'platform': platform.cliName,
      'id': id,
      'name': name,
      'kind': kind,
      'displayName': platformTargetDisplayName(this, listingKind: listingKind),
      'displayPlatform': platformTargetDisplayPlatform(this),
      'category': platformTargetCategory(this),
      if (summary.isNotEmpty) 'summary': summary,
      'connection': ?connection,
      'manufacturer': ?manufacturer,
      if (state != null) 'state': state,
      if (details.isNotEmpty) 'details': details,
    };
  }
}

/// Result of starting an emulator or simulator.
class PlatformStartResult {
  /// Creates an emulator or simulator start result.
  const PlatformStartResult({
    required this.platform,
    required this.ok,
    required this.emulator,
    required this.command,
    required this.message,
    this.pid,
  });

  /// Platform that handled the start request.
  final FluohPlatform platform;

  /// Whether the start command succeeded.
  final bool ok;

  /// Emulator or simulator id/name requested by the user.
  final String emulator;

  /// Command used to start the target.
  final List<String> command;

  /// User-facing result message.
  final String message;

  /// Started process id, when available.
  final int? pid;

  /// Converts this result to the command JSON contract.
  Map<String, Object?> toJson() {
    return {
      'platform': platform.cliName,
      'ok': ok,
      'emulator': emulator,
      'command': command,
      'message': message,
      if (pid != null) 'pid': pid,
    };
  }
}
