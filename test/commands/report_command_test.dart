import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';

void main() {
  test('report create uses an explicit output path exactly', () async {
    final environment = await createTestEnvironment();
    final output = File(
      '${environment.workingDirectory.path}/reports/custom.md',
    );
    await output.parent.create(recursive: true);
    await output.writeAsString('old english');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'report',
          'create',
          '--scope',
          'camera',
          '--output',
          output.path,
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('report', output.path));
    expect(report, isNot(contains('reports')));
    expect(
      File(
        '${environment.workingDirectory.path}/reports/custom-2.md',
      ).existsSync(),
      isFalse,
    );
    final content = await output.readAsString();
    expect(content, contains('# fluoh AI Report'));
    expect(content, contains('Interaction evidence missing:'));
    expect(content, isNot(contains('\nNo interaction required:')));
    expect(stderr, isEmpty);
  });

  test('report create writes an AI report from trace and automation json', () async {
    final environment = await createTestEnvironment();
    final traceDir = Directory(
      '${environment.workingDirectory.path}/.fluoh/traces/camera/session',
    );
    await traceDir.create(recursive: true);
    await File('${traceDir.path}/trace.json').writeAsString(
      jsonEncode({
        'id': 'trace-camera-session',
        'invocations': [
          {
            'commandLine':
                'fluoh build ohos --package camera --auto-sign --json',
            'exitCode': 0,
            'trace': {'manifest': '${traceDir.path}/trace.json'},
          },
          {
            'commandLine':
                'fluoh run android --package camera --auto-emulator --json',
            'exitCode': 0,
          },
        ],
        'feedbackCandidates': [
          {
            'id': 'fluoh.automation.retry',
            'owner': 'fluoh',
            'category': 'automation',
            'suggestedChange': 'Keep platform retry evidence structured.',
          },
        ],
      }),
    );
    final automationFile = File(
      '${environment.workingDirectory.path}/automation.json',
    );
    await automationFile.writeAsString(
      jsonEncode({
        'schema': 1,
        'command': 'drive',
        'ok': true,
        'exitCode': 0,
        'automation': {
          'rerunCommand':
              'fluoh drive ohos --package camera --scenario .fluoh/scenarios/camera/ohos-permission.md --json',
          'coveragePolicy': {
            'status': 'readyForReview',
            'readyForAutomation': true,
            'qualityGateSummary': {'ready': 1, 'notReady': 0},
            'qualityGates': [
              {
                'id': 'coverage-inventory',
                'status': 'readyForReview',
                'evidence': 'scenario matrix complete',
              },
            ],
          },
        },
        'targets': [
          {
            'platform': 'ohos',
            'targetName': 'DevEco Emulator',
            'steps': [
              {
                'name': 'automation-scenario-camera-permission',
                'status': 'passed',
                'path': 'camera permission grant',
              },
            ],
          },
        ],
      }),
    );
    final output = File(
      '${environment.workingDirectory.path}/reports/camera.md',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'report',
          'create',
          '--scope',
          'camera',
          '--package',
          'camera',
          '--trace-dir',
          traceDir.path,
          '--automation-json',
          automationFile.path,
          '--output',
          output.path,
          '--recommendation',
          'needs-maintainer-decision',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schema', 1));
    expect(report, containsPair('command', 'report create'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('changed', true));
    expect(report, containsPair('report', output.path));
    expect(report, isNot(contains('reports')));
    expect(report, containsPair('scope', 'camera'));
    expect(report['commandRows'], 3);
    expect(report['automationRows'], 1);
    expect(report['interactionRows'], 1);
    final content = output.readAsStringSync();
    expect(content, contains('# fluoh AI Report'));
    expect(content, contains('## Adaptation Responsibility'));
    expect(content, contains('## Platform Matrix'));
    expect(content, contains('## Automation Coverage'));
    expect(
      content,
      contains(
        'Existing package/app tests, example tests, and `integration_test/` were inspected',
      ),
    );
    expect(
      content,
      contains('Missing or weak functional tests were added or repaired'),
    );
    expect(
      content,
      contains(
        'Every existing Android, iOS, macOS, Linux, Web, and Windows platform was functionally checked',
      ),
    );
    expect(content, contains('automation-scenario-camera-permission'));
    expect(
      content,
      contains(
        'fluoh drive ohos --package camera --scenario .fluoh/scenarios/camera/ohos-permission.md --json',
      ),
    );
    expect(content, contains('fluoh.automation.retry'));
    expect(
      content,
      contains('Release recommendation: needs-maintainer-decision'),
    );
    expect(stderr, isEmpty);
  });

  test('report create imports automation evidence from trace manifests', () async {
    final environment = await createTestEnvironment();
    final traceDir = Directory(
      '${environment.workingDirectory.path}/.fluoh/traces/camera/adaptation',
    );
    await traceDir.create(recursive: true);
    await File('${traceDir.path}/trace.json').writeAsString(
      jsonEncode({
        'id': 'trace-camera-adaptation',
        'invocations': [
          {
            'commandLine':
                'fluoh drive ohos --package camera --scenario .fluoh/scenarios/camera/ohos-permission.md --dry-run --json --trace-dir .fluoh/traces/camera/adaptation',
            'ok': true,
            'exitCode': 0,
            'result': {
              'automation': {
                'coveragePolicy': {
                  'status': 'needsInteractionInventory',
                  'readyForAutomation': false,
                  'qualityGateSummary': {
                    'ready': 0,
                    'notReady': [
                      {'id': 'coverage-inventory'},
                    ],
                  },
                  'qualityGates': [
                    {
                      'id': 'coverage-inventory',
                      'status': 'needsInventory',
                      'repair': 'stale dry-run coverage inventory',
                    },
                  ],
                },
              },
            },
          },
          {
            'commandLine':
                'fluoh drive ohos --package camera --scenario .fluoh/scenarios/camera/ohos-permission.md --json --trace-dir .fluoh/traces/camera/adaptation',
            'ok': true,
            'exitCode': 0,
            'result': {
              'automation': {
                'coveragePolicy': {
                  'status': 'readyForExecution',
                  'readyForAutomation': true,
                  'qualityGateSummary': {'ready': 9, 'notReady': 0},
                  'qualityGates': [
                    {
                      'id': 'coverage-inventory',
                      'status': 'readyForReview',
                      'evidence': 'interaction inventory reviewed',
                    },
                  ],
                },
              },
              'targets': [
                {
                  'target': {'kind': 'package', 'name': 'camera'},
                  'phase': 'ohos-run',
                  'passed': true,
                  'exitCode': 0,
                  'steps': [
                    {
                      'name': 'package-run-ohos',
                      'path': 'example',
                      'command':
                          'flutter run -d emulator-5554 --device-timeout 90',
                      'status': 'passed',
                      'exitCode': 0,
                      'details': {
                        'platform': 'ohos',
                        'targetId': 'emulator-5554',
                      },
                    },
                    {
                      'name': 'automation-scenario-ohos-camera-permission',
                      'path': '.fluoh/scenarios/camera',
                      'command':
                          'fluoh drive ohos --package camera --scenario .fluoh/scenarios/camera/ohos-permission.md --json --trace-dir .fluoh/traces/camera/adaptation',
                      'status': 'passed',
                      'exitCode': 0,
                      'details': {
                        'scenario': {
                          'path': '.fluoh/scenarios/camera/ohos-permission.md',
                          'name': 'camera permission',
                          'platform': 'ohos',
                        },
                        'actions': [
                          {
                            'index': 1,
                            'action': 'captureScreenshot',
                            'status': 'passed',
                            'details': {
                              'path':
                                  '.fluoh/evidence/screenshots/camera-ohos-main.png',
                              'bytes': 128,
                            },
                          },
                          {
                            'index': 2,
                            'action': 'assertLog',
                            'status': 'passed',
                            'details': {
                              'hilog':
                                  '.fluoh/traces/camera/adaptation/ohos.hilog',
                            },
                          },
                        ],
                      },
                    },
                  ],
                },
              ],
            },
          },
        ],
      }),
    );
    final output = File(
      '${environment.workingDirectory.path}/reports/camera-trace.md',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'report',
          'create',
          '--scope',
          'camera',
          '--trace-dir',
          traceDir.path,
          '--output',
          output.path,
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(payload, containsPair('commandRows', 2));
    expect(payload, containsPair('automationRows', 1));
    expect(payload, containsPair('interactionRows', 1));
    final content = output.readAsStringSync();
    expect(content, contains('- coveragePolicy.status: readyForExecution'));
    expect(content, isNot(contains('stale dry-run coverage inventory')));
    expect(content, isNot(contains('| coverage-inventory | needsInventory |')));
    expect(content, isNot(contains('No automation JSON supplied')));
    expect(content, isNot(contains('Interaction evidence missing:')));
    expect(content, contains('automation-scenario-ohos-camera-permission'));
    expect(content, contains('emulator-5554'));
    expect(
      content,
      contains(
        'post-launch screenshot .fluoh/evidence/screenshots/camera-ohos-main.png',
      ),
    );
    expect(content, contains('assertLog passed with hilog'));
    expect(stderr, isEmpty);
  });

  test('report create leaves blocked automation gates unchecked', () async {
    final environment = await createTestEnvironment();
    final automationFile = File(
      '${environment.workingDirectory.path}/blocked-automation.json',
    );
    await automationFile.writeAsString(
      jsonEncode({
        'schema': 1,
        'command': 'drive',
        'ok': false,
        'exitCode': 1,
        'automation': {
          'coveragePolicy': {
            'status': 'needsInteractionInventory',
            'readyForAutomation': false,
            'qualityGateSummary': {
              'ready': 0,
              'notReady': [
                {'id': 'coverage-inventory'},
              ],
            },
            'qualityGates': [
              {
                'id': 'coverage-inventory',
                'status': 'needsInventory',
                'repair': 'Add scenario coverage metadata.',
              },
            ],
          },
        },
      }),
    );
    final output = File(
      '${environment.workingDirectory.path}/reports/blocked.md',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'report',
          'create',
          '--scope',
          'camera',
          '--automation-json',
          automationFile.path,
          '--output',
          output.path,
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(payload, containsPair('automationRows', 1));
    expect(payload, isNot(contains('reports')));
    final content = output.readAsStringSync();
    expect(content, contains('flutter test integration_test -d <device>'));
    expect(
      content,
      contains(
        '| coverage-inventory | needsInventory | Add scenario coverage metadata. |',
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'report create reports missing automation json as machine error',
    () async {
      final environment = await createTestEnvironment();
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          [
            'report',
            'create',
            '--scope',
            'camera',
            '--automation-json',
            'missing-automation.json',
            '--json',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      final payload = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(payload, containsPair('command', 'report create'));
      expect(payload, containsPair('ok', false));
      expect(payload, containsPair('exitCode', 64));
      expect(
        payload['error'],
        allOf(
          containsPair('type', 'format'),
          containsPair(
            'message',
            contains(
              'JSON input ${environment.workingDirectory.path}/missing-automation.json does not exist.',
            ),
          ),
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test('report create reports missing trace path as machine error', () async {
    final environment = await createTestEnvironment();
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'report',
          'create',
          '--scope',
          'camera',
          '--trace-dir',
          'missing-traces',
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(payload, containsPair('command', 'report create'));
    expect(payload, containsPair('ok', false));
    expect(payload, containsPair('exitCode', 64));
    expect(
      payload['error'],
      allOf(
        containsPair('type', 'format'),
        containsPair(
          'message',
          contains(
            'Trace path ${environment.workingDirectory.path}/missing-traces does not exist.',
          ),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test('report create reports malformed json with the input path', () async {
    final environment = await createTestEnvironment();
    final automationFile = File(
      '${environment.workingDirectory.path}/bad-automation.json',
    );
    await automationFile.writeAsString('{');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'report',
          'create',
          '--scope',
          'camera',
          '--automation-json',
          automationFile.path,
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      64,
    );

    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(
      payload['error'],
      allOf(
        containsPair('type', 'format'),
        containsPair(
          'message',
          contains('Could not parse JSON input ${automationFile.path}:'),
        ),
      ),
    );
    expect(stderr, isEmpty);
  });

  test(
    'report create reports empty trace directory as machine error',
    () async {
      final environment = await createTestEnvironment();
      final traceDir = Directory(
        '${environment.workingDirectory.path}/.fluoh/traces/camera/empty',
      );
      await traceDir.create(recursive: true);
      final stdout = <String>[];
      final stderr = <String>[];

      expect(
        await runFluoh(
          [
            'report',
            'create',
            '--scope',
            'camera',
            '--trace-dir',
            traceDir.path,
            '--json',
          ],
          environment: environment,
          stdout: stdout.add,
          stderr: stderr.add,
        ),
        64,
      );

      final payload = jsonDecode(stdout.single) as Map<String, Object?>;
      expect(
        payload['error'],
        allOf(
          containsPair('type', 'format'),
          containsPair(
            'message',
            contains(
              'Trace path ${traceDir.path} does not contain trace.json.',
            ),
          ),
        ),
      );
      expect(stderr, isEmpty);
    },
  );

  test('report create defaults scope to package before root pubspec', () async {
    final environment = await createTestEnvironment();
    await File(
      '${environment.workingDirectory.path}/pubspec.yaml',
    ).writeAsString('''
name: root_workspace
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['report', 'create', '--package', 'camera', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(payload, containsPair('command', 'report create'));
    expect(payload, containsPair('ok', true));
    expect(payload, containsPair('scope', 'camera'));
    final reportPath = payload['report'] as String;
    expect(reportPath, contains('/.fluoh/reports/camera/report-'));
    expect(
      File(reportPath).uri.pathSegments.last,
      matches(RegExp(r'^report-\d+\.md$')),
    );
    final content = File(reportPath).readAsStringSync();
    expect(content, contains('- Scope: camera'));
    expect(content, contains('- Package: camera'));
    expect(stderr, isEmpty);
  });

  test('report create reads default scope with YAML parsing', () async {
    final environment = await createTestEnvironment();
    await File(
      '${environment.workingDirectory.path}/pubspec.yaml',
    ).writeAsString('''
name: "root_workspace" # keep comment out of the scope
''');
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        ['report', 'create', '--json'],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(payload, containsPair('scope', 'root_workspace'));
    final reportPath = payload['report'] as String;
    expect(reportPath, contains('/.fluoh/reports/root_workspace/'));
    expect(
      File(reportPath).uri.pathSegments.last,
      matches(RegExp(r'^report-\d+\.md$')),
    );
    expect(stderr, isEmpty);
  });

  test('report create keeps failed command evidence failed in the matrix', () async {
    final environment = await createTestEnvironment();
    final traceDir = Directory(
      '${environment.workingDirectory.path}/.fluoh/traces/camera/failures',
    );
    await traceDir.create(recursive: true);
    await File('${traceDir.path}/trace.json').writeAsString(
      jsonEncode({
        'id': 'trace-camera-failures',
        'invocations': [
          {
            'commandLine':
                'fluoh build ohos --package camera --auto-sign --json',
            'ok': false,
            'exitCode': 0,
          },
          {
            'commandLine':
                'fluoh run android --package camera --auto-emulator --json',
            'exitCode': 1,
          },
          {
            'commandLine': 'fluoh run web --package camera --json',
            'ok': true,
            'exitCode': 0,
          },
        ],
      }),
    );
    final output = File(
      '${environment.workingDirectory.path}/reports/camera-failures.md',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(
        [
          'report',
          'create',
          '--scope',
          'camera',
          '--trace-dir',
          traceDir.path,
          '--output',
          output.path,
          '--json',
        ],
        environment: environment,
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );

    final payload = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(payload, containsPair('commandRows', 3));
    final content = output.readAsStringSync();
    expect(
      content,
      contains(
        '| `fluoh build ohos --package camera --auto-sign --json` | 0 | failed |',
      ),
    );
    expect(
      content,
      contains('| `fluoh run web --package camera --json` | 0 | passed |'),
    );
    expect(
      content,
      contains(
        '| OHOS | failed | skipped | n/a | n/a | composed from command rows |',
      ),
    );
    expect(
      content,
      contains(
        '| Android | skipped | failed | n/a | n/a | composed from command rows |',
      ),
    );
    expect(
      content,
      contains(
        '| Web | skipped | passed | n/a | n/a | composed from command rows |',
      ),
    );
    expect(stderr, isEmpty);
  });
}
