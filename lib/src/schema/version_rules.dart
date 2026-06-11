import 'package:pub_semver/pub_semver.dart';

import 'yaml_utils.dart';

final _completeFlutterOhosSdkVersion = RegExp(r'^(\d+)\.(\d+)\.(\d+)-ohos-.+$');

/// Returns the conventional FlutterOH adaptation branch for an SDK version.
String flutterOhosBranchForSdk(String sdkVersion) =>
    'ohos/${sdkLineFromSdkVersion(sdkVersion)}';

/// Returns the conventional FlutterOH package branch for an SDK and package.
String flutterOhosPackageBranchForSdk({
  required String sdkVersion,
  required String packageName,
}) {
  validateDartPackageName(packageName, label: 'package name');
  return '${flutterOhosBranchForSdk(sdkVersion)}/$packageName';
}

/// Builds the package release tag used by FlutterOH package repositories.
String packageReleaseTagForPackage({
  required String packageName,
  required String upstreamVersion,
  required String sdkVersion,
  required String releaseVersion,
}) {
  validateDartPackageName(packageName, label: 'package name');
  validatePubVersion(upstreamVersion, label: 'upstream version');
  validateReleaseVersion(releaseVersion, label: 'release version');
  final sdkLine = sdkLineFromSdkVersion(sdkVersion);
  return '$packageName-$upstreamVersion-ohos-$sdkLine-$releaseVersion';
}

/// Parses a canonical FlutterOH package release tag.
///
/// Canonical tags have this shape:
/// `<package>-<upstreamVersion>-ohos-<sdkLine>-<releaseVersion>`.
PackageReleaseTag parsePackageReleaseTag(String tag) {
  final separator = tag.indexOf('-ohos-');
  if (separator == -1) {
    throw FluohSchemaException('release tag must contain "-ohos-".');
  }
  final left = tag.substring(0, separator);
  final right = tag.substring(separator + '-ohos-'.length);
  final packageSeparator = left.indexOf('-');
  if (packageSeparator == -1) {
    throw FluohSchemaException('release tag must include an upstream version.');
  }
  final sdkSeparator = right.indexOf('-');
  if (sdkSeparator == -1) {
    throw FluohSchemaException('release tag must include a release version.');
  }
  final packageName = left.substring(0, packageSeparator);
  final upstreamVersion = left.substring(packageSeparator + 1);
  final sdkLine = right.substring(0, sdkSeparator);
  final releaseVersion = right.substring(sdkSeparator + 1);
  validateDartPackageName(packageName, label: 'release tag package name');
  validatePubVersion(upstreamVersion, label: 'release tag upstream version');
  if (!RegExp(r'^\d+\.\d+$').hasMatch(sdkLine)) {
    throw FluohSchemaException(
      'release tag SDK line must use <major>.<minor>.',
    );
  }
  validatePubVersion(releaseVersion, label: 'release tag release version');
  return PackageReleaseTag(
    packageName: packageName,
    upstreamVersion: upstreamVersion,
    sdkLine: sdkLine,
    releaseVersion: releaseVersion,
  );
}

/// Extracts the FlutterOH version prefix from a complete SDK tag.
String flutterOhosVersionFromSdkVersion(String sdkVersion) {
  final match = RegExp(r'^(\d+\.\d+\.\d+-ohos)-.+$').firstMatch(sdkVersion);
  if (match == null) {
    throw FormatException('Invalid FlutterOH SDK version: $sdkVersion');
  }
  return match.group(1)!;
}

/// Returns the SDK release series used by dependency compatibility indexes.
String sdkVersionSeriesFromSdkVersion(String sdkVersion) {
  return sdkLineFromSdkVersion(sdkVersion);
}

/// Extracts the major.minor SDK line from a complete SDK tag.
String sdkLineFromSdkVersion(String sdkVersion) {
  final match = _completeFlutterOhosSdkVersion.firstMatch(sdkVersion);
  if (match == null) {
    throw FormatException('Invalid FlutterOH SDK version: $sdkVersion');
  }
  return '${match.group(1)}.${match.group(2)}';
}

/// Extracts the upstream Flutter version from a FlutterOH SDK tag.
String flutterVersionFromSdkVersion(String version) {
  final match = RegExp(r'^(\d+\.\d+\.\d+)-ohos-.+$').firstMatch(version);
  if (match == null) {
    throw FormatException('Invalid FlutterOH SDK version: $version');
  }
  return match.group(1)!;
}

/// Converts SSH Git repository URLs to HTTPS URLs for pub dependencies.
String dependencyUrlForImplementationRepository(String repository) {
  final trimmed = repository.trim();
  final match = RegExp(r'^git@([^:]+):(.+)$').firstMatch(trimmed);
  if (match == null) {
    return trimmed;
  }
  return 'https://${match.group(1)}/${match.group(2)}';
}

/// Validates a Dart/pub semantic version used by package releases.
void validateReleaseVersion(String version, {String label = 'version'}) {
  validatePubVersion(version, label: label);
}

/// Validates a Dart/pub semantic version.
void validatePubVersion(String version, {String label = 'version'}) {
  try {
    Version.parse(version);
  } on FormatException {
    throw FluohSchemaException('$label must be a valid pub semantic version.');
  }
}

/// Compares pub semantic versions from newest to oldest.
int comparePubVersionsDescending(String left, String right) {
  return Version.parse(right).compareTo(Version.parse(left));
}

/// Compares pub semantic versions from oldest to newest.
int comparePubVersionsAscending(String left, String right) {
  return Version.parse(left).compareTo(Version.parse(right));
}

/// Validates a Dart package name used as a Source package key.
void validateDartPackageName(String name, {String label = 'package name'}) {
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
    throw FluohSchemaException(
      '$label must be a Dart package name using lowercase letters, numbers, '
      'and "_", starting with a letter.',
    );
  }
}

/// Returns a normalized relative package path used inside repositories.
String normalizeManifestPath(String? path, {String label = 'path'}) {
  var value = path?.trim() ?? '';
  if (value.isEmpty || value == '.') {
    return '.';
  }
  while (value.startsWith('./')) {
    value = value.substring(2);
  }
  if (value.isEmpty || value == '.') {
    return '.';
  }
  if (value.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) {
    throw FluohSchemaException('$label must be a relative package path.');
  }
  if (value.contains('\\')) {
    throw FluohSchemaException('$label must use forward slashes.');
  }
  final segments = value.split('/');
  if (segments.any((segment) => segment.isEmpty || segment == '..')) {
    throw FluohSchemaException(
      '$label must be a normalized relative package path.',
    );
  }
  return value;
}

/// Returns a normalized version-like token that can safely appear in a tag.
String validateVersionToken(String version, {String label = 'version'}) {
  final value = version.trim();
  if (value.isEmpty || RegExp(r'\s').hasMatch(value)) {
    throw FluohSchemaException('$label must be a non-empty token.');
  }
  return value;
}

/// Returns a normalized Git ref or tag token.
String normalizeGitRef(String ref, {String label = 'ref'}) {
  final value = ref.trim();
  if (value.isEmpty) {
    throw FluohSchemaException('$label must not be empty.');
  }
  if (RegExp(r'\s').hasMatch(value) ||
      value.startsWith('/') ||
      value.endsWith('/') ||
      value.contains('//')) {
    throw FluohSchemaException('$label must be a Git ref without whitespace.');
  }
  return value;
}

/// Returns a normalized full Git commit hash.
String normalizeGitCommitHash(String commit, {String label = 'commit'}) {
  final value = commit.trim();
  if (!RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(value)) {
    throw FluohSchemaException(
      '$label must be a 40-character hexadecimal Git commit hash.',
    );
  }
  return value;
}

/// Parsed canonical FlutterOH package release tag components.
class PackageReleaseTag {
  /// Creates a parsed package release tag.
  const PackageReleaseTag({
    required this.packageName,
    required this.upstreamVersion,
    required this.sdkLine,
    required this.releaseVersion,
  });

  /// Dart package name.
  final String packageName;

  /// Upstream package version.
  final String upstreamVersion;

  /// FlutterOH SDK line.
  final String sdkLine;

  /// FlutterOH adaptation release version.
  final String releaseVersion;
}
