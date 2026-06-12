part of 'workflow_commands.dart';

Future<List<_AutomationCapability>> _automationCapabilities(
  Directory root, {
  required Directory? example,
}) async {
  final capabilities = <_AutomationCapability>[];
  final seen = <String>{};

  void add({
    required String category,
    required String item,
    required String path,
    required String source,
  }) {
    final trimmedItem = item.trim();
    if (trimmedItem.isEmpty || trimmedItem.startsWith('_')) {
      return;
    }
    final key = '$category\u0000$trimmedItem\u0000$path\u0000$source';
    if (!seen.add(key)) {
      return;
    }
    capabilities.add(
      _AutomationCapability(
        category: category,
        item: trimmedItem,
        path: path,
        source: source,
      ),
    );
  }

  final lib = Directory('${root.path}/lib');
  for (final file in await _publicLibraryEntryFiles(lib)) {
    final declarationFiles = [file, ...await _localDartExportFiles(file)];
    final declarations = <({String name, String path})>[];
    for (final declarationFile in declarationFiles) {
      final content = await _readFileIfExists(declarationFile);
      if (content == null) {
        continue;
      }
      for (final declaration in _publicDartDeclarations(content)) {
        declarations.add((name: declaration, path: declarationFile.path));
      }
    }
    if (declarations.isEmpty) {
      add(
        category: 'publicApi',
        item: _dartFileStem(file),
        path: file.path,
        source: 'publicLibrary',
      );
    } else {
      for (final declaration in declarations) {
        add(
          category: 'publicApi',
          item: declaration.name,
          path: declaration.path,
          source: 'publicLibrary',
        );
      }
    }
  }

  for (final file in await _dartFiles(lib)) {
    final content = await _readFileIfExists(file);
    if (content == null) {
      continue;
    }
    for (final method in _methodChannelCalls(content)) {
      add(
        category: 'methodChannel',
        item: method,
        path: file.path,
        source: 'dartPlatformInterface',
      );
    }
    for (final channel in _platformChannelNames(content)) {
      add(
        category: 'platformChannel',
        item: channel,
        path: file.path,
        source: 'dartPlatformInterface',
      );
    }
  }

  if (example != null) {
    final exampleLib = Directory('${example.path}/lib');
    for (final file in await _dartFiles(exampleLib)) {
      add(
        category: 'exampleFlow',
        item: _dartFileStem(file),
        path: file.path,
        source: 'exampleLibrary',
      );
    }
  }

  capabilities.sort((a, b) {
    final categoryOrder = a.category.compareTo(b.category);
    if (categoryOrder != 0) {
      return categoryOrder;
    }
    final itemOrder = a.item.compareTo(b.item);
    if (itemOrder != 0) {
      return itemOrder;
    }
    return a.path.compareTo(b.path);
  });
  return capabilities;
}

Future<List<File>> _publicLibraryEntryFiles(Directory directory) async {
  if (!await directory.exists()) {
    return const [];
  }
  final files = <File>[];
  try {
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      if (name.endsWith('.dart') && !name.startsWith('_')) {
        files.add(entity);
      }
    }
  } on FileSystemException {
    return files;
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

Future<List<File>> _dartFiles(Directory directory) async {
  if (!await directory.exists()) {
    return const [];
  }
  final files = <File>[];
  try {
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        files.add(entity);
      }
    }
  } on FileSystemException {
    return files;
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

Future<List<File>> _localDartExportFiles(File file) async {
  final files = <File>[];
  final seen = <String>{file.absolute.path};

  Future<void> visit(File current) async {
    final content = await _readFileIfExists(current);
    if (content == null) {
      return;
    }
    for (final exportPath in _localDartExportPaths(content)) {
      final exported = File.fromUri(current.uri.resolve(exportPath)).absolute;
      if (!await exported.exists()) {
        continue;
      }
      if (!seen.add(exported.path)) {
        continue;
      }
      files.add(exported);
      await visit(exported);
    }
  }

  await visit(file.absolute);
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

Iterable<String> _localDartExportPaths(String content) sync* {
  final exportRegex = RegExp(
    r'''^\s*export\s+["']([^"']+)["']''',
    multiLine: true,
  );
  for (final match in exportRegex.allMatches(_stripDartComments(content))) {
    final path = match.group(1)!.trim();
    if (path.endsWith('.dart') &&
        !path.startsWith('dart:') &&
        !path.startsWith('package:')) {
      yield path;
    }
  }
}

Iterable<String> _publicDartDeclarations(String content) sync* {
  final source = _stripDartComments(content);
  var braceDepth = 0;
  for (final line in source.split('\n')) {
    if (braceDepth == 0) {
      final name = _publicDartDeclarationName(line);
      if (name != null && !name.startsWith('_')) {
        yield name;
      }
    }
    braceDepth += _braceDelta(line);
    if (braceDepth < 0) {
      braceDepth = 0;
    }
  }
}

String? _publicDartDeclarationName(String line) {
  final trimmed = line.trimLeft();
  if (trimmed.isEmpty ||
      trimmed.startsWith('@') ||
      trimmed.startsWith('import ') ||
      trimmed.startsWith('export ') ||
      trimmed.startsWith('part ') ||
      trimmed.startsWith('library ')) {
    return null;
  }

  final typeDeclaration = RegExp(
    r'^(?:abstract\s+|base\s+|final\s+|interface\s+|sealed\s+)*'
    r'(?:class|enum|extension|mixin|typedef)\s+([A-Za-z][A-Za-z0-9_]*)',
  ).firstMatch(trimmed);
  if (typeDeclaration != null) {
    return typeDeclaration.group(1);
  }

  final getter = RegExp(
    r'^(?:external\s+)?(?:[A-Za-z][A-Za-z0-9_?<>,.\s]*\s+)?'
    r'get\s+([A-Za-z][A-Za-z0-9_]*)\b',
  ).firstMatch(trimmed);
  if (getter != null) {
    return getter.group(1);
  }

  final function = RegExp(
    r'^(?:external\s+)?(?:[A-Za-z][A-Za-z0-9_?<>,.\s]*\s+)?'
    r'([A-Za-z][A-Za-z0-9_]*)\s*(?:<[^>]+>)?\s*\(',
  ).firstMatch(trimmed);
  if (function != null) {
    final name = function.group(1);
    if (name != 'if' &&
        name != 'for' &&
        name != 'while' &&
        name != 'switch' &&
        name != 'catch') {
      return name;
    }
  }

  return _publicTopLevelVariableName(trimmed);
}

String? _publicTopLevelVariableName(String trimmed) {
  final keywordVariable = RegExp(
    r'^(?:external\s+)?(?:late\s+)?(?:final|const|var)\s+(.+)$',
  ).firstMatch(trimmed);
  if (keywordVariable != null) {
    return _lastIdentifierBeforeInitializer(keywordVariable.group(1)!);
  }

  final typedVariable = RegExp(
    r'^[A-Za-z][A-Za-z0-9_?<>,.\s]*\s+([A-Za-z][A-Za-z0-9_]*)\s*(?:=|;)',
  ).firstMatch(trimmed);
  return typedVariable?.group(1);
}

String? _lastIdentifierBeforeInitializer(String source) {
  final declaration = source.split(RegExp(r'[=;,]')).first.trim();
  if (declaration.isEmpty) {
    return null;
  }
  final tokens = declaration.split(RegExp(r'\s+'));
  final candidate = tokens.last.trim();
  return RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(candidate)
      ? candidate
      : null;
}

int _braceDelta(String line) {
  var delta = 0;
  for (var index = 0; index < line.length; index += 1) {
    final char = line[index];
    if (char == '{') {
      delta += 1;
    } else if (char == '}') {
      delta -= 1;
    }
  }
  return delta;
}

Iterable<String> _methodChannelCalls(String content) sync* {
  final methodRegex = RegExp(
    r'''\.invokeMethod(?:<[^>]+>)?\(\s*["']([^"']+)["']''',
    multiLine: true,
  );
  for (final match in methodRegex.allMatches(content)) {
    final name = match.group(1)!;
    if (!name.startsWith('_')) {
      yield name;
    }
  }
}

Iterable<String> _platformChannelNames(String content) sync* {
  final channelRegex = RegExp(
    r'''(?:MethodChannel|EventChannel|BasicMessageChannel)(?:<[^>]+>)?\s*\(\s*["']([^"']+)["']''',
    multiLine: true,
  );
  for (final match in channelRegex.allMatches(_stripDartComments(content))) {
    final name = match.group(1)!;
    if (!name.startsWith('_')) {
      yield name;
    }
  }
}

String _stripDartComments(String content) {
  return content
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//.*$', multiLine: true), '');
}

String _dartFileStem(File file) {
  final name = file.uri.pathSegments.last;
  return name.endsWith('.dart') ? name.substring(0, name.length - 5) : name;
}
