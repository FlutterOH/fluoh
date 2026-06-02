import 'dart:convert';
import 'dart:io' as io;

/// Signing config fields written temporarily to OHOS `build-profile.json5`.
class OhosDebugSigningConfig {
  /// Creates an OHOS debug signing config.
  const OhosDebugSigningConfig({
    this.name = 'default',
    this.type = 'HarmonyOS',
    required this.storeFile,
    required this.storePassword,
    required this.keyAlias,
    required this.keyPassword,
    required this.signAlg,
    required this.profile,
    required this.certpath,
  });

  /// Signing config name referenced by product entries.
  final String name;

  /// Signing config type expected by OHOS build profile.
  final String type;

  /// Absolute path to the generated keystore.
  final String storeFile;

  /// Encrypted store password value.
  final String storePassword;

  /// Key alias in the generated keystore.
  final String keyAlias;

  /// Encrypted key password value.
  final String keyPassword;

  /// Signing algorithm.
  final String signAlg;

  /// Absolute path to the signed debug profile.
  final String profile;

  /// Absolute path to the generated certificate chain.
  final String certpath;
}

/// Restorable session for temporary OHOS build-profile signing edits.
class OhosBuildProfileSigningSession {
  OhosBuildProfileSigningSession._({
    required this.buildProfile,
    required this.originalContent,
  });

  /// Build profile file that was patched.
  final io.File buildProfile;

  /// Original file content restored by [restore].
  final String originalContent;
  var _restored = false;

  /// Restores the original build profile content once.
  Future<void> restore() async {
    if (_restored) {
      return;
    }
    await buildProfile.writeAsString(originalContent);
    _restored = true;
  }
}

/// Applies temporary signing config to an OHOS build profile.
Future<OhosBuildProfileSigningSession> applyTemporaryOhosSigning({
  required io.Directory ohosDirectory,
  required OhosDebugSigningConfig config,
}) async {
  final buildProfile = io.File('${ohosDirectory.path}/build-profile.json5');
  if (!await buildProfile.exists()) {
    throw const FormatException('Missing OHOS build-profile.json5.');
  }

  final originalContent = await buildProfile.readAsString();
  final patchedContent = buildProfileWithTemporaryOhosSigning(
    originalContent,
    config,
  );
  await buildProfile.writeAsString(patchedContent);
  return OhosBuildProfileSigningSession._(
    buildProfile: buildProfile,
    originalContent: originalContent,
  );
}

/// Returns build-profile content patched with temporary OHOS signing config.
String buildProfileWithTemporaryOhosSigning(
  String content,
  OhosDebugSigningConfig config,
) {
  final signingConfigs = _findSigningConfigs(content);
  final lineIndent = _lineIndentAt(content, signingConfigs.keyStart);
  final replacement = _renderSigningConfigArray(config, lineIndent);
  var patched = content.replaceRange(
    signingConfigs.arrayStart,
    signingConfigs.arrayEnd + 1,
    replacement,
  );
  return _upsertProductSigningConfigs(patched, config.name);
}

_ArrayRange _findSigningConfigs(String content) {
  final keyMatch = RegExp(
    r'"signingConfigs"\s*:\s*\[',
    multiLine: true,
  ).firstMatch(content);
  if (keyMatch == null) {
    throw const FormatException('Missing app.signingConfigs in build-profile.');
  }
  final arrayStart = content.indexOf('[', keyMatch.start);
  final arrayEnd = _findMatchingBracket(content, arrayStart);
  return _ArrayRange(
    keyStart: keyMatch.start,
    arrayStart: arrayStart,
    arrayEnd: arrayEnd,
  );
}

String _renderSigningConfigArray(
  OhosDebugSigningConfig config,
  String lineIndent,
) {
  final itemIndent = '$lineIndent  ';
  final fieldIndent = '$itemIndent  ';
  final materialIndent = '$fieldIndent  ';
  return [
    '[',
    '$itemIndent{',
    '$fieldIndent"name": ${jsonEncode(config.name)},',
    '$fieldIndent"type": ${jsonEncode(config.type)},',
    '$fieldIndent"material": {',
    '$materialIndent"certpath": ${jsonEncode(config.certpath)},',
    '$materialIndent"storePassword": ${jsonEncode(config.storePassword)},',
    '$materialIndent"keyAlias": ${jsonEncode(config.keyAlias)},',
    '$materialIndent"keyPassword": ${jsonEncode(config.keyPassword)},',
    '$materialIndent"profile": ${jsonEncode(config.profile)},',
    '$materialIndent"signAlg": ${jsonEncode(config.signAlg)},',
    '$materialIndent"storeFile": ${jsonEncode(config.storeFile)}',
    '$fieldIndent}',
    '$itemIndent}',
    '$lineIndent]',
  ].join('\n');
}

String _upsertProductSigningConfigs(String content, String signingConfigName) {
  final productsMatch = RegExp(r'"products"\s*:\s*\[').firstMatch(content);
  if (productsMatch == null) {
    throw const FormatException(
      'Missing app.products; cannot attach OHOS signingConfig.',
    );
  }
  final arrayStart = content.indexOf('[', productsMatch.start);
  final arrayEnd = _findMatchingBracket(content, arrayStart);
  final products = _productRanges(content, arrayStart + 1, arrayEnd);
  if (products.isEmpty) {
    throw const FormatException(
      'Missing app.products entry; cannot attach OHOS signingConfig.',
    );
  }

  var patched = content;
  for (final product in products.reversed) {
    patched = _upsertProductSigningConfig(patched, product, signingConfigName);
  }
  return patched;
}

String _upsertProductSigningConfig(
  String content,
  _Range product,
  String signingConfigName,
) {
  final productText = content.substring(product.start, product.end);
  final existing = RegExp(
    r'("signingConfig"\s*:\s*)"[^"]*"',
  ).firstMatch(productText);
  if (existing != null) {
    return content.replaceRange(
      product.start + existing.start,
      product.start + existing.end,
      '${existing.group(1)!}${jsonEncode(signingConfigName)}',
    );
  }

  final nameMatch = RegExp(r'"name"\s*:\s*"[^"]+"\s*,').firstMatch(productText);
  if (nameMatch == null) {
    throw const FormatException(
      'Missing comma-terminated product name; cannot attach OHOS signingConfig.',
    );
  }
  final insertionPoint = content.indexOf('\n', product.start + nameMatch.end);
  if (insertionPoint < 0) {
    throw const FormatException(
      'Cannot attach OHOS signingConfig to one-line app.products entry.',
    );
  }
  final indent = _nextLineIndentAt(content, insertionPoint + 1);
  return content.replaceRange(
    insertionPoint + 1,
    insertionPoint + 1,
    '$indent"signingConfig": ${jsonEncode(signingConfigName)},\n',
  );
}

List<_Range> _productRanges(String content, int start, int end) {
  final ranges = <_Range>[];
  int? objectStart;
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var index = start; index < end; index += 1) {
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
    if (char == '{') {
      if (depth == 0) {
        objectStart = index;
      }
      depth += 1;
    } else if (char == '}') {
      depth -= 1;
      if (depth == 0 && objectStart != null) {
        ranges.add(_Range(start: objectStart, end: index + 1));
        objectStart = null;
      }
    }
  }
  return ranges;
}

int _findMatchingBracket(String content, int start) {
  return _findMatchingDelimiter(content, start, '[', ']');
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
  throw const FormatException('Unclosed JSON5 delimiter in build-profile.');
}

String _lineIndentAt(String content, int offset) {
  final lineStart = content.lastIndexOf('\n', offset - 1) + 1;
  final buffer = StringBuffer();
  for (var index = lineStart; index < content.length; index += 1) {
    final char = content[index];
    if (char != ' ' && char != '\t') {
      break;
    }
    buffer.write(char);
  }
  return buffer.toString();
}

String _nextLineIndentAt(String content, int offset) {
  final buffer = StringBuffer();
  for (var index = offset; index < content.length; index += 1) {
    final char = content[index];
    if (char != ' ' && char != '\t') {
      break;
    }
    buffer.write(char);
  }
  return buffer.toString();
}

class _ArrayRange {
  const _ArrayRange({
    required this.keyStart,
    required this.arrayStart,
    required this.arrayEnd,
  });

  final int keyStart;
  final int arrayStart;
  final int arrayEnd;
}

class _Range {
  const _Range({required this.start, required this.end});

  final int start;
  final int end;
}
