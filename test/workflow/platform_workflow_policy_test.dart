import 'package:fluoh/src/workflow/platform_workflow_policy.dart';
import 'package:test/test.dart';

void main() {
  test('builds app and package regression commands from platform policy', () {
    expect(
      platformWorkflowPolicy('android').regressionCommand(traceDir: 'traces'),
      'fluoh run android --auto-emulator --json --trace-dir traces',
    );
    expect(
      platformWorkflowPolicy(
        'linux',
      ).regressionCommand(packageName: 'camera', traceDir: 'traces'),
      'fluoh build linux --package camera --json --trace-dir traces',
    );
    expect(
      platformWorkflowPolicy(
        'web',
      ).regressionCommand(packageName: 'camera', traceDir: 'traces'),
      'fluoh run web --package camera --json --trace-dir traces',
    );
  });

  test('formats project doctor and target inventory commands', () {
    final ohos = platformWorkflowPolicy('ohos');

    expect(
      ohos.doctorCommand(project: true),
      'fluoh doctor --platform ohos --project --json',
    );
    expect(
      ohos.doctorCommand(project: true, strict: true),
      'fluoh doctor --platform ohos --project --json --strict',
    );
    expect(
      ohos.devicesCommand(json: true),
      'fluoh devices --platform ohos --json',
    );
    expect(
      ohos.emulatorsCommand(json: true),
      'fluoh emulators --platform ohos --json',
    );
  });

  test('routes package diagnostics through platform policies', () {
    expect(
      platformWorkflowPolicy(
        'android',
      ).packageRepairCommand('android.device_missing', 'camera'),
      'fluoh run android --package camera --auto-emulator --json',
    );
    expect(
      platformWorkflowPolicy(
        'web',
      ).packageRepairCommand('web.device_missing', 'camera'),
      'fluoh doctor --platform web --json',
    );
    expect(
      platformWorkflowPolicy(
        'windows',
      ).packageRepairCommand('windows.device_ambiguous', 'camera'),
      'fluoh devices --platform windows',
    );
    expect(
      platformWorkflowPolicy(
        'macos',
      ).packageRepairCommand('macos.device_missing', 'camera'),
      'fluoh run macos --package camera --json',
    );
  });

  test('routes project diagnostics through platform policies', () {
    expect(
      platformWorkflowPolicy('android').projectRepairCommand(
        'android.device_missing',
        currentCommand: 'fluoh run android --json',
        autoEmulatorCommand: 'fluoh run android --auto-emulator --json',
      ),
      'fluoh run android --auto-emulator --json',
    );
    expect(
      platformWorkflowPolicy('web').projectRepairCommand(
        'web.device_missing',
        currentCommand: 'fluoh run web --json',
        autoEmulatorCommand: 'fluoh run web --json',
      ),
      'fluoh doctor --platform web --json',
    );
    expect(
      platformWorkflowPolicy('ohos').projectRepairCommand(
        'ohos.hdc_target_unavailable',
        currentCommand: 'fluoh run ohos --json',
        autoEmulatorCommand: 'fluoh run ohos --auto-emulator --json',
      ),
      'fluoh devices --platform ohos',
    );
  });

  test(
    'owns platform labels, integration diagnostics, and evidence metadata',
    () {
      expect(platformWorkflowPolicy('ios').label, 'iOS');
      expect(
        platformWorkflowPolicy('web').integrationTestDiagnosticCode,
        'web.integration_test_failed',
      );
      expect(
        platformWorkflowPolicy('ohos').integrationTestDiagnosticCode,
        'integration_test.failed',
      );
      expect(
        platformWorkflowPolicy('android').automationEvidenceItems,
        contains('flutterRunSession JSON'),
      );
      expect(
        platformWorkflowPolicy('ohos').automationMetadata,
        contains('ohos'),
      );
    },
  );

  test('suggests integration discovery runs without web-server targets', () {
    final commands = integrationDiscoveryRunCommands(packageName: 'camera');

    expect(commands, contains('fluoh run web --package camera --json'));
    expect(commands.join('\n'), isNot(contains('web-server')));
    expect(commands.join('\n'), isNot(contains('--device-id chrome')));
  });
}
