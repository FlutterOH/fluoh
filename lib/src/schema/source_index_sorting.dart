part of 'source_index.dart';

List<SourceManifestSdk> _sortedManifestSdks(Iterable<SourceManifestSdk> sdks) {
  return sdks.toList(growable: false)..sort(
    (left, right) => _compareSdkLinesAscending(left.sdkLine, right.sdkLine),
  );
}

List<SourceManifestRelease> _sortedManifestReleases(
  Iterable<SourceManifestRelease> releases,
) {
  return releases.toList(growable: false)
    ..sort(_compareManifestReleasesAscending);
}

int _compareManifestReleasesAscending(
  SourceManifestRelease left,
  SourceManifestRelease right,
) {
  final upstream = comparePubVersionsAscending(
    left.upstreamVersion,
    right.upstreamVersion,
  );
  if (upstream != 0) {
    return upstream;
  }
  final release = comparePubVersionsAscending(left.version, right.version);
  if (release != 0) {
    return release;
  }
  final commit = left.upstreamCommit.compareTo(right.upstreamCommit);
  if (commit != 0) {
    return commit;
  }
  return (left.upstreamRef ?? '').compareTo(right.upstreamRef ?? '');
}

List<SdkRelease> _sortedSdkReleases(Iterable<SdkRelease> releases) {
  return releases.toList(growable: false)..sort((left, right) {
    final version = comparePubVersionsAscending(left.version, right.version);
    if (version != 0) {
      return version;
    }
    return left.repository.compareTo(right.repository);
  });
}

List<SourceManifestRoute> _sortedManifestRoutes(
  Iterable<SourceManifestRoute> routes,
) {
  return routes.toList(growable: false)
    ..sort((left, right) => left.name.compareTo(right.name));
}

int _compareSdkLinesAscending(String left, String right) {
  final leftParts = left.split('.').map(int.parse).toList(growable: false);
  final rightParts = right.split('.').map(int.parse).toList(growable: false);
  for (var i = 0; i < leftParts.length && i < rightParts.length; i += 1) {
    final compared = leftParts[i].compareTo(rightParts[i]);
    if (compared != 0) {
      return compared;
    }
  }
  return leftParts.length.compareTo(rightParts.length);
}

String _manifestPubVersion(String version, {required String label}) {
  validatePubVersion(version, label: label);
  return version;
}

String _yamlScalar(String value) {
  if (!_shouldQuoteYamlScalar(value)) {
    return value;
  }
  final escaped = value
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\t', '\\t');
  return '"$escaped"';
}

bool _shouldQuoteYamlScalar(String value) {
  if (value.isEmpty) {
    return true;
  }
  if (value.startsWith(RegExp(r'''[-?:,[\]{}#&*!|>@`"']'''))) {
    return true;
  }
  if (value.contains(RegExp(r'[\s:]'))) {
    return true;
  }
  if (RegExp(
    r'^[+-]?(?:\d+|\d+\.\d+|\.\d+)(?:[eE][+-]?\d+)?$',
  ).hasMatch(value)) {
    return true;
  }
  if (const {'true', 'false', 'null', '~'}.contains(value.toLowerCase())) {
    return true;
  }
  return false;
}

List<String> _stringList(
  Object? value,
  String label, {
  bool allowNull = false,
}) {
  if (value == null && allowNull) {
    return const <String>[];
  }
  if (value is! List) {
    throw FluohSchemaException('$label must be a YAML list.');
  }
  return value
      .map((item) => _nonEmptyString(item, '$label[]'))
      .toList(growable: false);
}

List<Map<String, Object?>> _objectList(
  Object? value,
  String label, {
  bool allowNull = false,
}) {
  if (value == null && allowNull) {
    return const <Map<String, Object?>>[];
  }
  if (value is! List) {
    throw FluohSchemaException('$label must be a YAML list.');
  }
  return [
    for (var index = 0; index < value.length; index += 1)
      objectMap(value[index], '$label[$index]'),
  ];
}

String _nonEmptyString(Object? value, String label) {
  if (value == null || '$value'.isEmpty) {
    throw FluohSchemaException('$label must be a non-empty string.');
  }
  return '$value';
}

String _requiredScalarString(Map<String, Object?> yaml, String key) {
  final value = yaml[key];
  if (value == null || '$value'.isEmpty) {
    throw FluohSchemaException('Expected "$key" to be a non-empty value.');
  }
  return '$value';
}

String _sdkLine(Object? value, String label) {
  final text = _nonEmptyString(value, label);
  if (!RegExp(r'^\d+\.\d+$').hasMatch(text)) {
    throw FluohSchemaException('$label must use <major>.<minor>, got $text.');
  }
  return text;
}

void _validateSourceName(String value, {required String label}) {
  if (value.isEmpty || RegExp(r'\s').hasMatch(value)) {
    throw FluohSchemaException('$label must be a non-empty token.');
  }
}

void _ensureSourceSchema(Map<String, Object?> yaml, String label) {
  final schema = yaml['schema'];
  if (schema == null) {
    throw FluohSchemaException('$label missing "schema".');
  }
  if (schema is! int) {
    throw FluohSchemaException('$label schema must be an integer.');
  }
  if (schema > sourceManifestSchema) {
    throw FluohSchemaException('$label schema $schema requires a newer fluoh.');
  }
  if (schema < sourceManifestSchema) {
    throw FluohSchemaException(
      '$label schema $schema is not supported. Expected schema '
      '$sourceManifestSchema.',
    );
  }
}

void _requireKind(Map<String, Object?> yaml, String expected, String label) {
  final kind = yaml['kind'];
  if (kind != expected) {
    throw FluohSchemaException('$label kind must be "$expected".');
  }
}

class _FlutterOhosSdkSource {
  const _FlutterOhosSdkSource({
    required this.repository,
    required this.releases,
  });

  final String repository;
  final List<SdkRelease> releases;
}
