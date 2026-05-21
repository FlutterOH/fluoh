import 'yaml_utils.dart';

String flutterOhosBranchForSdk(String sdkVersion) =>
    'ohos/${sdkLineFromSdkVersion(sdkVersion)}';

String pubReleaseTagForPackage({
  required String packageName,
  required String upstreamVersion,
  required String sdkVersion,
  required String releaseVersion,
}) {
  final sdkLine = sdkLineFromSdkVersion(sdkVersion);
  return '$packageName-$upstreamVersion-ohos-$sdkLine-$releaseVersion';
}

String flutterOhosVersionFromSdkVersion(String sdkVersion) {
  final match = RegExp(r'^(\d+\.\d+\.\d+-ohos)-.+$').firstMatch(sdkVersion);
  if (match == null) {
    throw FormatException('Invalid Flutter OHOS SDK version: $sdkVersion');
  }
  return match.group(1)!;
}

String sdkVersionSeriesFromSdkVersion(String sdkVersion) {
  return sdkLineFromSdkVersion(sdkVersion);
}

String sdkLineFromSdkVersion(String sdkVersion) {
  final match = RegExp(r'^(\d+)\.(\d+)\.').firstMatch(sdkVersion);
  if (match == null) {
    throw FormatException('Invalid Flutter OHOS SDK version: $sdkVersion');
  }
  return '${match.group(1)}.${match.group(2)}';
}

String flutterVersionFromSdkVersion(String version) {
  final match = RegExp(r'^(\d+\.\d+\.\d+)-ohos-.+$').firstMatch(version);
  if (match == null) {
    throw FormatException('Invalid Flutter OHOS SDK version: $version');
  }
  return match.group(1)!;
}

String dependencyUrlForImplementationRepository(String repository) {
  final trimmed = repository.trim();
  final match = RegExp(r'^git@([^:]+):(.+)$').firstMatch(trimmed);
  if (match == null) {
    return trimmed;
  }
  return 'https://${match.group(1)}/${match.group(2)}';
}

void validateReleaseVersion(String version, {String label = 'version'}) {
  if (!RegExp(r'^\d+(?:\.\d+)*$').hasMatch(version)) {
    throw FluohSchemaException('$label must use numeric dot-separated parts.');
  }
}
