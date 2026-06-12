part of 'workflow_commands.dart';

List<_AutomationMissingPackageTest> _missingPackageTestsForLibraryFiles({
  required Directory root,
  required List<File> libraryFiles,
  required List<File> packageTestFiles,
  required String packageTestRunner,
}) {
  final testPaths = {for (final file in packageTestFiles) file.absolute.path};
  final lib = Directory('${root.path}/lib');
  final test = Directory('${root.path}/test');
  final missing = <_AutomationMissingPackageTest>[];
  for (final libraryFile in libraryFiles) {
    final relativeLibraryPath = _relativeFilePath(lib, libraryFile);
    if (relativeLibraryPath == null || !relativeLibraryPath.endsWith('.dart')) {
      continue;
    }
    final libraryStem = relativeLibraryPath.substring(
      0,
      relativeLibraryPath.length - '.dart'.length,
    );
    final expectedTest = File('${test.path}/${libraryStem}_test.dart').absolute;
    final flatTest = File(
      '${test.path}/${_pathBasename(libraryStem)}_test.dart',
    ).absolute;
    final accepted = <String>{expectedTest.path, flatTest.path}.toList()
      ..sort();
    if (accepted.any(testPaths.contains)) {
      continue;
    }
    missing.add(
      _AutomationMissingPackageTest(
        libraryPath: libraryFile.absolute.path,
        expectedTestPath: expectedTest.path,
        acceptedTestPaths: accepted,
        testCommand:
            '$packageTestRunner test ${_workflowShellQuote(expectedTest.path)}',
        acceptedTestCommands: [
          for (final path in accepted)
            '$packageTestRunner test ${_workflowShellQuote(path)}',
        ],
      ),
    );
  }
  missing.sort((a, b) => a.libraryPath.compareTo(b.libraryPath));
  return missing;
}

Future<List<_AutomationWeakPackageTest>> _weakPackageTestsForLibraryFiles({
  required Directory root,
  required List<File> libraryFiles,
  required List<File> packageTestFiles,
  required String packageTestRunner,
}) async {
  final testFilesByPath = {
    for (final file in packageTestFiles) file.absolute.path: file.absolute,
  };
  final lib = Directory('${root.path}/lib');
  final test = Directory('${root.path}/test');
  final weak = <_AutomationWeakPackageTest>[];
  for (final libraryFile in libraryFiles) {
    final relativeLibraryPath = _relativeFilePath(lib, libraryFile);
    if (relativeLibraryPath == null || !relativeLibraryPath.endsWith('.dart')) {
      continue;
    }
    final declarations = await _publicDeclarationNamesForLibraryFile(
      libraryFile,
    );
    if (declarations.isEmpty) {
      continue;
    }
    final libraryStem = relativeLibraryPath.substring(
      0,
      relativeLibraryPath.length - '.dart'.length,
    );
    final acceptedTestFiles = [
      File('${test.path}/${libraryStem}_test.dart').absolute,
      File('${test.path}/${_pathBasename(libraryStem)}_test.dart').absolute,
    ];
    final existingTestFiles = [
      for (final candidate in acceptedTestFiles)
        ?testFilesByPath[candidate.path],
    ];
    if (existingTestFiles.isEmpty) {
      continue;
    }
    final testSource = StringBuffer();
    for (final testFile in existingTestFiles) {
      final content = await _readFileIfExists(testFile);
      if (content != null) {
        testSource.writeln(_stripDartCommentsAndStrings(content));
      }
    }
    final source = testSource.toString();
    final exercisedDeclarations = [
      for (final declaration in declarations)
        if (_containsDartIdentifier(source, declaration)) declaration,
    ];
    final missingDeclarations = [
      for (final declaration in declarations)
        if (!exercisedDeclarations.contains(declaration)) declaration,
    ];
    if (missingDeclarations.isEmpty) {
      continue;
    }
    final testPath = existingTestFiles.first.path;
    weak.add(
      _AutomationWeakPackageTest(
        libraryPath: libraryFile.absolute.path,
        testPath: testPath,
        publicDeclarations: declarations,
        exercisedDeclarations: exercisedDeclarations,
        missingDeclarations: missingDeclarations,
        testCommand: '$packageTestRunner test ${_workflowShellQuote(testPath)}',
      ),
    );
  }
  weak.sort((a, b) => a.libraryPath.compareTo(b.libraryPath));
  return weak;
}

Future<List<String>> _publicDeclarationNamesForLibraryFile(File file) async {
  final declarations = <String>{};
  final declarationFiles = [file, ...await _localDartExportFiles(file)];
  for (final declarationFile in declarationFiles) {
    final content = await _readFileIfExists(declarationFile);
    if (content == null) {
      continue;
    }
    declarations.addAll(_publicDartDeclarations(content));
  }
  final result = declarations.toList()..sort();
  return result;
}

bool _containsDartIdentifier(String source, String identifier) {
  final pattern = RegExp(
    '(^|[^A-Za-z0-9_])${RegExp.escape(identifier)}([^A-Za-z0-9_]|'
    r'$'
    ')',
  );
  return pattern.hasMatch(source);
}

String _stripDartCommentsAndStrings(String content) {
  return _stripDartStringLiterals(_stripDartComments(content));
}

String _stripDartStringLiterals(String content) {
  final buffer = StringBuffer();
  var index = 0;
  while (index < content.length) {
    final rawPrefix =
        content[index] == 'r' &&
        index + 1 < content.length &&
        (content[index + 1] == "'" || content[index + 1] == '"') &&
        (index == 0 || !RegExp(r'[A-Za-z0-9_]').hasMatch(content[index - 1]));
    final quoteIndex = rawPrefix ? index + 1 : index;
    final quote = content[quoteIndex];
    if (quote == "'" || quote == '"') {
      buffer.write(' ');
      index = _skipDartStringLiteral(content, quoteIndex, raw: rawPrefix);
      continue;
    }
    buffer.write(content[index]);
    index += 1;
  }
  return buffer.toString();
}

int _skipDartStringLiteral(
  String content,
  int quoteIndex, {
  required bool raw,
}) {
  final quote = content[quoteIndex];
  final triple =
      quoteIndex + 2 < content.length &&
      content[quoteIndex + 1] == quote &&
      content[quoteIndex + 2] == quote;
  var index = quoteIndex + (triple ? 3 : 1);
  while (index < content.length) {
    if (!raw && content[index] == '\\') {
      index += 2;
      continue;
    }
    if (triple) {
      if (index + 2 < content.length &&
          content[index] == quote &&
          content[index + 1] == quote &&
          content[index + 2] == quote) {
        return index + 3;
      }
      index += 1;
      continue;
    }
    if (content[index] == quote) {
      return index + 1;
    }
    index += 1;
  }
  return content.length;
}

String? _relativeFilePath(Directory root, File file) {
  final rootPath = root.absolute.path;
  final filePath = file.absolute.path;
  final prefix = '$rootPath/';
  if (!filePath.startsWith(prefix)) {
    return null;
  }
  return filePath.substring(prefix.length);
}

String _pathBasename(String path) {
  final index = path.lastIndexOf('/');
  return index == -1 ? path : path.substring(index + 1);
}
