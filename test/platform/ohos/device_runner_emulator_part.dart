part of 'device_runner_test.dart';

void _registerOhosDeviceRunnerEmulatorTests() {
  test('starts local emulator and waits for hdc target', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_ohos_run_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final home = Directory('${root.path}/home')..createSync(recursive: true);
    final project = Directory('${root.path}/project')
      ..createSync(recursive: true);
    final ohos = await _writeOhosProject(project);
    final hap = File('${project.path}/entry-default-signed.hap')
      ..writeAsStringSync('hap');
    final hdcLog = File('${root.path}/hdc.log');
    final emulatorLog = File('${root.path}/emulator.log');
    final emulatorStarted = File('${root.path}/emulator.started');
    final deployed = await _writeEmulatorList(root);
    final imageRoot = Directory('${root.path}/Huawei/Sdk')
      ..createSync(recursive: true);
    final devEco = await _writeDevEcoFixture(
      root,
      hdcLog: hdcLog,
      emulatorLog: emulatorLog,
      emulatorStarted: emulatorStarted,
      targets: '[Empty]\n',
      targetsAfterEmulatorStart: 'emulator-5554\n',
    );

    final result = await runOhosHapsOnDevice(
      environment: FluohEnvironment(
        homeDirectory: home,
        workingDirectory: project,
        processEnvironment: {
          'FLUOH_DEVECO_STUDIO': devEco.path,
          'FLUOH_OHOS_EMULATOR_DEPLOYED': deployed.path,
          'FLUOH_HARMONYOS_SDK_ROOT': imageRoot.path,
          'FLUOH_OHOS_EMULATOR_MIN_FREE_KB': '0',
        },
      ),
      ohosDirectory: ohos,
      haps: [hap],
      output: TerminalOutput(stdout: (_) {}),
      startEmulator: true,
      emulatorName: 'Huawei_Phone',
      deviceTimeout: const Duration(seconds: 5),
      logDuration: Duration.zero,
    );

    expect(result.passed, isTrue, reason: result.reason);
    expect(emulatorStarted.existsSync(), isTrue);
    expect(
      emulatorLog.readAsStringSync(),
      contains('-hvd Huawei_Phone -path ${deployed.path}'),
    );
    expect(hdcLog.readAsStringSync(), contains('list targets'));
  });

  test('reports local emulator startup errors from DevEco logs', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_ohos_run_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final home = Directory('${root.path}/home')..createSync(recursive: true);
    final project = Directory('${root.path}/project')
      ..createSync(recursive: true);
    final ohos = await _writeOhosProject(project);
    final hap = File('${project.path}/entry-default-signed.hap')
      ..writeAsStringSync('hap');
    final hdcLog = File('${root.path}/hdc.log');
    final emulatorLog = File('${root.path}/emulator.log');
    final deployed = await _writeEmulatorList(root);
    final imageRoot = Directory('${root.path}/Huawei/Sdk')
      ..createSync(recursive: true);
    final devEco = await _writeDevEcoFixture(
      root,
      hdcLog: hdcLog,
      emulatorLog: emulatorLog,
      targets: '[Empty]\n',
      emulatorStartupLog:
          '[Warning] [CheckRuntimeEnv.cpp(RunCheck:166)]'
          '"No enough space to start Emulator"\n'
          '[Warning] QString::arg: Argument missing: '
          '请修改模拟器路径或者清理磁盘。\n',
    );

    final result = await runOhosHapsOnDevice(
      environment: FluohEnvironment(
        homeDirectory: home,
        workingDirectory: project,
        processEnvironment: {
          'FLUOH_DEVECO_STUDIO': devEco.path,
          'FLUOH_OHOS_EMULATOR_DEPLOYED': deployed.path,
          'FLUOH_HARMONYOS_SDK_ROOT': imageRoot.path,
          'FLUOH_OHOS_EMULATOR_MIN_FREE_KB': '0',
        },
      ),
      ohosDirectory: ohos,
      haps: [hap],
      output: TerminalOutput(stdout: (_) {}),
      startEmulator: true,
      emulatorName: 'Huawei_Phone',
      deviceTimeout: const Duration(seconds: 5),
      logDuration: Duration.zero,
    );

    expect(result.passed, isFalse);
    expect(result.reason, contains('not have enough free space'));
    expect(result.diagnostics.single.code, 'ohos.emulator_start_failed');
    expect(
      result.diagnostics.single.details['error'],
      contains('not have enough free space'),
    );
  });

  test(
    'auto-starts highest API local emulator when no device is connected',
    () async {
      final root = await Directory.systemTemp.createTemp('fluoh_ohos_run_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final home = Directory('${root.path}/home')..createSync(recursive: true);
      final project = Directory('${root.path}/project')
        ..createSync(recursive: true);
      final ohos = await _writeOhosProject(project);
      final hap = File('${project.path}/entry-default-signed.hap')
        ..writeAsStringSync('hap');
      final hdcLog = File('${root.path}/hdc.log');
      final emulatorLog = File('${root.path}/emulator.log');
      final emulatorStarted = File('${root.path}/emulator.started');
      final deployed = await _writeEmulatorList(
        root,
        emulators: const [
          {'name': 'OHOS_API_10', 'apiVersion': 10},
          {'name': 'OHOS_API_15', 'apiVersion': 15},
          {'name': 'OHOS_API_12', 'apiVersion': 12},
        ],
      );
      final imageRoot = Directory('${root.path}/Huawei/Sdk')
        ..createSync(recursive: true);
      final devEco = await _writeDevEcoFixture(
        root,
        hdcLog: hdcLog,
        emulatorLog: emulatorLog,
        emulatorStarted: emulatorStarted,
        targets: '[Empty]\n',
        targetsAfterEmulatorStart: 'emulator-5554\n',
      );

      final result = await runOhosHapsOnDevice(
        environment: FluohEnvironment(
          homeDirectory: home,
          workingDirectory: project,
          processEnvironment: {
            'FLUOH_DEVECO_STUDIO': devEco.path,
            'FLUOH_OHOS_EMULATOR_DEPLOYED': deployed.path,
            'FLUOH_HARMONYOS_SDK_ROOT': imageRoot.path,
            'FLUOH_OHOS_EMULATOR_MIN_FREE_KB': '0',
          },
        ),
        ohosDirectory: ohos,
        haps: [hap],
        output: TerminalOutput(stdout: (_) {}),
        startEmulator: true,
        deviceTimeout: const Duration(seconds: 5),
        logDuration: Duration.zero,
      );

      expect(result.passed, isTrue, reason: result.reason);
      expect(
        emulatorLog.readAsStringSync(),
        contains('-hvd OHOS_API_15 -path ${deployed.path}'),
      );
      expect(
        hdcLog.readAsStringSync(),
        contains('-t emulator-5554 install -r'),
      );
    },
  );
}
