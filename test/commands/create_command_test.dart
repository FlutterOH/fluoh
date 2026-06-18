import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

void main() {
  test(
    'creates a project with the latest stable SDK and forwards arguments',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createCreateCommandSdkSource(
        environment.homeDirectory,
        versions: const ['3.35.8-ohos-0.0.3', '3.36.1-ohos-0.0.1'],
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'enable', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          [
            'create',
            '--org',
            'com.example',
            '--platforms=android,ios,ohos',
            'demo_app',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final demo = Directory('${environment.workingDirectory.path}/demo_app');
      expect(File('${demo.path}/pubspec.yaml').existsSync(), isTrue);
      expect(
        File('${demo.path}/fluoh.yaml').readAsStringSync(),
        contains('version: 3.36.1-ohos-0.0.1'),
      );
      expect(Link('${demo.path}/.fluoh/flutter_sdk').existsSync(), isTrue);
      expect(
        File(
          '${environment.workingDirectory.path}/flutter_create_invocations.txt',
        ).readAsStringSync(),
        contains(
          'create --org com.example --platforms=android,ios,ohos demo_app',
        ),
      );
      expect(stdout.join('\n'), contains('flutter create stdout'));
      expect(stderr.join('\n'), contains('flutter create stderr'));
    },
  );

  test(
    'honors explicit --sdk before forwarding flutter create arguments',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createCreateCommandSdkSource(
        environment.homeDirectory,
        versions: const ['3.35.8-ohos-0.0.3', '3.36.1-ohos-0.0.1'],
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'enable', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          ['create', '--sdk', '3.35', '--', '--template=app', 'older_app'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final demo = Directory('${environment.workingDirectory.path}/older_app');
      expect(
        File('${demo.path}/fluoh.yaml').readAsStringSync(),
        contains('version: 3.35.8-ohos-0.0.3'),
      );
      expect(
        File(
          '${environment.workingDirectory.path}/flutter_create_invocations.txt',
        ).readAsStringSync(),
        contains('create --template=app older_app'),
      );
      expect(stderr.join('\n'), contains('flutter create stderr'));
    },
  );

  test(
    'prints machine-readable create report without streaming Flutter output',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createCreateCommandSdkSource(
        environment.homeDirectory,
        versions: const ['3.36.1-ohos-0.0.1'],
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'enable', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          [
            'create',
            '--json',
            '--org',
            'com.example',
            '--platforms=android,ios,ohos',
            'json_app',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final report = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(report, containsPair('schema', 1));
      expect(report, containsPair('command', 'create'));
      expect(report, containsPair('ok', true));
      expect(report, containsPair('exitCode', 0));
      expect(report, containsPair('metadataWritten', true));
      expect(report['sdk'], {
        'version': '3.36.1-ohos-0.0.1',
        'path': '${environment.homeDirectory.path}/sdks/3.36.1-ohos-0.0.1',
      });
      expect(report['project'], {
        'path': '${environment.workingDirectory.path}/json_app',
      });
      expect(
        report['ideFlutterSdkLink'],
        endsWith('/json_app/.fluoh/flutter_sdk'),
      );

      final flutter = report['flutter'] as Map<String, Object?>;
      expect(
        flutter['arguments'],
        containsAllInOrder([
          'create',
          '--org',
          'com.example',
          '--platforms=android,ios,ohos',
          'json_app',
        ]),
      );
      expect(flutter, containsPair('exitCode', 0));
      expect(flutter['stdoutTail'], contains('flutter create stdout'));
      expect(flutter['stderrTail'], contains('flutter create stderr'));
      expect(stderr, isEmpty);
    },
  );

  test('prints machine-readable usage errors for create', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['create', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'create'));
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 64));
    expect(report['error'], {
      'type': 'usage',
      'message': 'Expected arguments for flutter create.',
    });
    expect(stderr, isEmpty);
  });

  test('prints machine-readable runner errors for create --json', () async {
    final environment = await createTestEnvironment();
    await File(
      '${environment.homeDirectory.path}/config.json',
    ).writeAsString('{');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['create', '--json', 'broken_app'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'create'));
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 64));
    expect(report['error'], isA<Map<String, Object?>>());
    final error = report['error'] as Map<String, Object?>;
    expect(error, containsPair('type', 'format'));
    expect(error['message'], contains('fluoh config could not be read'));
    expect(stderr, isEmpty);
  });

  test('prints help create through the injected output writer', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['help', 'create'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout.join('\n'), contains('Usage: fluoh create'));
    expect(stdout.join('\n'), contains('--json'));
    expect(stderr, isEmpty);
  });

  test(
    'infers project directory when Flutter value options follow the target',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createCreateCommandSdkSource(
        environment.homeDirectory,
        versions: const ['3.36.1-ohos-0.0.1'],
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'enable', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          ['create', 'ordered_app', '--org', 'com.example'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final demo = Directory(
        '${environment.workingDirectory.path}/ordered_app',
      );
      expect(
        File('${demo.path}/fluoh.yaml').readAsStringSync(),
        contains('version: 3.36.1-ohos-0.0.1'),
      );
      expect(Link('${demo.path}/.fluoh/flutter_sdk').existsSync(), isTrue);
      expect(
        Directory(
          '${environment.workingDirectory.path}/com.example',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'infers project directory when short template option follows the target',
    () async {
      final environment = await createTestEnvironment();
      final source = await _createCreateCommandSdkSource(
        environment.homeDirectory,
        versions: const ['3.36.1-ohos-0.0.1'],
      );
      final stdout = <String>[];
      final stderr = <String>[];

      await runFluoh(
        ['source', 'enable', 'fixture', source.path],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      );
      stdout.clear();
      stderr.clear();

      expect(
        await runFluoh(
          ['create', 'ordered_plugin', '-t', 'plugin'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final demo = Directory(
        '${environment.workingDirectory.path}/ordered_plugin',
      );
      expect(
        File('${demo.path}/fluoh.yaml').readAsStringSync(),
        contains('version: 3.36.1-ohos-0.0.1'),
      );
      expect(Link('${demo.path}/.fluoh/flutter_sdk').existsSync(), isTrue);
      expect(
        Directory('${environment.workingDirectory.path}/plugin').existsSync(),
        isFalse,
      );
      expect(
        File(
          '${environment.workingDirectory.path}/flutter_create_invocations.txt',
        ).readAsStringSync(),
        contains('create ordered_plugin -t plugin'),
      );
    },
  );

  test('forwards --json to Flutter when it appears after --', () async {
    final environment = await createTestEnvironment();
    final source = await _createCreateCommandSdkSource(
      environment.homeDirectory,
      versions: const ['3.36.1-ohos-0.0.1'],
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'enable', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    stdout.clear();
    stderr.clear();

    expect(
      await runFluoh(
        ['create', '--', '--json', 'passthrough_app'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final demo = Directory(
      '${environment.workingDirectory.path}/passthrough_app',
    );
    expect(File('${demo.path}/fluoh.yaml').existsSync(), isTrue);
    expect(
      File(
        '${environment.workingDirectory.path}/flutter_create_invocations.txt',
      ).readAsStringSync(),
      contains('create --json passthrough_app'),
    );
    expect(stdout.join('\n'), contains('flutter create stdout'));
    expect(stdout, isNot(hasLength(1)));
  });

  test('prints wrapper help without loading source configuration', () async {
    final environment = await createTestEnvironment();
    final configFile = File('${environment.homeDirectory.path}/config.json');
    await environment.homeDirectory.delete(recursive: true);
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['create', '--help'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout.join('\n'), contains('Usage: fluoh create'));
    expect(configFile.existsSync(), isFalse);
    expect(stderr, isEmpty);
  });
}

Future<Directory> _createCreateCommandSdkSource(
  Directory parent, {
  required List<String> versions,
}) async {
  final sdkRepository = await _createFlutterOhSdkRepository(
    Directory('${parent.path}/flutter-ohos-sdk'),
    versions,
  );
  final source = Directory('${parent.path}/source');
  await writeSdkSourceFixture(
    source,
    sdkRepository: sdkRepository.path,
    releases: {for (final version in versions) version: version},
  );
  return source;
}

Future<Directory> _createFlutterOhSdkRepository(
  Directory repository,
  List<String> versions,
) async {
  await repository.create(recursive: true);
  await _git(repository, ['init', '--initial-branch=main']);
  await _git(repository, ['config', 'user.email', 'fixture@example.com']);
  await _git(repository, ['config', 'user.name', 'Fixture']);
  for (final version in versions) {
    await _writeFakeFlutter(repository, version: version);
    await _git(repository, ['add', '.']);
    await _git(repository, ['commit', '-m', 'SDK $version']);
    await _git(repository, ['tag', version]);
  }
  return repository;
}

Future<void> _writeFakeFlutter(
  Directory repository, {
  required String version,
}) async {
  final flutter = File('${repository.path}/bin/flutter');
  await flutter.parent.create(recursive: true);
  await flutter.writeAsString('''
#!/bin/sh
printf "%s\\n" "\$*" >> "\$PWD/flutter_create_invocations.txt"
if [ "\$1" = "create" ]; then
  shift
  target=""
  skip_next=0
  for arg in "\$@"; do
    if [ "\$skip_next" = "1" ]; then
      skip_next=0
      continue
    fi
    case "\$arg" in
      --android-language|--description|--ios-language|--org|--platforms|--project-name|--sample|--template|-a|-i|-t)
        skip_next=1
        ;;
      -*) ;;
      *) target="\$arg" ;;
    esac
  done
  if [ -z "\$target" ]; then
    printf "%s\\n" "missing target" >&2
    exit 64
  fi
  mkdir -p "\$target/lib"
  cat > "\$target/pubspec.yaml" <<'PUBSPEC'
name: fixture_app
dependencies:
  flutter:
    sdk: flutter
PUBSPEC
  printf "%s\\n" "flutter create stdout"
  printf "%s\\n" "flutter create stderr" >&2
  exit 0
fi
printf "%s\\n" "unsupported flutter $version \$*" >&2
exit 1
''');
  await Process.run('chmod', ['+x', flutter.path]);
}

Future<void> _git(Directory repository, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: repository.path,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
}
