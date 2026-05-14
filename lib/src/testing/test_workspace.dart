import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import '../cli/fluoh_command_runner.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import '../pub/manifest/pubspec_package.dart';
import '../sdk/sdk_manager.dart';
import '../sdk/sdk_project_config.dart';

class FluohTestInitResult {
  const FluohTestInitResult.created(this.package) : skippedReason = null;

  const FluohTestInitResult.skipped(this.skippedReason) : package = null;

  final FlutterImplementationPackage? package;
  final String? skippedReason;

  bool get created => package != null;
}

class FlutterImplementationPackage {
  const FlutterImplementationPackage({
    required this.name,
    required this.version,
    required this.packagePath,
    required this.directory,
    required this.platforms,
    required this.hasPublicLibrary,
  });

  final String name;
  final String version;
  final String packagePath;
  final Directory directory;
  final List<String> platforms;
  final bool hasPublicLibrary;
}

Future<FluohTestInitResult> initializeFluohTestWorkspace({
  required FluohEnvironment environment,
  required OutputWriter stdout,
  required OutputWriter stderr,
  TerminalOutput? output,
  bool force = false,
  String? packageName,
}) async {
  final terminal = output ?? TerminalOutput(stdout: stdout, stderr: stderr);
  final package = await findFlutterImplementationPackage(
    environment.workingDirectory,
    packageName: packageName,
  );
  if (package == null) {
    final displayName = await _packageNameOrDirectory(
      environment.workingDirectory,
      packageName: packageName,
    );
    final reason = '$displayName is not a Flutter package.';
    terminal.skipped('Skipping fluoh test init: $reason');
    return FluohTestInitResult.skipped(reason);
  }

  final testDirectory = await _testWorkspaceDirectory(
    environment.workingDirectory,
    package,
  );
  final testPath = _testWorkspaceDisplayPath(
    environment.workingDirectory,
    testDirectory,
  );
  if (await testDirectory.exists()) {
    if (!force) {
      throw UsageException(
        '$testPath already exists. Remove it or pass --force.',
        '',
      );
    }
    await testDirectory.delete(recursive: true);
  }

  final flutter = await _flutterExecutableForEnvironment(
    environment,
    output: terminal,
  );
  await testDirectory.create(recursive: true);
  await _writeTestWorkspace(
    testDirectory,
    package,
    testWorkspacePath: testPath,
  );
  await _createExampleProject(
    environment: environment,
    flutter: flutter,
    testDirectory: testDirectory,
    testWorkspacePath: testPath,
    package: package,
    stdout: stdout,
    stderr: stderr,
    output: terminal,
  );

  terminal.success('Created $testPath for ${package.name}.');
  final runCommand = testPath == 'fluoh_test'
      ? 'fluoh test run'
      : 'fluoh test run --package ${package.name}';
  terminal.next('Run "$runCommand" before publishing the FlutterOH package.');
  terminal.next('Use $testPath/example for manual platform verification.');
  return FluohTestInitResult.created(package);
}

Future<int> runFluohTestWorkspace({
  required FluohEnvironment environment,
  required OutputWriter stdout,
  required OutputWriter stderr,
  TerminalOutput? output,
  String? packageName,
}) async {
  final terminal = output ?? TerminalOutput(stdout: stdout, stderr: stderr);
  final package = await findFlutterImplementationPackage(
    environment.workingDirectory,
    packageName: packageName,
  );
  if (package == null) {
    final displayName = await _packageNameOrDirectory(
      environment.workingDirectory,
      packageName: packageName,
    );
    terminal.skipped(
      'Skipping fluoh test run: $displayName is not a Flutter package.',
    );
    return 0;
  }

  final testDirectory = await _existingTestWorkspaceDirectory(
    environment.workingDirectory,
    package,
  );
  final testPath = _testWorkspaceDisplayPath(
    environment.workingDirectory,
    testDirectory,
  );
  if (!await testDirectory.exists()) {
    throw UsageException(
      'Missing $testPath. Run "fluoh test init --package ${package.name}".',
      '',
    );
  }
  final pubspec = File('${testDirectory.path}/pubspec.yaml');
  if (!await pubspec.exists()) {
    throw UsageException(
      'Missing $testPath/pubspec.yaml. Run '
          '"fluoh test init --package ${package.name}".',
      '',
    );
  }

  final flutter = await _flutterExecutableForEnvironment(
    environment,
    output: terminal,
  );
  final packageTest = await _runImplementationPackageTests(
    environment: environment,
    flutter: flutter,
    package: package,
    stdout: stdout,
    stderr: stderr,
    output: terminal,
  );
  if (packageTest != 0) {
    return packageTest;
  }

  terminal.step('Running $testPath pub get.');
  final pubGet = await _runProcess(
    flutter.path,
    ['pub', 'get'],
    workingDirectory: testDirectory,
    environment: environment,
    stdout: stdout,
    stderr: stderr,
  );
  if (pubGet != 0) {
    terminal.failure('$testPath pub get failed.');
    return pubGet;
  }

  terminal.step('Running $testPath tests.');
  final test = await _runProcess(
    flutter.path,
    ['test'],
    workingDirectory: testDirectory,
    environment: environment,
    stdout: stdout,
    stderr: stderr,
  );
  if (test != 0) {
    terminal.failure('$testPath failed.');
    return test;
  }

  terminal.success('$testPath passed.');
  return 0;
}

Future<List<Directory>> fluohTestWorkspaceDirectories(
  Directory repository,
) async {
  final directories = <Directory>[];
  final manifest = File('${repository.path}/fluoh.yaml');
  if (!await manifest.exists()) {
    return _testWorkspacePair(Directory('${repository.path}/fluoh_test'));
  }

  final yaml = loadYaml(await manifest.readAsString());
  final packages = yaml is YamlMap ? yaml['packages'] : null;
  if (packages is! YamlMap || packages.isEmpty) {
    return _testWorkspacePair(Directory('${repository.path}/fluoh_test'));
  }

  final useScoped = packages.length > 1;
  for (final entry in packages.entries) {
    final name = entry.key;
    final value = entry.value;
    if (name is! String || value is! YamlMap) {
      continue;
    }
    final packageRepository = value['repository'];
    final path = packageRepository is YamlMap
        ? packageRepository['path']
        : null;
    final workspace = useScoped || (path is String && path.isNotEmpty)
        ? Directory('${repository.path}/fluoh_test/$name')
        : Directory('${repository.path}/fluoh_test');
    directories.addAll(_testWorkspacePair(workspace));
  }
  return _dedupeDirectories(directories);
}

List<Directory> _testWorkspacePair(Directory workspace) {
  return [workspace, Directory('${workspace.path}/example')];
}

List<Directory> _dedupeDirectories(List<Directory> directories) {
  final seen = <String>{};
  return [
    for (final directory in directories)
      if (seen.add(directory.absolute.path)) directory,
  ];
}

Future<int> _runImplementationPackageTests({
  required FluohEnvironment environment,
  required File flutter,
  required FlutterImplementationPackage package,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required TerminalOutput output,
}) async {
  if (!await _hasFlutterTests(package.directory)) {
    output.skipped(
      'Skipping ${package.name} package tests: no test files found.',
    );
    return 0;
  }

  output.step('Running ${package.name} package pub get.');
  final pubGet = await _runProcess(
    flutter.path,
    ['pub', 'get'],
    workingDirectory: package.directory,
    environment: environment,
    stdout: stdout,
    stderr: stderr,
  );
  if (pubGet != 0) {
    output.failure('${package.name} package pub get failed.');
    return pubGet;
  }

  output.step('Running ${package.name} package Flutter tests.');
  final test = await _runProcess(
    flutter.path,
    ['test'],
    workingDirectory: package.directory,
    environment: environment,
    stdout: stdout,
    stderr: stderr,
  );
  if (test != 0) {
    output.failure('${package.name} package tests failed.');
    return test;
  }

  output.success('${package.name} package tests passed.');
  return 0;
}

Future<bool> _hasFlutterTests(Directory packageDirectory) async {
  final testDirectory = Directory('${packageDirectory.path}/test');
  if (!await testDirectory.exists()) {
    return false;
  }
  await for (final entity in testDirectory.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('_test.dart')) {
      return true;
    }
  }
  return false;
}

Future<FlutterImplementationPackage?> findFlutterImplementationPackage(
  Directory repository, {
  String? packageName,
}) async {
  final packagePath = await _implementationPackagePath(repository, packageName);
  final directory = packageDirectory(repository, packagePath);
  final pubspec = File('${directory.path}/pubspec.yaml');
  if (!await pubspec.exists()) {
    throw UsageException('Missing pubspec.yaml in $packagePath.', '');
  }

  final yaml = loadYaml(await pubspec.readAsString());
  if (yaml is! YamlMap) {
    throw UsageException('pubspec.yaml must contain a YAML map.', '');
  }

  final name = yaml['name'];
  final version = yaml['version'];
  if (name is! String || version is! String) {
    throw UsageException('pubspec.yaml must contain name and version.', '');
  }
  if (!_isFlutterPackage(yaml)) {
    return null;
  }

  final platforms = _platformsForExample(directory, yaml);
  final publicLibrary = File('${directory.path}/lib/$name.dart');
  return FlutterImplementationPackage(
    name: name,
    version: version,
    packagePath: packagePath,
    directory: directory,
    platforms: platforms,
    hasPublicLibrary: await publicLibrary.exists(),
  );
}

Future<String> _implementationPackagePath(
  Directory repository,
  String? packageName,
) async {
  final manifest = File('${repository.path}/fluoh.yaml');
  if (!await manifest.exists()) {
    return '.';
  }
  final yaml = loadYaml(await manifest.readAsString());
  if (yaml is! YamlMap) {
    return '.';
  }
  final packages = yaml['packages'];
  if (packages is! YamlMap) {
    return '.';
  }
  if (packageName != null && packageName.trim().isNotEmpty) {
    final package = packages[packageName.trim()];
    if (package is! YamlMap) {
      throw UsageException(
        'Package ${packageName.trim()} is not registered in fluoh.yaml.',
        '',
      );
    }
    final packageRepository = package['repository'];
    final path = packageRepository is YamlMap
        ? packageRepository['path']
        : null;
    return path is String && path.isNotEmpty ? path : '.';
  }
  if (packages.length != 1) {
    throw UsageException(
      'Multiple packages are registered in fluoh.yaml. Pass '
          '"--package <name>".',
      '',
    );
  }
  final package = packages.values.single;
  if (package is! YamlMap) {
    return '.';
  }
  final packageRepository = package['repository'];
  final path = packageRepository is YamlMap ? packageRepository['path'] : null;
  return path is String && path.isNotEmpty ? path : '.';
}

Future<Directory> _testWorkspaceDirectory(
  Directory repository,
  FlutterImplementationPackage package,
) async {
  if (await _usesScopedTestWorkspace(repository, package)) {
    return Directory('${repository.path}/fluoh_test/${package.name}');
  }
  return Directory('${repository.path}/fluoh_test');
}

Future<Directory> _existingTestWorkspaceDirectory(
  Directory repository,
  FlutterImplementationPackage package,
) async {
  final scoped = Directory('${repository.path}/fluoh_test/${package.name}');
  if (await File('${scoped.path}/pubspec.yaml').exists()) {
    return scoped;
  }
  if (await _usesScopedTestWorkspace(repository, package)) {
    return scoped;
  }

  final root = Directory('${repository.path}/fluoh_test');
  if (await _testWorkspaceTargetsPackage(root, package.name)) {
    return root;
  }
  return root;
}

Future<bool> _usesScopedTestWorkspace(
  Directory repository,
  FlutterImplementationPackage package,
) async {
  if (package.packagePath != '.') {
    return true;
  }

  final manifest = File('${repository.path}/fluoh.yaml');
  if (await manifest.exists()) {
    final yaml = loadYaml(await manifest.readAsString());
    final packages = yaml is YamlMap ? yaml['packages'] : null;
    if (packages is YamlMap && packages.length > 1) {
      return true;
    }
  }

  final root = Directory('${repository.path}/fluoh_test');
  return await File('${root.path}/pubspec.yaml').exists() &&
      !await _testWorkspaceTargetsPackage(root, package.name);
}

Future<bool> _testWorkspaceTargetsPackage(
  Directory testDirectory,
  String packageName,
) async {
  final pubspec = File('${testDirectory.path}/pubspec.yaml');
  if (!await pubspec.exists()) {
    return false;
  }
  final yaml = loadYaml(await pubspec.readAsString());
  if (yaml is! YamlMap) {
    return false;
  }
  final dependencies = yaml['dependencies'];
  return dependencies is YamlMap && dependencies[packageName] != null;
}

bool _isFlutterPackage(YamlMap pubspec) {
  final flutter = pubspec['flutter'];
  return flutter is YamlMap ||
      _hasFlutterSdkDependency(pubspec['dependencies']) ||
      _hasFlutterSdkDependency(pubspec['dev_dependencies']);
}

bool _hasFlutterSdkDependency(Object? dependencies) {
  if (dependencies is! YamlMap) {
    return false;
  }
  final flutter = dependencies['flutter'];
  return flutter is YamlMap && flutter['sdk'] == 'flutter';
}

List<String> _platformsForExample(Directory packageDirectory, YamlMap pubspec) {
  final platforms = <String>{};
  final flutter = pubspec['flutter'];
  final plugin = flutter is YamlMap ? flutter['plugin'] : null;
  final pluginPlatforms = plugin is YamlMap ? plugin['platforms'] : null;
  if (pluginPlatforms is YamlMap) {
    platforms.addAll(
      pluginPlatforms.keys.whereType<String>().where(_isFlutterCreatePlatform),
    );
  }

  for (final platform in _platformOrder) {
    if (Directory('${packageDirectory.path}/$platform').existsSync()) {
      platforms.add(platform);
    }
  }

  if (platforms.isEmpty) {
    platforms.addAll(['android', 'ios']);
  }
  platforms.add('ohos');
  return _platformOrder.where(platforms.contains).toList(growable: false);
}

bool _isFlutterCreatePlatform(String platform) =>
    _platformOrder.contains(platform);

const _platformOrder = [
  'android',
  'ios',
  'ohos',
  'web',
  'linux',
  'macos',
  'windows',
];

Future<File> _flutterExecutableForEnvironment(
  FluohEnvironment environment, {
  TerminalOutput? output,
}) async {
  final sdkVersion = await readProjectSdkVersion(environment.workingDirectory);
  if (sdkVersion == null || sdkVersion.isEmpty) {
    throw UsageException(
      'No SDK selected. Run "fluoh sdk use <version-or-series>".',
      '',
    );
  }

  final manager = SdkManager(environment);
  var sdkDirectory = manager.sdkDirectory(sdkVersion);
  if (!await sdkDirectory.exists()) {
    final release = await manager.resolveRelease(sdkVersion);
    sdkDirectory = output == null
        ? await manager.install(release)
        : await output.withProgress(
            'Installing Flutter OHOS SDK ${release.tag}; this may take a while.',
            () => manager.install(release),
          );
  }
  final flutter = File('${sdkDirectory.path}/bin/flutter');
  if (!await flutter.exists()) {
    throw UsageException(
      'Selected SDK $sdkVersion does not contain bin/flutter.',
      '',
    );
  }
  return flutter;
}

Future<void> _writeTestWorkspace(
  Directory testDirectory,
  FlutterImplementationPackage package, {
  required String testWorkspacePath,
}) async {
  await File('${testDirectory.path}/.gitignore').writeAsString('''
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
.pub/
.pub-cache/
build/
coverage/
local.properties
pubspec.lock
example/.dart_tool/
example/.flutter-plugins
example/.flutter-plugins-dependencies
example/.packages
example/.pub/
example/.pub-cache/
example/build/
example/coverage/
example/local.properties
example/pubspec.lock
''');
  await File('${testDirectory.path}/README.md').writeAsString(
    _testReadmeContent(package, testWorkspacePath: testWorkspacePath),
  );
  await File('${testDirectory.path}/pubspec.yaml').writeAsString(
    _testPubspecContent(
      package: package,
      dependencyPath: _relativeDirectoryPath(
        from: testDirectory,
        to: package.directory,
      ),
    ),
  );
  final tests = Directory('${testDirectory.path}/test');
  await tests.create(recursive: true);
  await File(
    '${tests.path}/contract_test.dart',
  ).writeAsString(_contractTestContent(package));
}

Future<void> _createExampleProject({
  required FluohEnvironment environment,
  required File flutter,
  required Directory testDirectory,
  required String testWorkspacePath,
  required FlutterImplementationPackage package,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required TerminalOutput output,
}) async {
  final example = Directory('${testDirectory.path}/example');
  output.step(
    'Creating $testWorkspacePath/example for ${package.platforms.join(',')}.',
  );
  final exitCode = await _runProcess(
    flutter.path,
    [
      'create',
      '--no-pub',
      '--project-name',
      'fluoh_test_example',
      '--platforms=${package.platforms.join(',')}',
      example.path,
    ],
    workingDirectory: environment.workingDirectory,
    environment: environment,
    stdout: stdout,
    stderr: stderr,
    forwardOutput: false,
  );
  if (exitCode != 0) {
    throw UsageException(
      'flutter create failed for $testWorkspacePath/example.',
      '',
    );
  }

  await Directory('${example.path}/lib').create(recursive: true);
  await File('${example.path}/pubspec.yaml').writeAsString(
    _examplePubspecContent(
      package: package,
      dependencyPath: _relativeDirectoryPath(
        from: example,
        to: package.directory,
      ),
    ),
  );
  await File(
    '${example.path}/lib/main.dart',
  ).writeAsString(_exampleMainContent(package));
}

Future<int> _runProcess(
  String executable,
  List<String> arguments, {
  required Directory workingDirectory,
  required FluohEnvironment environment,
  required OutputWriter stdout,
  required OutputWriter stderr,
  bool forwardOutput = true,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
    environment: environment.processEnvironment,
  );
  if (forwardOutput || result.exitCode != 0) {
    _writeProcessOutput(result.stdout, stdout);
    _writeProcessOutput(result.stderr, stderr);
  }
  return result.exitCode;
}

void _writeProcessOutput(Object? output, OutputWriter write) {
  if (output == null) {
    return;
  }
  final text = output.toString().trimRight();
  if (text.isEmpty) {
    return;
  }
  for (final line in text.split('\n')) {
    write(line);
  }
}

String _testPubspecContent({
  required FlutterImplementationPackage package,
  required String dependencyPath,
}) {
  return '''
name: ${package.name}_fluoh_test
publish_to: none

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
  ${package.name}:
    path: $dependencyPath

dev_dependencies:
  flutter_test:
    sdk: flutter
''';
}

String _contractTestContent(FlutterImplementationPackage package) {
  final import = package.hasPublicLibrary
      ? "import 'package:${package.name}/${package.name}.dart' "
            'as package_under_test;'
      : null;
  return '''
// ignore_for_file: unused_import

import 'package:flutter_test/flutter_test.dart';
${import ?? ''}

void main() {
  test('${package.name} FlutterOH implementation test harness is ready', () {
    expect(true, isTrue);
  });
}
''';
}

String _examplePubspecContent({
  required FlutterImplementationPackage package,
  required String dependencyPath,
}) {
  return '''
name: fluoh_test_example
publish_to: none

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
  ${package.name}:
    path: $dependencyPath

dev_dependencies:
  flutter_test:
    sdk: flutter

flutter:
  uses-material-design: true
''';
}

String _exampleMainContent(FlutterImplementationPackage package) {
  return '''
import 'package:flutter/material.dart';

void main() {
  runApp(const FluohTestExampleApp());
}

class FluohTestExampleApp extends StatelessWidget {
  const FluohTestExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('FlutterOH Verify')),
        body: const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: _VerifyPage(),
          ),
        ),
      ),
    );
  }
}

class _VerifyPage extends StatelessWidget {
  const _VerifyPage();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        Text('Package: ${package.name}'),
        SizedBox(height: 12),
        Text('Use this page for manual OHOS, Android, and iOS checks.'),
        SizedBox(height: 24),
        Text('Add package-specific buttons for the OHOS implementation here.'),
      ],
    );
  }
}
''';
}

String _testReadmeContent(
  FlutterImplementationPackage package, {
  required String testWorkspacePath,
}) {
  final runCommand = testWorkspacePath == 'fluoh_test'
      ? 'fluoh test run'
      : 'fluoh test run --package ${package.name}';
  return '''
# FlutterOH Implementation Test

Package: `${package.name}`

## Automated Verification

Run from the FlutterOH pub repository root:

```sh
$runCommand
```

The command first runs package Flutter tests when `test/**/*_test.dart` exists, equivalent to `fluoh flutter test` in the package path, then runs the tests in this `$testWorkspacePath` package with the Flutter OHOS SDK selected by `fluoh.yaml`.

## Manual Verification

Use `$testWorkspacePath/example` as the small app for checking platform behavior manually. Add package-specific UI actions when the implementation needs real device validation.
''';
}

String _relativeDirectoryPath({
  required Directory from,
  required Directory to,
}) {
  final fromParts = _pathParts(from.absolute.path);
  final toParts = _pathParts(to.absolute.path);
  var common = 0;
  while (common < fromParts.length &&
      common < toParts.length &&
      fromParts[common] == toParts[common]) {
    common += 1;
  }
  final parts = [
    for (var index = common; index < fromParts.length; index += 1) '..',
    ...toParts.skip(common),
  ];
  return parts.isEmpty ? '.' : parts.join(Platform.pathSeparator);
}

List<String> _pathParts(String path) {
  final separator = Platform.pathSeparator;
  final trimmed = path.endsWith(separator)
      ? path.substring(0, path.length - 1)
      : path;
  return trimmed.split(separator).where((part) => part.isNotEmpty).toList();
}

Future<String> _packageNameOrDirectory(
  Directory repository, {
  String? packageName,
}) async {
  final packagePath = await _implementationPackagePath(repository, packageName);
  final pubspec = File(
    '${packageDirectory(repository, packagePath).path}/pubspec.yaml',
  );
  if (!await pubspec.exists()) {
    return repository.path;
  }
  final yaml = loadYaml(await pubspec.readAsString());
  if (yaml is YamlMap && yaml['name'] is String) {
    return yaml['name'] as String;
  }
  return repository.path;
}

String _testWorkspaceDisplayPath(Directory repository, Directory directory) {
  final root = repository.absolute.path;
  final path = directory.absolute.path;
  if (path == root) {
    return '.';
  }
  if (path.startsWith('$root${Platform.pathSeparator}')) {
    return path.substring(root.length + 1);
  }
  return path;
}
