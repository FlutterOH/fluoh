import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/fluoh_command_runner.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import '../schema/yaml_utils.dart';
import '../sdk/flutter_runner.dart';
import '../sdk/sdk_manager.dart';
import '../sdk/sdk_project_environment.dart';
import 'manifest/package_manifest.dart';
import 'manifest/pubspec_package.dart';

/// Result of preparing a package example for FlutterOH verification.
class PackageExampleSetupResult {
  /// Creates an example setup result.
  const PackageExampleSetupResult({
    required this.packageName,
    required this.example,
    required this.prepared,
    this.reason,
    this.rollbackSnapshot,
  });

  /// Package name associated with the example.
  final String packageName;

  /// Example directory.
  final Directory example;

  /// Whether the example was prepared.
  final bool prepared;

  /// Skip reason when [prepared] is false.
  final String? reason;

  /// Snapshot that can roll back preparation changes.
  final PackageExampleSnapshot? rollbackSnapshot;
}

/// Prepares a package example with selected SDK metadata and OHOS platform.
Future<PackageExampleSetupResult> preparePackageExample({
  required FluohEnvironment environment,
  required Directory repository,
  required PackageManifestPackage package,
  required String sdkVersion,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required TerminalOutput output,
  Directory? sdkDirectory,
}) async {
  final packageRoot = packageDirectory(repository, package.repositoryPath);
  final example = Directory('${packageRoot.path}/example');
  final pubspec = File('${example.path}/pubspec.yaml');
  if (!await pubspec.exists()) {
    return _skipped(package, example, 'no Flutter example found');
  }

  final pubspecContent = await pubspec.readAsString();
  if (!_isFlutterPubspec(pubspecContent)) {
    return _skipped(package, example, 'example is not a Flutter project');
  }

  final snapshot = await PackageExampleSnapshot.capture(example);
  try {
    final exampleEnvironment = FluohEnvironment(
      homeDirectory: environment.homeDirectory,
      workingDirectory: example,
      processEnvironment: environment.processEnvironment,
    );
    final selectedSdk =
        sdkDirectory ?? SdkManager(environment).sdkDirectory(sdkVersion);
    await SdkProjectEnvironment(exampleEnvironment).writeSdkVersion(sdkVersion);
    await SdkProjectEnvironment(exampleEnvironment).linkIdeSdk(selectedSdk);
    await _ensureExampleGitIgnore(example);

    if (!await Directory('${example.path}/ohos').exists()) {
      output.step(
        'Adding OHOS platform to ${_relativePath(repository, example)}',
      );
      final result = await runSelectedFlutter(
        environment: exampleEnvironment,
        arguments: const ['create', '--no-pub', '--platforms=ohos', '.'],
        workingDirectory: example,
        stdout: stdout,
        stderr: stderr,
        output: output,
      );
      if (result != 0) {
        throw UsageException(
          'flutter create failed for ${_relativePath(repository, example)}.',
          '',
        );
      }
    }

    if (!await Directory('${example.path}/ohos').exists()) {
      throw UsageException(
        'flutter create did not create ohos in '
            '${_relativePath(repository, example)}.',
        '',
      );
    }

    output.success(
      'Prepared example for ${package.name} at '
      '${_relativePath(repository, example)}',
    );
    return PackageExampleSetupResult(
      packageName: package.name,
      example: example,
      prepared: true,
      rollbackSnapshot: snapshot,
    );
  } catch (_) {
    await snapshot.restore();
    rethrow;
  }
}

/// Returns existing package example directories.
Future<List<Directory>> packageExampleDirectories({
  required Directory repository,
  required Iterable<PackageManifestPackage> packages,
  bool flutterOnly = true,
}) async {
  final examples = <Directory>[];
  for (final package in packages) {
    final example = Directory(
      '${packageDirectory(repository, package.repositoryPath).path}/example',
    );
    final pubspec = File('${example.path}/pubspec.yaml');
    if (!await pubspec.exists()) {
      continue;
    }
    if (flutterOnly && !_isFlutterPubspec(await pubspec.readAsString())) {
      continue;
    }
    examples.add(example);
  }
  return examples;
}

/// Returns whether [directory] contains a Flutter package pubspec.
Future<bool> isFlutterPackageDirectory(Directory directory) async {
  final pubspec = File('${directory.path}/pubspec.yaml');
  if (!await pubspec.exists()) {
    return false;
  }
  return _isFlutterPubspec(await pubspec.readAsString());
}

/// Returns whether [directory] contains Dart package tests.
Future<bool> hasPackageTests(Directory directory) async {
  final testRoot = Directory('${directory.path}/test');
  if (!await testRoot.exists()) {
    return false;
  }
  await for (final entity in testRoot.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File && entity.path.endsWith('_test.dart')) {
      return true;
    }
  }
  return false;
}

/// Returns [directory] as a repository-relative path.
String packageRelativePath(Directory repository, Directory directory) {
  return _relativePath(repository, directory);
}

PackageExampleSetupResult _skipped(
  PackageManifestPackage package,
  Directory example,
  String reason,
) {
  return PackageExampleSetupResult(
    packageName: package.name,
    example: example,
    prepared: false,
    reason: reason,
  );
}

bool _isFlutterPubspec(String content) {
  final yaml = parseYamlMap(content, label: 'pubspec.yaml');
  return _containsSdkFlutter(yaml['dependencies'], 'flutter') ||
      _containsSdkFlutter(yaml['dev_dependencies'], 'flutter_test') ||
      yaml.containsKey('flutter');
}

bool _containsSdkFlutter(Object? section, String packageName) {
  if (section is! Map<String, Object?>) {
    return false;
  }
  final dependency = section[packageName];
  return dependency is Map<String, Object?> && dependency['sdk'] == 'flutter';
}

Future<void> _ensureExampleGitIgnore(Directory example) async {
  for (final entry in const ['.fluoh/', 'flutter_*.log', 'local.properties']) {
    await _ensureGitIgnoreEntry(example, entry);
  }
}

Future<void> _ensureGitIgnoreEntry(Directory directory, String entry) async {
  final gitignore = File('${directory.path}/.gitignore');
  if (!await gitignore.exists()) {
    await gitignore.writeAsString('$entry\n');
    return;
  }

  final content = await gitignore.readAsString();
  final exists = content
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .contains(entry);
  if (exists) {
    return;
  }

  final separator = content.isEmpty || content.endsWith('\n') ? '' : '\n';
  await gitignore.writeAsString('$content$separator$entry\n');
}

String _relativePath(Directory rootDirectory, Directory directory) {
  final root = rootDirectory.absolute.path;
  final path = directory.absolute.path;
  if (path == root) {
    return '.';
  }
  if (path.startsWith('$root${Platform.pathSeparator}')) {
    return path.substring(root.length + 1);
  }
  return path;
}

/// Snapshot of package example files that fluoh may modify.
class PackageExampleSnapshot {
  /// Creates an example snapshot.
  const PackageExampleSnapshot({
    required this.example,
    required this.files,
    required this.fluohDirectoryExisted,
    required this.ohosDirectoryExisted,
    required this.flutterSdkLinkTarget,
  });

  /// Example directory captured by the snapshot.
  final Directory example;

  /// Captured file contents keyed by relative path.
  final Map<String, String?> files;

  /// Whether `.fluoh/` existed before capture.
  final bool fluohDirectoryExisted;

  /// Whether `ohos/` existed before capture.
  final bool ohosDirectoryExisted;

  /// Existing `.fluoh/flutter_sdk` symlink target.
  final String? flutterSdkLinkTarget;

  /// Captures restorable example state.
  static Future<PackageExampleSnapshot> capture(Directory example) async {
    final files = <String, String?>{};
    for (final path in const ['.gitignore', 'fluoh.yaml', 'local.properties']) {
      final file = File('${example.path}/$path');
      files[path] = await file.exists() ? await file.readAsString() : null;
    }
    final flutterSdkLink = Link('${example.path}/.fluoh/flutter_sdk');
    final flutterSdkLinkType = await FileSystemEntity.type(
      flutterSdkLink.path,
      followLinks: false,
    );
    final flutterSdkLinkTarget = flutterSdkLinkType == FileSystemEntityType.link
        ? await flutterSdkLink.target()
        : null;
    return PackageExampleSnapshot(
      example: example,
      files: files,
      fluohDirectoryExisted: await Directory('${example.path}/.fluoh').exists(),
      ohosDirectoryExisted: await Directory('${example.path}/ohos').exists(),
      flutterSdkLinkTarget: flutterSdkLinkTarget,
    );
  }

  /// Restores captured example files, directories, and Flutter SDK symlink.
  Future<void> restore() async {
    for (final entry in files.entries) {
      final file = File('${example.path}/${entry.key}');
      final content = entry.value;
      if (content == null) {
        if (await file.exists()) {
          await file.delete();
        }
      } else {
        await file.writeAsString(content);
      }
    }

    await _restoreFlutterSdkLink();
    final ohosDirectory = Directory('${example.path}/ohos');
    if (!ohosDirectoryExisted && await ohosDirectory.exists()) {
      await ohosDirectory.delete(recursive: true);
    }
    final fluohDirectory = Directory('${example.path}/.fluoh');
    if (!fluohDirectoryExisted && await fluohDirectory.exists()) {
      await fluohDirectory.delete(recursive: true);
    }
  }

  Future<void> _restoreFlutterSdkLink() async {
    final flutterSdkLink = Link('${example.path}/.fluoh/flutter_sdk');
    final type = await FileSystemEntity.type(
      flutterSdkLink.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.link) {
      await flutterSdkLink.delete();
    }
    final target = flutterSdkLinkTarget;
    if (target != null) {
      await flutterSdkLink.parent.create(recursive: true);
      await flutterSdkLink.create(target);
    }
  }
}
