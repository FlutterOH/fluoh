import 'yaml_utils.dart';

/// Returns the conventional FlutterOH adaptation branch for an SDK version.
String flutterOhosBranchForSdk(String sdkVersion) =>
    'ohos/${sdkLineFromSdkVersion(sdkVersion)}';

/// Builds the package release tag used by FlutterOH package repositories.
String packageReleaseTagForPackage({
  required String packageName,
  required String upstreamVersion,
  required String sdkVersion,
  required String releaseVersion,
}) {
  final sdkLine = sdkLineFromSdkVersion(sdkVersion);
  return '$packageName-$upstreamVersion-ohos-$sdkLine-$releaseVersion';
}

/// Extracts the FlutterOH version prefix from a complete SDK tag.
String flutterOhosVersionFromSdkVersion(String sdkVersion) {
  final match = RegExp(r'^(\d+\.\d+\.\d+-ohos)-.+$').firstMatch(sdkVersion);
  if (match == null) {
    throw FormatException('Invalid Flutter OHOS SDK version: $sdkVersion');
  }
  return match.group(1)!;
}

/// Returns the SDK release series used by dependency compatibility indexes.
String sdkVersionSeriesFromSdkVersion(String sdkVersion) {
  return sdkLineFromSdkVersion(sdkVersion);
}

/// Extracts the major.minor SDK line from a complete SDK tag.
String sdkLineFromSdkVersion(String sdkVersion) {
  final match = RegExp(r'^(\d+)\.(\d+)\.').firstMatch(sdkVersion);
  if (match == null) {
    throw FormatException('Invalid Flutter OHOS SDK version: $sdkVersion');
  }
  return '${match.group(1)}.${match.group(2)}';
}

/// Extracts the upstream Flutter version from a FlutterOH SDK tag.
String flutterVersionFromSdkVersion(String version) {
  final match = RegExp(r'^(\d+\.\d+\.\d+)-ohos-.+$').firstMatch(version);
  if (match == null) {
    throw FormatException('Invalid Flutter OHOS SDK version: $version');
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

/// Validates a dot-separated numeric package release version.
void validateReleaseVersion(String version, {String label = 'version'}) {
  if (!RegExp(r'^\d+(?:\.\d+)*$').hasMatch(version)) {
    throw FluohSchemaException('$label must use numeric dot-separated parts.');
  }
}
