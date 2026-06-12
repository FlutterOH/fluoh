part of 'source_runtime.dart';

const _sourceLockInlineJsonMaxLength = 120;

String _encodeSourceLockJson(Object? value) {
  final buffer = StringBuffer();
  _writeSourceLockJsonValue(buffer, value, 0, allowInline: false);
  return buffer.toString();
}

void _writeSourceLockJsonValue(
  StringBuffer buffer,
  Object? value,
  int indent, {
  bool allowInline = true,
}) {
  if (allowInline) {
    final inline = _inlineSourceLockJson(value);
    if (inline != null) {
      buffer.write(inline);
      return;
    }
  }

  if (value is Map) {
    _writeSourceLockJsonMap(buffer, value, indent);
    return;
  }
  if (value is Iterable) {
    _writeSourceLockJsonList(buffer, value.toList(growable: false), indent);
    return;
  }
  buffer.write(jsonEncode(value));
}

String? _inlineSourceLockJson(Object? value) {
  if (value is! Map && value is! Iterable) {
    return jsonEncode(value);
  }
  final encoded = jsonEncode(value);
  return encoded.length <= _sourceLockInlineJsonMaxLength ? encoded : null;
}

void _writeSourceLockJsonMap(
  StringBuffer buffer,
  Map<Object?, Object?> map,
  int indent,
) {
  if (map.isEmpty) {
    buffer.write('{}');
    return;
  }
  buffer.write('{\n');
  final entries = map.entries.toList(growable: false);
  for (var index = 0; index < entries.length; index += 1) {
    final entry = entries[index];
    _writeSourceLockJsonIndent(buffer, indent + 1);
    buffer
      ..write(jsonEncode('${entry.key}'))
      ..write(': ');
    _writeSourceLockJsonValue(buffer, entry.value, indent + 1);
    if (index != entries.length - 1) {
      buffer.write(',');
    }
    buffer.write('\n');
  }
  _writeSourceLockJsonIndent(buffer, indent);
  buffer.write('}');
}

void _writeSourceLockJsonList(
  StringBuffer buffer,
  List<Object?> list,
  int indent,
) {
  if (list.isEmpty) {
    buffer.write('[]');
    return;
  }
  buffer.write('[\n');
  for (var index = 0; index < list.length; index += 1) {
    _writeSourceLockJsonIndent(buffer, indent + 1);
    _writeSourceLockJsonValue(buffer, list[index], indent + 1);
    if (index != list.length - 1) {
      buffer.write(',');
    }
    buffer.write('\n');
  }
  _writeSourceLockJsonIndent(buffer, indent);
  buffer.write(']');
}

void _writeSourceLockJsonIndent(StringBuffer buffer, int indent) {
  buffer.write('  ' * indent);
}

String _fileSystemMessage(FileSystemException error) {
  final path = error.path;
  if (path == null || path.isEmpty) {
    return error.message;
  }
  return '${error.message}: $path';
}
