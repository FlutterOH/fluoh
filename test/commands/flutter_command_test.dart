import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';

void main() {
  test('runs flutter from the SDK selected in fluoh.yaml', () async {
    final environment = await createTestEnvironment();
    final source = await _createFlutterCommandSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      ['sdk', 'use', '3.35.8-ohos-0.0.3'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(
      await runFluoh(
        ['flutter', 'pub', 'get', '--offline'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(
      File(
        '${environment.workingDirectory.path}/flutter_args.txt',
      ).readAsStringSync(),
      'pub\nget\n--offline\n',
    );
    expect(stdout, contains('flutter stdout'));
    expect(stderr, contains('flutter stderr'));
  });

  test('installs the selected SDK before running flutter when needed', () async {
    final environment = await createTestEnvironment();
    final source = await _createFlutterCommandSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    await File('${environment.workingDirectory.path}/fluoh.yaml').writeAsString(
      '''
schema: 1
sdk:
  version: 3.35.8-ohos-0.0.3
sources:
  - fixture
''',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(
      await runFluoh(
        ['flutter', '--version'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(
      stdout,
      contains(
        'Installing Flutter OHOS SDK 3.35.8-ohos-0.0.3; this may take a while.',
      ),
    );
    expect(
      Directory(
        '${environment.homeDirectory.path}/sdks/3.35.8-ohos-0.0.3',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        '${environment.workingDirectory.path}/flutter_args.txt',
      ).readAsStringSync(),
      '--version\n',
    );
    expect(stderr, contains('flutter stderr'));
  });

  test('runs cached selected SDK without readable sources', () async {
    final environment = await createTestEnvironment();
    final source = await _createFlutterCommandSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      ['sdk', 'use', '3.35.8-ohos-0.0.3'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await source.delete(recursive: true);

    expect(
      await runFluoh(
        ['flutter', 'doctor'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(
      File(
        '${environment.workingDirectory.path}/flutter_args.txt',
      ).readAsStringSync(),
      'doctor\n',
    );
    expect(
      stdout,
      isNot(
        contains(
          'Installing Flutter OHOS SDK 3.35.8-ohos-0.0.3; this may take a while.',
        ),
      ),
    );
    expect(stderr, contains('flutter stderr'));
  });

  test('runs cached selected SDK with malformed source config', () async {
    final environment = await createTestEnvironment();
    final source = await _createFlutterCommandSdkSource(
      environment.homeDirectory,
      environment.workingDirectory,
    );
    await writeFlutterProjectFixture(environment.workingDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await runFluoh(
      ['sdk', 'use', '3.35.8-ohos-0.0.3'],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );
    await environment.configFile.writeAsString('{');

    expect(
      await runFluoh(
        ['flutter', 'doctor'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(
      File(
        '${environment.workingDirectory.path}/flutter_args.txt',
      ).readAsStringSync(),
      'doctor\n',
    );
    expect(stderr, contains('flutter stderr'));
    expect(
      stderr.join('\n'),
      isNot(contains('fluoh config could not be read')),
    );
  });

  test('fails when no SDK has been selected', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final stdout = <String>[];
    final stderr = <String>[];

    await runFluoh(
      ['source', 'add', 'fixture', source.path],
      environment: environment,
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(
      await runFluoh(
        ['flutter', 'pub', 'get'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );
    expect(
      stderr.join('\n'),
      contains('No SDK selected. Run "fluoh sdk use <version-or-series>".'),
    );
  });
}

Future<Directory> _createFlutterCommandSdkSource(
  Directory parent,
  Directory project,
) async {
  final source = Directory('${parent.path}/flutter_command_source');
  final sdkRepository = Directory('${parent.path}/flutter_command_sdk');
  await Directory('${source.path}/sdk').create(recursive: true);
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
  await flutter.writeAsString('''
#!/bin/sh
printf "%s\\n" "\$@" > "${project.path}/flutter_args.txt"
printf "flutter stdout\\n"
printf "flutter stderr\\n" >&2
exit 0
''');
  await _runProcess('chmod', ['+x', flutter.path], sdkRepository);
  await File('${sdkRepository.path}/README.md').writeAsString('# SDK\n');
  await _runProcess('git', ['add', '.'], sdkRepository);
  await _runProcess('git', ['commit', '-m', 'Initial SDK'], sdkRepository);
  await _runProcess('git', ['tag', '3.35.8-ohos-0.0.3'], sdkRepository);
  await File('${source.path}/sdk/releases.yaml').writeAsString('''
schema: 1
url: ${sdkRepository.path}
releases:
  - version: 3.35.8-ohos-0.0.3
    status: stable
''');
  return source;
}

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
