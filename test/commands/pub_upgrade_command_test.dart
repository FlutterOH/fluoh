import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_test_context.dart';

void main() {
  test('updates existing OHOS adapter overrides to the latest tag', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    await writeFlutterProjectWithAdapterOverrideFixture(
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
        ['pub', 'upgrade', '--dry-run'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    var pubspec = File(
      '${environment.workingDirectory.path}/pubspec.yaml',
    ).readAsStringSync();
    expect(pubspec, contains('camera-v0.11.0-ohos-3.35.8-0'));

    expect(
      await runFluoh(
        ['pub', 'upgrade'],
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
        'Would update camera camera-v0.11.0-ohos-3.35.8-0 -> camera-v0.11.0-ohos-3.35.8-1',
      ),
    );
    expect(stdout, contains('Updated 1 OHOS dependency ref.'));
    expect(stdout, contains('Next: run `fluoh pub get`.'));
    expect(pubspec, contains('camera-v0.11.0-ohos-3.35.8-1'));
    expect(pubspec, isNot(contains('camera-v0.11.0-ohos-3.35.8-0')));
    expect(stderr, isEmpty);
  });

  test('updates only the matching override block', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
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
      ref: camera-v0.11.0-ohos-3.35.8-0
  camera: 0.11.0

dependency_overrides:
  camera:
    git:
      url: ${environment.homeDirectory.path}/camera
      ref: camera-v0.11.0-ohos-3.35.8-0
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
        ['pub', 'upgrade'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final updated = pubspec.readAsStringSync();
    expect(
      RegExp(
        r'other:[\s\S]*?ref: camera-v0\.11\.0-ohos-3\.35\.8-0',
      ).hasMatch(updated),
      isTrue,
    );
    expect(
      RegExp(
        r'dependency_overrides:[\s\S]*?ref: camera-v0\.11\.0-ohos-3\.35\.8-1',
      ).hasMatch(updated),
      isTrue,
    );
    expect(stderr, isEmpty);
  });

  test('updates quoted OHOS refs and preserves quote style', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
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
      ref: 'camera-v0.11.0-ohos-3.35.8-0' # keep comment
  share_plus: 10.0.0
  mystery_package: ^1.0.0

dependency_overrides:
  camera:
    git:
      url: ${environment.homeDirectory.path}/camera
      ref: "camera-v0.11.0-ohos-3.35.8-0"
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
        ['pub', 'upgrade'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final updated = pubspec.readAsStringSync();
    expect(
      updated,
      contains("ref: 'camera-v0.11.0-ohos-3.35.8-1' # keep comment"),
    );
    expect(updated, contains('ref: "camera-v0.11.0-ohos-3.35.8-1"'));
    expect(updated, isNot(contains('camera-v0.11.0-ohos-3.35.8-0')));
    expect(stdout, contains('Updated 2 OHOS dependency refs.'));
    expect(stderr, isEmpty);
  });

  test('updates rewritten OHOS dependencies without overrides', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
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
      ref: camera-v0.11.0-ohos-3.35.8-0
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
        ['pub', 'upgrade'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final updated = pubspec.readAsStringSync();
    expect(updated, contains('camera-v0.11.0-ohos-3.35.8-1'));
    expect(updated, isNot(contains('camera-v0.11.0-ohos-3.35.8-0')));
    expect(stdout, contains('Updated 1 OHOS dependency ref.'));
    expect(stderr, isEmpty);
  });

  test('updates existing refs to compatible adapter upgrades', () async {
    final environment = await createTestEnvironment();
    final source = await createPubSourceFixture(environment.homeDirectory);
    final manifest = File('${source.path}/packages/manifests/share_plus.yaml');
    await manifest.writeAsString('''
${manifest.readAsStringSync()}
  - upstream:
      version: 10.1.0
      git:
        ref: share_plus-v10.1.0
    package:
      version: "1"
      git:
        ref: ohos/3.35
    sdk:
      versionSeries: 3.35
      versions:
        - 3.35.8-ohos-0.0.3
    status: compatible
    replacement:
      git:
        url: ${environment.homeDirectory.path}/share_plus
        ref: share_plus-v10.1.0-ohos-3.35.8-1
        path: packages/share_plus/share_plus
''');
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
      ref: share_plus-v10.0.0-ohos-3.35.8-1
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
        ['pub', 'upgrade', '--dry-run'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    expect(
      stdout,
      contains(
        'Would update share_plus share_plus-v10.0.0-ohos-3.35.8-1 -> '
        'share_plus-v10.1.0-ohos-3.35.8-1 '
        '(upstream 10.0.0 -> 10.1.0)',
      ),
    );
    expect(
      pubspec.readAsStringSync(),
      contains('share_plus-v10.0.0-ohos-3.35.8-1'),
    );

    expect(
      await runFluoh(
        ['pub', 'upgrade'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final updated = pubspec.readAsStringSync();
    expect(updated, contains('share_plus-v10.1.0-ohos-3.35.8-1'));
    expect(updated, isNot(contains('share_plus-v10.0.0-ohos-3.35.8-1')));
    expect(stderr, isEmpty);
  });
}
