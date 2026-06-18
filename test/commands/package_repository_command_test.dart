import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fluoh/fluoh.dart';
import 'package:fluoh/src/cli/terminal_output.dart';
import 'package:fluoh/src/package/commands/package_command.dart';
import 'package:fluoh/src/package/manifest/package_manifest.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';
import '../helpers/package_test_context.dart';

part 'package_repository_core_part.dart';
part 'package_repository_selection_part.dart';
part 'package_repository_docs_part.dart';
part 'package_repository_add_part.dart';
part 'package_repository_validation_part.dart';

void main() {
  _registerPackageRepositoryCoreTests();
  _registerPackageRepositorySelectionTests();
  _registerPackageRepositoryDocsTests();
  _registerPackageRepositoryAddTests();
  _registerPackageRepositoryValidationTests();
}

class _ContextPackage {
  const _ContextPackage({
    required this.name,
    required this.version,
    required this.path,
  });

  final String name;
  final String version;
  final String path;

  String get examplePath => path == '.' ? 'example' : '$path/example';

  String get verifyCommand =>
      path == '.' ? 'fluoh verify' : 'fluoh verify --package $name';

  String get nextCommand => 'fluoh package next --package $name';

  String get releaseCommand => path == '.'
      ? 'fluoh package release'
      : 'fluoh package release --package $name';

  String get releaseCheckCommand => path == '.'
      ? 'fluoh package check'
      : 'fluoh package check --package $name';
}

void _expectPackageContext(
  String content, {
  required List<_ContextPackage> packages,
}) {
  _expectMarkdownHeadings(content, [
    '# FlutterOH Package Context',
    if (packages.length > 1) '## Packages' else '## Package',
    '## Ownership',
    '## Library Surface',
    '## Fluoh Workflow',
    '## Delivery Gates',
    '## FlutterOH Release History',
  ]);
  _expectContainsAll(content, [
    'Generated quick context for the fluoh skill',
    'use fluoh CLI JSON and `nextAction` for workflow state',
    'fluoh.yaml',
    '`FLUOH.md` is a generated index',
    '`doc/fluoh/<package>/spec.md` is the branch-local contract',
    '`doc/fluoh/<package>/scope.yaml` records support decisions',
    'Upstream README and agent policy files are repository-owned',
    'fluoh does not create, rewrite, or stage them as generated support context',
    'Public Dart API',
    'platform interface',
    'method-channel names',
    'Existing platform implementations that are present',
    'Example app flows',
    'permission prompts',
    'OHOS/OpenHarmony',
    'fluoh package next',
    'fluoh verify',
    'build/run/drive commands printed by fluoh JSON',
    'fluoh package check',
    '.fluoh/tasks/',
    'FlutterOH Release History',
    'TODO: Replace this generated placeholder',
    '--json',
  ]);
  if (packages.length > 1) {
    _expectContainsAll(content, ['## Packages']);
  }

  for (final package in packages) {
    _expectContainsAll(content, [
      package.name,
      package.version,
      package.examplePath,
      package.nextCommand,
      package.verifyCommand,
      package.releaseCheckCommand,
      package.releaseCommand,
      'Spec: `doc/fluoh/${package.name}/spec.md`',
      'Support scope: `doc/fluoh/${package.name}/scope.yaml`',
      'doc/fluoh/${package.name}/scope.yaml',
    ]);
    if (package.path != '.') {
      expect(content, contains(package.path));
    } else {
      expect(content, contains('package'));
    }
  }
}

void _expectChangelogEntry(String content, String tag) {
  final headingMatch = RegExp(
    '^#{2,6} ${RegExp.escape(tag)}\$',
    multiLine: true,
  ).firstMatch(content);
  expect(headingMatch, isNotNull, reason: 'Expected release history $tag.');
  final start = headingMatch!.start;
  final heading = headingMatch.group(0)!;

  final next = RegExp(
    r'\n#{2,6} ',
  ).firstMatch(content.substring(start + heading.length));
  final end = next == null
      ? content.length
      : start + heading.length + next.start;
  final entry = content.substring(start + heading.length, end).trim();
  expect(entry, isNotEmpty);
  expect(entry.split('\n').any((line) => line.trim().startsWith('- ')), isTrue);
}

void _expectMarkdownHeadings(String content, Iterable<String> expected) {
  final headings = content
      .split('\n')
      .where((line) => line.startsWith('#'))
      .toSet();
  for (final heading in expected) {
    expect(headings, contains(heading), reason: 'Missing heading $heading.');
  }
}

void _expectContainsAll(String content, Iterable<String> expected) {
  for (final value in expected) {
    expect(content, contains(value), reason: 'Expected to find "$value".');
  }
}

void _expectWrappedContainsAll(String content, Iterable<String> expected) {
  final normalizedContent = _normalizeOutput(content);
  for (final value in expected) {
    expect(
      normalizedContent,
      contains(_normalizeOutput(value)),
      reason: 'Expected to find "$value".',
    );
  }
}

String _normalizeOutput(String value) {
  return value
      .replaceAll(RegExp(r'(?<=[/-])\s+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Future<void> _addWorkspacePackage(
  Directory repository, {
  required String path,
  required String name,
  required String version,
}) async {
  final package = Directory('${repository.path}/$path');
  await package.create(recursive: true);
  await File('${package.path}/pubspec.yaml').writeAsString('''
name: $name
version: $version

environment:
  sdk: ^3.0.0
''');
  await runGit(repository, ['add', path]);
  await runGit(repository, ['commit', '-m', 'Add $name fixture']);
}

Future<void> _addWorkspaceFlutterPackage(
  Directory repository, {
  required String path,
  required String name,
  required String version,
}) async {
  final package = Directory('${repository.path}/$path');
  await Directory('${package.path}/lib').create(recursive: true);
  await Directory('${package.path}/example/lib').create(recursive: true);
  await File('${package.path}/pubspec.yaml').writeAsString('''
name: $name
version: $version

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
''');
  await File(
    '${package.path}/lib/$name.dart',
  ).writeAsString('library $name;\n');
  await File('${package.path}/example/pubspec.yaml').writeAsString('''
name: ${name}_example

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
  $name:
    path: ..

dev_dependencies:
  flutter_test:
    sdk: flutter
''');
  await File('${package.path}/example/lib/main.dart').writeAsString('''
import 'package:flutter/widgets.dart';

void main() {
  runApp(const Placeholder());
}
''');
  await runGit(repository, ['add', path]);
  await runGit(repository, ['commit', '-m', 'Add $name Flutter fixture']);
}

Future<Directory> _createPackageRepositorySdkSource(
  Directory parent, {
  required String logName,
  String? requiredCreateOrg,
}) async {
  final source = Directory('${parent.path}/flutter_sdk_source_$logName');
  final sdkRepository = Directory('${parent.path}/flutter_sdk_$logName');
  await sdkRepository.create(recursive: true);
  await _runProcess('git', ['init', '--initial-branch=main'], sdkRepository);
  await _runProcess('git', [
    'config',
    'user.email',
    'fixture@example.com',
  ], sdkRepository);
  await _runProcess('git', ['config', 'user.name', 'Fixture'], sdkRepository);
  final flutter = File('${sdkRepository.path}/bin/flutter');
  await flutter.parent.create(recursive: true);
  await flutter.writeAsString(
    _fakeFlutterScript(
      '${parent.path}/$logName',
      requiredCreateOrg: requiredCreateOrg,
    ),
  );
  await _runProcess('chmod', ['+x', flutter.path], sdkRepository);
  await File('${sdkRepository.path}/README.md').writeAsString('# SDK\n');
  await _runProcess('git', ['add', '.'], sdkRepository);
  await _runProcess('git', ['commit', '-m', 'Initial SDK'], sdkRepository);
  await _runProcess('git', ['tag', '3.35.8-ohos-0.0.3'], sdkRepository);
  await writeSdkSourceFixture(
    source,
    sdkRepository: sdkRepository.path,
    releases: {'3.35.8-ohos-0.0.3': 'stable'},
  );
  return source;
}

String _fakeFlutterScript(String logPath, {String? requiredCreateOrg}) {
  final requiredOrg = requiredCreateOrg ?? '';
  return '''
#!/bin/sh
printf "%s::%s\\n" "\$(pwd)" "\$*" >> "$logPath"
if [ "\$1" = "create" ]; then
  printf "flutter create stdout\\n"
  printf "flutter create stderr\\n" >&2
  target=""
  platforms=""
  org=""
  project_name=""
  while [ "\$#" -gt 0 ]; do
    case "\$1" in
      --template=*) ;;
      --template) shift ;;
      --platforms=*) platforms="\${1#--platforms=}" ;;
      --org=*) org="\${1#--org=}" ;;
      --org) shift; org="\$1" ;;
      --project-name) shift; project_name="\$1" ;;
      --no-pub) ;;
      create) ;;
      *) target="\$1" ;;
    esac
    shift
  done
  if [ "$requiredOrg" != "" ] && [ "\$org" != "$requiredOrg" ]; then
    printf "expected --org $requiredOrg, got %s\\n" "\$org" >&2
    exit 64
  fi
  mkdir -p "\$target/lib"
  if [ ! -f "\$target/pubspec.yaml" ]; then
    printf "name: %s\\nversion: 0.1.0\\nenvironment:\\n  sdk: '>=3.0.0 <4.0.0'\\ndependencies:\\n  flutter:\\n    sdk: flutter\\n" "\$project_name" > "\$target/pubspec.yaml"
  fi
  old_ifs="\$IFS"
  IFS=,
  for platform in \$platforms; do
    mkdir -p "\$target/\$platform"
    printf "{}\\n" > "\$target/\$platform/build-profile.json5"
  done
  IFS="\$old_ifs"
fi
exit 0
''';
}

Future<void> _addAmbiguousExampleOrganizations(Directory repo) async {
  await Directory(
    '${repo.path}/example/android/app/src/main',
  ).create(recursive: true);
  await File(
    '${repo.path}/example/android/app/src/main/AndroidManifest.xml',
  ).writeAsString('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="io.flutter.plugins.cameraExample">
</manifest>
''');
  await Directory(
    '${repo.path}/example/ios/Runner.xcodeproj',
  ).create(recursive: true);
  await File(
    '${repo.path}/example/ios/Runner.xcodeproj/project.pbxproj',
  ).writeAsString('''
{
  PRODUCT_BUNDLE_IDENTIFIER = dev.flutter.plugins.cameraExample;
}
''');
  await _runProcess('git', ['add', '.'], repo);
  await _runProcess('git', [
    'commit',
    '-m',
    'Add example platform metadata',
  ], repo);
}

Future<Directory> _createUpstreamFlutterPluginRepository(Directory repo) async {
  await repo.create(recursive: true);
  await _runProcess('git', ['init', '--initial-branch=main'], repo);
  await _runProcess('git', [
    'config',
    'user.email',
    'fixture@example.com',
  ], repo);
  await _runProcess('git', ['config', 'user.name', 'Fixture'], repo);
  await Directory('${repo.path}/lib').create(recursive: true);
  await Directory('${repo.path}/example/lib').create(recursive: true);
  await File('${repo.path}/lib/camera.dart').writeAsString('library camera;\n');
  await File('${repo.path}/pubspec.yaml').writeAsString('''
name: camera
version: 0.11.0

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter

flutter:
  plugin:
    platforms:
      android:
        package: dev.flutter.camera
        pluginClass: CameraPlugin
      ios:
        pluginClass: CameraPlugin
''');
  await File('${repo.path}/example/pubspec.yaml').writeAsString('''
name: camera_example

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
  camera:
    path: ..

dev_dependencies:
  flutter_test:
    sdk: flutter
''');
  await File('${repo.path}/example/lib/main.dart').writeAsString('''
import 'package:flutter/widgets.dart';

void main() {
  runApp(const Placeholder());
}
''');
  await File('${repo.path}/LICENSE').writeAsString(_testLicenseContent);
  await _runProcess('git', ['add', '.'], repo);
  await _runProcess('git', ['commit', '-m', 'Initial Flutter plugin'], repo);
  return repo;
}

Future<Directory> _createFederatedWorkspaceRepository(Directory repo) async {
  await repo.create(recursive: true);
  await _runProcess('git', ['init', '--initial-branch=main'], repo);
  await _runProcess('git', [
    'config',
    'user.email',
    'fixture@example.com',
  ], repo);
  await _runProcess('git', ['config', 'user.name', 'Fixture'], repo);
  await _writeFederatedPackage(
    repo,
    path: 'packages/path_provider/path_provider',
    name: 'path_provider',
    version: '2.1.0',
    defaultPackages: const {
      'android': 'path_provider_android',
      'ios': 'path_provider_foundation',
    },
  );
  await _writePlainPackage(
    repo,
    path: 'packages/path_provider/path_provider_android',
    name: 'path_provider_android',
    version: '2.1.0',
  );
  await _writePlainPackage(
    repo,
    path: 'packages/path_provider/path_provider_foundation',
    name: 'path_provider_foundation',
    version: '2.1.0',
  );
  await File('${repo.path}/README.md').writeAsString('# federated workspace\n');
  await File('${repo.path}/LICENSE').writeAsString(_testLicenseContent);
  await _runProcess('git', ['add', '.'], repo);
  await _runProcess('git', [
    'commit',
    '-m',
    'Initial federated workspace',
  ], repo);
  return repo;
}

Future<void> _writeFederatedPackage(
  Directory repo, {
  required String path,
  required String name,
  required String version,
  required Map<String, String> defaultPackages,
}) async {
  final directory = Directory('${repo.path}/$path');
  await Directory('${directory.path}/lib').create(recursive: true);
  final platforms = defaultPackages.entries.map((entry) {
    return '''
      ${entry.key}:
        default_package: ${entry.value}
''';
  }).join();
  await File('${directory.path}/pubspec.yaml').writeAsString('''
name: $name
version: $version

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter

flutter:
  plugin:
    platforms:
$platforms
''');
  await File(
    '${directory.path}/lib/$name.dart',
  ).writeAsString('library $name;\n');
}

Future<void> _writePlainPackage(
  Directory repo, {
  required String path,
  required String name,
  required String version,
}) async {
  final directory = Directory('${repo.path}/$path');
  await Directory('${directory.path}/lib').create(recursive: true);
  await File('${directory.path}/pubspec.yaml').writeAsString('''
name: $name
version: $version

environment:
  sdk: ^3.0.0
''');
  await File(
    '${directory.path}/lib/$name.dart',
  ).writeAsString('library $name;\n');
}

const _testLicenseContent = '''
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software.
''';

Future<void> _runProcess(
  String executable,
  List<String> arguments,
  Directory workingDirectory,
) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
  );
  if (result.exitCode != 0) {
    fail('$executable ${arguments.join(' ')} failed:\n${result.stderr}');
  }
}
