import 'dart:io' as io;

class OhosPermissionProfile {
  const OhosPermissionProfile({
    required this.bundleName,
    required this.requestedPermissions,
    required this.restrictedPermissions,
    required this.apl,
  });

  final String bundleName;
  final List<String> requestedPermissions;
  final List<String> restrictedPermissions;
  final String apl;
}

class OhosPermissionDefinition {
  const OhosPermissionDefinition({
    required this.name,
    required this.availableLevel,
    required this.provisionEnable,
  });

  final String name;
  final String availableLevel;
  final bool provisionEnable;
}

Future<OhosPermissionProfile> readOhosPermissionProfile({
  required io.Directory ohosDirectory,
  required io.Directory openHarmonySdk,
}) async {
  final bundleName = await readOhosBundleName(ohosDirectory);
  final requestedPermissions = await readRequestedOhosPermissions(
    ohosDirectory,
  );
  final definitions = await readOhosPermissionDefinitions(openHarmonySdk);
  final restrictedPermissions = <String>[];
  var apl = 'normal';

  for (final permission in requestedPermissions) {
    final definition = definitions[permission];
    if (definition == null || !definition.provisionEnable) {
      continue;
    }
    if (_compareApl(definition.availableLevel, apl) > 0) {
      apl = definition.availableLevel;
    }
    if (definition.availableLevel != 'normal') {
      restrictedPermissions.add(permission);
    }
  }

  return OhosPermissionProfile(
    bundleName: bundleName,
    requestedPermissions: requestedPermissions,
    restrictedPermissions: restrictedPermissions,
    apl: apl,
  );
}

Future<String> readOhosBundleName(io.Directory ohosDirectory) async {
  final appJson = io.File('${ohosDirectory.path}/AppScope/app.json5');
  if (!await appJson.exists()) {
    throw const FormatException('Missing AppScope/app.json5.');
  }
  final content = await appJson.readAsString();
  final match = RegExp(r'"bundleName"\s*:\s*"([^"]+)"').firstMatch(content);
  if (match == null) {
    throw const FormatException(
      'Missing app.bundleName in AppScope/app.json5.',
    );
  }
  return match.group(1)!;
}

Future<List<String>> readRequestedOhosPermissions(
  io.Directory ohosDirectory,
) async {
  final permissions = <String>{};
  await for (final entity in ohosDirectory.list(recursive: true)) {
    if (entity is! io.File || !entity.path.endsWith('/module.json5')) {
      continue;
    }
    final normalized = entity.path.replaceAll('\\', '/');
    if (normalized.contains('/ohosTest/')) {
      continue;
    }
    final content = await entity.readAsString();
    for (final arrayText in _requestPermissionArrays(content)) {
      for (final match in RegExp(
        r'"name"\s*:\s*"(ohos\.permission\.[^"]+)"',
      ).allMatches(arrayText)) {
        permissions.add(match.group(1)!);
      }
    }
  }
  final sorted = permissions.toList()..sort();
  return sorted;
}

Future<Map<String, OhosPermissionDefinition>> readOhosPermissionDefinitions(
  io.Directory openHarmonySdk,
) async {
  final definitionsFile = io.File(
    '${openHarmonySdk.path}/previewer/common/resources/module.json',
  );
  if (!await definitionsFile.exists()) {
    return const {};
  }

  final content = await definitionsFile.readAsString();
  final definitions = <String, OhosPermissionDefinition>{};
  for (final match in RegExp(
    r'"name"\s*:\s*"(ohos\.permission\.[^"]+)"',
  ).allMatches(content)) {
    final objectStart = content.lastIndexOf('{', match.start);
    final objectEnd = content.indexOf('}', match.end);
    if (objectStart < 0 || objectEnd < 0) {
      continue;
    }
    final objectText = content.substring(objectStart, objectEnd + 1);
    final name = match.group(1)!;
    final level =
        RegExp(
          r'"availableLevel"\s*:\s*"([^"]+)"',
        ).firstMatch(objectText)?.group(1) ??
        'normal';
    final provisionEnable =
        RegExp(
          r'"provisionEnable"\s*:\s*(true|false)',
        ).firstMatch(objectText)?.group(1) ==
        'true';
    definitions[name] = OhosPermissionDefinition(
      name: name,
      availableLevel: level,
      provisionEnable: provisionEnable,
    );
  }
  return definitions;
}

Iterable<String> _requestPermissionArrays(String content) sync* {
  for (final match in RegExp(r'"requestPermissions"\s*:').allMatches(content)) {
    final start = content.indexOf('[', match.end);
    if (start < 0) {
      continue;
    }
    final end = _findMatchingDelimiter(content, start, '[', ']');
    if (end < 0) {
      continue;
    }
    yield content.substring(start, end + 1);
  }
}

int _findMatchingDelimiter(
  String content,
  int start,
  String open,
  String close,
) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var index = start; index < content.length; index += 1) {
    final char = content[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }
    if (char == '"') {
      inString = true;
      continue;
    }
    if (char == open) {
      depth += 1;
    } else if (char == close) {
      depth -= 1;
      if (depth == 0) {
        return index;
      }
    }
  }
  return -1;
}

int _compareApl(String left, String right) {
  int rank(String apl) {
    return switch (apl) {
      'normal' => 0,
      'system_basic' => 1,
      'system_core' => 2,
      _ => 0,
    };
  }

  return rank(left).compareTo(rank(right));
}
