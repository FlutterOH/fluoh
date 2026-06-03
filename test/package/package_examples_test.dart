import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fluoh/src/cli/terminal_output.dart';
import 'package:fluoh/src/package/manifest/package_manifest.dart';
import 'package:fluoh/src/package/package_examples.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

void main() {
  test('removes generic flutter create templates from existing examples', () async {
    final environment = await createTestEnvironment();
    final repository = environment.workingDirectory;
    final packageRoot = Directory('${repository.path}/plugin');
    final example = Directory('${packageRoot.path}/example');
    await Directory('${example.path}/lib').create(recursive: true);
    await File('${example.path}/pubspec.yaml').writeAsString('''
name: plugin_example

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
''');
    final selectedSdk = Directory(
      '${environment.homeDirectory.path}/sdks/3.35.8-ohos-0.0.3',
    );
    await Directory('${selectedSdk.path}/bin').create(recursive: true);
    final flutter = File('${selectedSdk.path}/bin/flutter');
    await flutter.writeAsString('''
#!/bin/sh
if [ "\$1" = "create" ]; then
  mkdir -p ohos/entry/src/main/resources/base/profile
  mkdir -p test
  echo "include: package:flutter_lints/flutter.yaml" > analysis_options.yaml
  echo "void main() {}" > test/widget_test.dart
  echo "{build: true}" > ohos/entry/src/main/resources/base/profile/buildinfo.json5
  echo "{frames: true}" > ohos/entry/src/main/resources/base/profile/framesconfig.json
  exit 0
fi
exit 0
''');
    await _makeExecutable(flutter);
    final stdout = <String>[];
    final stderr = <String>[];

    final result = await preparePackageExample(
      environment: environment,
      repository: repository,
      package: const PackageManifestPackage(
        name: 'plugin',
        upstreamVersion: '1.0.0',
        version: '0.1.0',
        repositoryPath: 'plugin',
      ),
      sdkVersion: '3.35.8-ohos-0.0.3',
      stdout: stdout.add,
      stderr: stderr.add,
      output: TerminalOutput(stdout: stdout.add, stderr: stderr.add),
    );

    expect(result.prepared, isTrue);
    expect(File('${example.path}/analysis_options.yaml').existsSync(), isFalse);
    expect(File('${example.path}/test/widget_test.dart').existsSync(), isFalse);
    expect(Directory('${example.path}/test').existsSync(), isFalse);
    expect(
      File(
        '${example.path}/ohos/entry/src/main/resources/rawfile/buildinfo.json5',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        '${example.path}/ohos/entry/src/main/resources/rawfile/framesconfig.json',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        '${example.path}/ohos/entry/src/main/resources/base/profile/buildinfo.json5',
      ).existsSync(),
      isFalse,
    );
    expect(stderr, isEmpty);
  });

  test('preserves existing example analysis and test files', () async {
    final environment = await createTestEnvironment();
    final repository = environment.workingDirectory;
    final packageRoot = Directory('${repository.path}/plugin');
    final example = Directory('${packageRoot.path}/example');
    await Directory('${example.path}/lib').create(recursive: true);
    await Directory('${example.path}/test').create(recursive: true);
    await File('${example.path}/pubspec.yaml').writeAsString('''
name: plugin_example

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
''');
    await File(
      '${example.path}/analysis_options.yaml',
    ).writeAsString('include: package:custom_lints/custom.yaml\n');
    await File(
      '${example.path}/test/widget_test.dart',
    ).writeAsString('void main() => customTest();\n');
    final selectedSdk = Directory(
      '${environment.homeDirectory.path}/sdks/3.35.8-ohos-0.0.3',
    );
    await Directory('${selectedSdk.path}/bin').create(recursive: true);
    final flutter = File('${selectedSdk.path}/bin/flutter');
    await flutter.writeAsString('''
#!/bin/sh
if [ "\$1" = "create" ]; then
  mkdir -p ohos
  mkdir -p test
  echo "include: package:flutter_lints/flutter.yaml" > analysis_options.yaml
  echo "void main() {}" > test/widget_test.dart
  exit 0
fi
exit 0
''');
    await _makeExecutable(flutter);

    final result = await preparePackageExample(
      environment: environment,
      repository: repository,
      package: const PackageManifestPackage(
        name: 'plugin',
        upstreamVersion: '1.0.0',
        version: '0.1.0',
        repositoryPath: 'plugin',
      ),
      sdkVersion: '3.35.8-ohos-0.0.3',
      stdout: (_) {},
      stderr: (_) {},
      output: TerminalOutput(stdout: (_) {}, stderr: (_) {}),
    );

    expect(result.prepared, isTrue);
    expect(
      File('${example.path}/analysis_options.yaml').readAsStringSync(),
      'include: package:custom_lints/custom.yaml\n',
    );
    expect(
      File('${example.path}/test/widget_test.dart').readAsStringSync(),
      'void main() => customTest();\n',
    );
    expect(Directory('${example.path}/test').existsSync(), isTrue);
  });

  test('restores an existing example SDK link when OHOS setup fails', () async {
    final environment = await createTestEnvironment();
    final repository = environment.workingDirectory;
    final packageRoot = Directory('${repository.path}/plugin');
    final example = Directory('${packageRoot.path}/example');
    await Directory('${example.path}/lib').create(recursive: true);
    await File('${example.path}/pubspec.yaml').writeAsString('''
name: plugin_example

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
''');
    await File('${example.path}/fluoh.yaml').writeAsString('''
schema: 1
sdk:
  version: old-sdk
''');
    await File('${example.path}/.gitignore').writeAsString('existing\n');
    final oldSdk = Directory('${environment.homeDirectory.path}/old_sdk');
    await oldSdk.create(recursive: true);
    await Directory('${example.path}/.fluoh').create(recursive: true);
    await Link('${example.path}/.fluoh/flutter_sdk').create(oldSdk.path);
    final selectedSdk = Directory(
      '${environment.homeDirectory.path}/sdks/3.35.8-ohos-0.0.3',
    );
    await Directory('${selectedSdk.path}/bin').create(recursive: true);
    final flutter = File('${selectedSdk.path}/bin/flutter');
    await flutter.writeAsString('''
#!/bin/sh
exit 1
''');
    await _makeExecutable(flutter);
    final stdout = <String>[];
    final stderr = <String>[];

    await expectLater(
      preparePackageExample(
        environment: environment,
        repository: repository,
        package: const PackageManifestPackage(
          name: 'plugin',
          upstreamVersion: '1.0.0',
          version: '0.1.0',
          repositoryPath: 'plugin',
        ),
        sdkVersion: '3.35.8-ohos-0.0.3',
        stdout: stdout.add,
        stderr: stderr.add,
        output: TerminalOutput(stdout: stdout.add, stderr: stderr.add),
      ),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          contains('flutter create failed for plugin/example'),
        ),
      ),
    );

    expect(
      Link('${example.path}/.fluoh/flutter_sdk').targetSync(),
      oldSdk.path,
    );
    expect(File('${example.path}/fluoh.yaml').readAsStringSync(), '''
schema: 1
sdk:
  version: old-sdk
''');
    expect(File('${example.path}/.gitignore').readAsStringSync(), 'existing\n');
    expect(Directory('${example.path}/ohos').existsSync(), isFalse);
  });
}

Future<void> _makeExecutable(File file) async {
  final result = await Process.run('chmod', ['+x', file.path]);
  if (result.exitCode != 0) {
    fail('chmod +x ${file.path} failed:\n${result.stderr}');
  }
}
