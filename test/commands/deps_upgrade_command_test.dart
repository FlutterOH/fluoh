import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

void main() {
  test('deps upgrade updates existing OHOS implementation overrides', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    await writeFlutterProjectWithImplementationOverrideFixture(
      environment.workingDirectory,
    );
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
        ['deps', 'upgrade', '--dry-run'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    var pubspec = File(
      '${environment.workingDirectory.path}/pubspec.yaml',
    ).readAsStringSync();
    expect(pubspec, contains('camera-0.11.0-ohos-3.35-0'));

    expect(
      await runFluoh(
        ['deps', 'upgrade'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    pubspec = File(
      '${environment.workingDirectory.path}/pubspec.yaml',
    ).readAsStringSync();
    expect(
      stdout,
      contains(
        'Would update camera camera-0.11.0-ohos-3.35-0 -> camera-0.11.0-ohos-3.35-1.0.0',
      ),
    );
    expect(stdout, contains('Updated 1 FlutterOH dependency replacement'));
    expect(stdout, contains('Next: run `fluoh deps get`'));
    expect(pubspec, contains('camera-0.11.0-ohos-3.35-1.0.0'));
    expect(pubspec, isNot(contains('camera-0.11.0-ohos-3.35-0')));
    expect(stderr, isEmpty);
  });

  test('emits json for dry-run and applied upgrades', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    await writeFlutterProjectWithImplementationOverrideFixture(
      environment.workingDirectory,
    );
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
    stdout.clear();

    expect(
      await runFluoh(
        ['deps', 'upgrade', '--dry-run', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, hasLength(1));
    final dryRunReport = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(dryRunReport, containsPair('schema', 1));
    expect(dryRunReport, containsPair('command', 'deps upgrade'));
    expect(dryRunReport, containsPair('ok', false));
    expect(dryRunReport, containsPair('exitCode', 0));
    expect(dryRunReport, containsPair('applied', 0));
    expect(dryRunReport, containsPair('dryRun', true));
    final dryRunChanges = dryRunReport['changes'] as List<Object?>;
    expect(dryRunChanges, hasLength(1));
    expect(
      dryRunChanges.single,
      allOf(
        containsPair('packageName', 'camera'),
        containsPair('kind', 'updateRef'),
        containsPair('currentRef', 'camera-0.11.0-ohos-3.35-0'),
        containsPair('nextRef', 'camera-0.11.0-ohos-3.35-1.0.0'),
      ),
    );
    expect(
      File(
        '${environment.workingDirectory.path}/pubspec.yaml',
      ).readAsStringSync(),
      contains('camera-0.11.0-ohos-3.35-0'),
    );

    stdout.clear();
    expect(
      await runFluoh(
        ['deps', 'upgrade', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    expect(stdout, hasLength(1));
    final applyReport = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(applyReport, containsPair('schema', 1));
    expect(applyReport, containsPair('command', 'deps upgrade'));
    expect(applyReport, containsPair('ok', true));
    expect(applyReport, containsPair('exitCode', 0));
    expect(applyReport, containsPair('applied', 1));
    expect(applyReport, containsPair('dryRun', false));
    final pubspec = File(
      '${environment.workingDirectory.path}/pubspec.yaml',
    ).readAsStringSync();
    expect(pubspec, contains('camera-0.11.0-ohos-3.35-1.0.0'));
    expect(pubspec, isNot(contains('camera-0.11.0-ohos-3.35-0')));
    expect(stderr, isEmpty);
  });

  test('updates only the matching override block', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    await writeFlutterProjectFixture(environment.workingDirectory);
    final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
    await pubspec.writeAsString('''
name: fixture_app

dependencies:
  flutter:
    sdk: flutter
  other:
    git:
      url: ${environment.homeDirectory.path}/other
      ref: camera-0.11.0-ohos-3.35-0
  camera: 0.11.0

dependency_overrides:
  camera:
    git:
      url: ${environment.homeDirectory.path}/camera
      ref: camera-0.11.0-ohos-3.35-0
''');
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
        ['deps', 'upgrade'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final updated = pubspec.readAsStringSync();
    expect(
      RegExp(
        r'other:[\s\S]*?ref: camera-0\.11\.0-ohos-3\.35-0',
      ).hasMatch(updated),
      isTrue,
    );
    expect(
      RegExp(
        r'dependency_overrides:[\s\S]*?ref: camera-0\.11\.0-ohos-3\.35-1',
      ).hasMatch(updated),
      isTrue,
    );
    expect(stderr, isEmpty);
  });

  test('updates quoted OHOS refs and preserves quote style', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    await writeFlutterProjectFixture(environment.workingDirectory);
    final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
    await pubspec.writeAsString('''
name: fixture_app

dependencies:
  flutter:
    sdk: flutter
  camera:
    git:
      url: ${environment.homeDirectory.path}/camera
      ref: 'camera-0.11.0-ohos-3.35-0' # keep comment
  share_plus: 10.0.0
  mystery_package: ^1.0.0

dependency_overrides:
  camera:
    git:
      url: ${environment.homeDirectory.path}/camera
      ref: "camera-0.11.0-ohos-3.35-0"
''');
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
        ['deps', 'upgrade'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final updated = pubspec.readAsStringSync();
    expect(
      updated,
      contains("ref: 'camera-0.11.0-ohos-3.35-1.0.0' # keep comment"),
    );
    expect(updated, contains('ref: "camera-0.11.0-ohos-3.35-1.0.0"'));
    expect(updated, isNot(contains('camera-0.11.0-ohos-3.35-0')));
    expect(stdout, contains('Updated 2 FlutterOH dependency replacements'));
    expect(stderr, isEmpty);
  });

  test('updates rewritten OHOS dependencies without overrides', () async {
    final environment = await createTestEnvironment();
    final source = await createPackageSourceFixture(environment.homeDirectory);
    await writeFlutterProjectFixture(environment.workingDirectory);
    final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
    await pubspec.writeAsString('''
name: fixture_app

dependencies:
  flutter:
    sdk: flutter
  camera:
    git:
      url: ${environment.homeDirectory.path}/camera
      ref: camera-0.11.0-ohos-3.35-0
      path: packages/camera/camera
  share_plus: 10.0.0
  mystery_package: ^1.0.0
''');
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
        ['deps', 'upgrade'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final updated = pubspec.readAsStringSync();
    expect(updated, contains('camera-0.11.0-ohos-3.35-1.0.0'));
    expect(updated, isNot(contains('camera-0.11.0-ohos-3.35-0')));
    expect(stdout, contains('Updated 1 FlutterOH dependency replacement'));
    expect(stderr, isEmpty);
  });

  test(
    'upgrades existing refs to compatible OHOS implementation upgrades',
    () async {
      final environment = await createTestEnvironment();
      final source = await createPackageSourceFixture(
        environment.homeDirectory,
      );
      final manifest = File('${source.path}/manifests/share_plus/fluoh.yaml');
      await manifest.writeAsString(
        '${manifest.readAsStringSync()}'
        '        - version: 1.0.0\n'
        '          upstream:\n'
        '            version: 10.1.0\n'
        '            ref: share_plus-v10.1.0\n'
        '            commit: "1010101010101010101010101010101010101010"\n',
      );
      await writeFlutterProjectFixture(environment.workingDirectory);
      final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
      await pubspec.writeAsString('''
name: fixture_app

dependencies:
  flutter:
    sdk: flutter
  share_plus: 10.0.0

dependency_overrides:
  share_plus:
    git:
      url: ${environment.homeDirectory.path}/share_plus
      ref: share_plus-10.0.0-ohos-3.35-1.0.0
      path: packages/share_plus/share_plus
''');
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
          ['deps', 'upgrade', '--dry-run'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );
      expect(
        stdout,
        contains(
          'Would update share_plus share_plus-10.0.0-ohos-3.35-1.0.0 -> '
          'share_plus-10.1.0-ohos-3.35-1.0.0 '
          '(upstream 10.0.0 -> 10.1.0)',
        ),
      );
      expect(
        pubspec.readAsStringSync(),
        contains('share_plus-10.0.0-ohos-3.35-1.0.0'),
      );

      expect(
        await runFluoh(
          ['deps', 'upgrade'],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        0,
      );

      final updated = pubspec.readAsStringSync();
      expect(updated, contains('share_plus-10.1.0-ohos-3.35-1.0.0'));
      expect(updated, isNot(contains('share_plus-10.0.0-ohos-3.35-1.0.0')));
      expect(stderr, isEmpty);
    },
  );
}
