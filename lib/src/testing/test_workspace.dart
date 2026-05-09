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

  final FlutterAdapterPackage? package;
  final String? skippedReason;

  bool get created => package != null;
}

class FlutterAdapterPackage {
  const FlutterAdapterPackage({
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
}) async {
  final terminal = output ?? TerminalOutput(stdout: stdout, stderr: stderr);
  final package = await findFlutterAdapterPackage(environment.workingDirectory);
  if (package == null) {
    final packageName = await _packageNameOrDirectory(
      environment.workingDirectory,
    );
    final reason = '$packageName is not a Flutter package.';
    terminal.skipped('Skipping fluoh test init: $reason');
    return FluohTestInitResult.skipped(reason);
  }

  final testDirectory = Directory(
    '${environment.workingDirectory.path}/fluoh_test',
  );
  if (await testDirectory.exists()) {
    if (!force) {
      throw UsageException(
        'fluoh_test already exists. Remove it or pass --force.',
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
  await _writeTestWorkspace(testDirectory, package);
  await _createExampleProject(
    environment: environment,
    flutter: flutter,
    testDirectory: testDirectory,
    package: package,
    stdout: stdout,
    stderr: stderr,
    output: terminal,
  );

  terminal.success('Created fluoh_test for ${package.name}.');
  terminal.next('Run "fluoh test run" before publishing the adapter.');
  terminal.next('Use fluoh_test/example for manual platform verification.');
  return FluohTestInitResult.created(package);
}

Future<int> runFluohTestWorkspace({
  required FluohEnvironment environment,
  required OutputWriter stdout,
  required OutputWriter stderr,
  TerminalOutput? output,
}) async {
  final terminal = output ?? TerminalOutput(stdout: stdout, stderr: stderr);
  final package = await findFlutterAdapterPackage(environment.workingDirectory);
  if (package == null) {
    final packageName = await _packageNameOrDirectory(
      environment.workingDirectory,
    );
    terminal.skipped(
      'Skipping fluoh test run: $packageName is not a Flutter package.',
    );
    return 0;
  }

  final testDirectory = Directory(
    '${environment.workingDirectory.path}/fluoh_test',
  );
  if (!await testDirectory.exists()) {
    throw UsageException('Missing fluoh_test. Run "fluoh test init".', '');
  }
  final pubspec = File('${testDirectory.path}/pubspec.yaml');
  if (!await pubspec.exists()) {
    throw UsageException(
      'Missing fluoh_test/pubspec.yaml. Run "fluoh test init".',
      '',
    );
  }

  final flutter = await _flutterExecutableForEnvironment(
    environment,
    output: terminal,
  );
  final packageTest = await _runAdapterPackageTests(
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

  terminal.step('Running fluoh_test pub get.');
  final pubGet = await _runProcess(
    flutter.path,
    ['pub', 'get'],
    workingDirectory: testDirectory,
    environment: environment,
    stdout: stdout,
    stderr: stderr,
  );
  if (pubGet != 0) {
    terminal.failure('fluoh_test pub get failed.');
    return pubGet;
  }

  terminal.step('Running fluoh_test tests.');
  final test = await _runProcess(
    flutter.path,
    ['test'],
    workingDirectory: testDirectory,
    environment: environment,
    stdout: stdout,
    stderr: stderr,
  );
  if (test != 0) {
    terminal.failure('fluoh_test failed.');
    return test;
  }

  terminal.success('fluoh_test passed.');
  return 0;
}

Future<int> _runAdapterPackageTests({
  required FluohEnvironment environment,
  required File flutter,
  required FlutterAdapterPackage package,
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

Future<FlutterAdapterPackage?> findFlutterAdapterPackage(
  Directory repository,
) async {
  final packagePath = await _adapterPackagePath(repository);
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
  return FlutterAdapterPackage(
    name: name,
    version: version,
    packagePath: packagePath,
    directory: directory,
    platforms: platforms,
    hasPublicLibrary: await publicLibrary.exists(),
  );
}

Future<String> _adapterPackagePath(Directory repository) async {
  final manifest = File('${repository.path}/fluoh.yaml');
  if (!await manifest.exists()) {
    return '.';
  }
  final yaml = loadYaml(await manifest.readAsString());
  if (yaml is! YamlMap) {
    return '.';
  }
  final package = yaml['package'];
  if (package is! YamlMap) {
    return '.';
  }
  final git = package['git'];
  if (git is! YamlMap) {
    return '.';
  }
  final path = git['path'];
  return path is String && path.isNotEmpty ? path : '.';
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
  final sdkTag = await readProjectSdkTag(environment.workingDirectory);
  if (sdkTag == null || sdkTag.isEmpty) {
    throw UsageException(
      'No SDK selected. Run "fluoh sdk use <version-or-series>".',
      '',
    );
  }

  final manager = SdkManager(environment);
  var sdkDirectory = manager.sdkDirectory(sdkTag);
  if (!await sdkDirectory.exists()) {
    final release = await manager.resolveRelease(sdkTag);
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
      'Selected SDK $sdkTag does not contain bin/flutter.',
      '',
    );
  }
  return flutter;
}

Future<void> _writeTestWorkspace(
  Directory testDirectory,
  FlutterAdapterPackage package,
) async {
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
  await File(
    '${testDirectory.path}/README.md',
  ).writeAsString(_testReadmeContent(package));
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
  required FlutterAdapterPackage package,
  required OutputWriter stdout,
  required OutputWriter stderr,
  required TerminalOutput output,
}) async {
  final example = Directory('${testDirectory.path}/example');
  output.step(
    'Creating fluoh_test/example for ${package.platforms.join(',')}.',
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
    throw UsageException('flutter create failed for fluoh_test/example.', '');
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
  required FlutterAdapterPackage package,
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

String _contractTestContent(FlutterAdapterPackage package) {
  final import = package.hasPublicLibrary
      ? "import 'package:${package.name}/${package.name}.dart' "
            'as package_under_test;'
      : null;
  return '''
// ignore_for_file: unused_import

import 'package:flutter_test/flutter_test.dart';
${import ?? ''}

void main() {
  test('${package.name} FlutterOH adaptation test harness is ready', () {
    expect(true, isTrue);
  });
}
''';
}

String _examplePubspecContent({
  required FlutterAdapterPackage package,
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

String _exampleMainContent(FlutterAdapterPackage package) {
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
        Text('Add package-specific buttons for the adapted capability here.'),
      ],
    );
  }
}
''';
}

String _testReadmeContent(FlutterAdapterPackage package) {
  return '''
# FlutterOH Adaptation Test

Package: `${package.name}`

## Automated Verification

Run from the adapter repository root:

```sh
fluoh test run
```

The command first runs package Flutter tests when `test/**/*_test.dart` exists, equivalent to `fluoh flutter test` in the package path, then runs the tests in this `fluoh_test` package with the Flutter OHOS SDK selected by `fluoh.yaml`.

## Manual Verification

Use `fluoh_test/example` as the small app for checking platform behavior manually. Add package-specific UI actions when the adapter needs real device validation.
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

Future<String> _packageNameOrDirectory(Directory repository) async {
  final packagePath = await _adapterPackagePath(repository);
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
