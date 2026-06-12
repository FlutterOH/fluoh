part of 'source_runtime.dart';

Future<String> _snapshotHash(Directory root) async {
  if (!await root.exists()) {
    return _stableHash({'missing': root.path});
  }
  final fingerprint = await _snapshotFingerprint(root);
  final stateHash = await _readSnapshotStateHash(root, fingerprint);
  if (stateHash != null) {
    return stateHash;
  }
  final hash = await _calculateSnapshotHash(root);
  await _writeSnapshotState(root, hash, fingerprint);
  return hash;
}

Future<String> _calculateSnapshotHash(Directory root) async {
  final files = <File>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File &&
        _relativePath(root, entity) != _sourceSnapshotStateFileName) {
      files.add(entity);
    }
  }
  files.sort(
    (a, b) => _relativePath(root, a).compareTo(_relativePath(root, b)),
  );
  return _stableHash({
    for (final file in files)
      _relativePath(root, file): _hashBytes(await file.readAsBytes()),
  });
}

Future<Map<String, Object?>> _snapshotFingerprint(Directory root) async {
  final entries = <Map<String, Object?>>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final relative = _relativePath(root, entity);
    if (relative == _sourceSnapshotStateFileName) {
      continue;
    }
    final stat = await entity.stat();
    entries.add({
      'path': relative,
      'size': stat.size,
      'modified': stat.modified.toUtc().microsecondsSinceEpoch,
    });
  }
  entries.sort((a, b) => '${a['path']}'.compareTo('${b['path']}'));
  return {'files': entries};
}

Future<String?> _readSnapshotStateHash(
  Directory root,
  Map<String, Object?> fingerprint,
) async {
  final file = File('${root.path}/$_sourceSnapshotStateFileName');
  if (!await file.exists()) {
    return null;
  }
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    if (_optionalInt(decoded['stateVersion']) != _sourceSnapshotStateVersion) {
      return null;
    }
    if (!_jsonEqual(decoded['fingerprint'], fingerprint)) {
      return null;
    }
    final hash = _optionalString(decoded['snapshotHash']);
    return hash == null || !hash.startsWith('hash64:') ? null : hash;
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
}

Future<void> _writeSnapshotState(
  Directory root,
  String snapshotHash,
  Map<String, Object?> fingerprint,
) async {
  final file = File('${root.path}/$_sourceSnapshotStateFileName');
  final content = const JsonEncoder.withIndent('  ').convert({
    'stateVersion': _sourceSnapshotStateVersion,
    'generatedBy': 'fluoh $packageVersion',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'fingerprint': fingerprint,
    'snapshotHash': snapshotHash,
  });
  await file.writeAsString('$content\n');
}

String _relativePath(Directory root, FileSystemEntity entity) {
  final rootPath = root.absolute.path;
  final entityPath = entity.absolute.path;
  if (entityPath == rootPath) {
    return '';
  }
  return entityPath.substring(rootPath.length + 1);
}

String _stableHash(Object? value) {
  final normalized = _normalizeJson(value);
  final bytes = utf8.encode(jsonEncode(normalized));
  return _hashBytes(bytes);
}

Object? _normalizeJson(Object? value) {
  if (value is Map) {
    final entries = value.entries.toList(growable: false)
      ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
    return {
      for (final entry in entries) '${entry.key}': _normalizeJson(entry.value),
    };
  }
  if (value is Iterable) {
    return [for (final item in value) _normalizeJson(item)];
  }
  return value;
}

String _hashBytes(List<int> bytes) {
  const mask = 0xffffffffffffffff;
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & mask;
  }
  return 'hash64:${hash.toRadixString(16).padLeft(16, '0')}';
}

bool _jsonEqual(Object? left, Object? right) {
  return jsonEncode(_normalizeJson(left)) == jsonEncode(_normalizeJson(right));
}

Map<String, Object?> _jsonObject(Object? value, String label) {
  if (value is! Map) {
    throw FormatException('$label must be a JSON object.');
  }
  return {for (final entry in value.entries) '${entry.key}': entry.value};
}

List<String> _jsonStringList(Object? value, String label) {
  if (value is! Iterable) {
    throw FormatException('$label must be a JSON array.');
  }
  return [for (final item in value) _requiredString(item, '$label[]')];
}

String _requiredString(Object? value, String label) {
  final text = _optionalString(value);
  if (text == null || text.isEmpty) {
    throw FormatException('$label must be a non-empty string.');
  }
  return text;
}

String? _optionalString(Object? value) {
  if (value == null) {
    return null;
  }
  return '$value';
}

int? _optionalInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  return int.tryParse('$value');
}

Future<void> _restoreFile(File file, String? content) async {
  if (content == null) {
    if (await file.exists()) {
      await file.delete();
    }
    return;
  }
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}
