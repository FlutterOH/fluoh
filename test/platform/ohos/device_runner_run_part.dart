part of 'device_runner_test.dart';

void _registerOhosDeviceRunnerRunTests() {
  test('reads launch info from OHOS stage module metadata', () async {
    final root = await Directory.systemTemp.createTemp('fluoh_ohos_run_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final ohos = await _writeOhosProject(root);

    final launchInfo = await readOhosLaunchInfo(ohos);

    expect(launchInfo.bundleName, 'com.example.camera');
    expect(launchInfo.moduleName, 'entry');
    expect(launchInfo.abilityName, 'EntryAbility');
  });

  test('installs signed HAP, starts ability, and writes hilog', () async {
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
    final devEco = await _writeDevEcoFixture(root, hdcLog: hdcLog);
    final outputLines = <String>[];

    final result = await runOhosHapsOnDevice(
      environment: FluohEnvironment(
        homeDirectory: home,
        workingDirectory: project,
        processEnvironment: {
          'FLUOH_DEVECO_STUDIO': devEco.path,
          'FLUOH_OHOS_EMULATOR_DEPLOYED': '${root.path}/no_emulators',
        },
      ),
      ohosDirectory: ohos,
      haps: [hap],
      output: TerminalOutput(stdout: outputLines.add),
      logDuration: const Duration(milliseconds: 10),
    );

    expect(
      result.passed,
      isTrue,
      reason:
          'reason=${result.reason}, '
          'findings=${result.findings}, '
          'diagnostics=${result.diagnostics.map((item) => '${item.code}: ${item.details}').join('; ')}',
    );
    expect(result.diagnostics, isEmpty);
    expect(result.targetId, 'emulator-5554');
    expect(result.logFile, isNotNull);
    expect(
      result.logFile!.path,
      startsWith(
        '${project.path}/.fluoh/cache/package-runs/com.example.camera/',
      ),
    );
    expect(result.logFile!.readAsStringSync(), contains('app started'));
    final invocations = hdcLog.readAsStringSync();
    expect(invocations, contains('list targets'));
    expect(invocations, contains('-t emulator-5554 install -r ${hap.path}'));
    expect(
      invocations,
      contains(
        '-t emulator-5554 shell aa start -d 0 -a EntryAbility '
        '-b com.example.camera',
      ),
    );
    expect(invocations, contains('-t emulator-5554 hilog -r'));
    expect(invocations, contains('-t emulator-5554 hilog'));
  });

  test('auto emulator reuses an already connected emulator target', () async {
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
    final devEco = await _writeDevEcoFixture(
      root,
      hdcLog: hdcLog,
      emulatorLog: emulatorLog,
      targets: 'real-device\nemulator-5554\n',
    );

    final result = await runOhosHapsOnDevice(
      environment: FluohEnvironment(
        homeDirectory: home,
        workingDirectory: project,
        processEnvironment: {
          'FLUOH_DEVECO_STUDIO': devEco.path,
          'FLUOH_OHOS_EMULATOR_DEPLOYED': '${root.path}/no_emulators',
        },
      ),
      ohosDirectory: ohos,
      haps: [hap],
      output: TerminalOutput(stdout: (_) {}),
      startEmulator: true,
      logDuration: const Duration(milliseconds: 10),
    );

    expect(result.passed, isTrue, reason: result.reason);
    expect(result.targetId, 'emulator-5554');
    expect(emulatorLog.existsSync(), isFalse);
    final invocations = hdcLog.readAsStringSync();
    expect(invocations, contains('list targets'));
    expect(invocations, contains('-t emulator-5554 install -r ${hap.path}'));
    expect(invocations, isNot(contains('-t real-device install')));
  });

  test('auto emulator reuses a localhost hdc emulator target', () async {
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
    final devEco = await _writeDevEcoFixture(
      root,
      hdcLog: hdcLog,
      emulatorLog: emulatorLog,
      targets: '127.0.0.1:5555\n',
    );

    final result = await runOhosHapsOnDevice(
      environment: FluohEnvironment(
        homeDirectory: home,
        workingDirectory: project,
        processEnvironment: {
          'FLUOH_DEVECO_STUDIO': devEco.path,
          'FLUOH_OHOS_EMULATOR_DEPLOYED': '${root.path}/no_emulators',
        },
      ),
      ohosDirectory: ohos,
      haps: [hap],
      output: TerminalOutput(stdout: (_) {}),
      startEmulator: true,
      logDuration: const Duration(milliseconds: 10),
    );

    expect(result.passed, isTrue, reason: result.reason);
    expect(result.targetId, '127.0.0.1:5555');
    expect(emulatorLog.existsSync(), isFalse);
    final invocations = hdcLog.readAsStringSync();
    expect(invocations, contains('list targets'));
    expect(invocations, contains('-t 127.0.0.1:5555 install -r ${hap.path}'));
  });

  test(
    'auto emulator falls back to a connected device when emulator tool is missing',
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
      final devEco = await _writeDevEcoFixture(
        root,
        hdcLog: hdcLog,
        targets: 'real-device\n',
        createEmulatorTool: false,
      );

      final result = await runOhosHapsOnDevice(
        environment: FluohEnvironment(
          homeDirectory: home,
          workingDirectory: project,
          processEnvironment: {
            'FLUOH_DEVECO_STUDIO': devEco.path,
            'FLUOH_OHOS_EMULATOR_DEPLOYED': '${root.path}/no_emulators',
          },
        ),
        ohosDirectory: ohos,
        haps: [hap],
        output: TerminalOutput(stdout: (_) {}),
        startEmulator: true,
        logDuration: Duration.zero,
      );

      expect(result.passed, isTrue, reason: result.reason);
      expect(result.targetId, 'real-device');
      final invocations = hdcLog.readAsStringSync();
      expect(invocations, contains('list targets'));
      expect(invocations, contains('-t real-device install -r ${hap.path}'));
    },
  );

  test(
    'explicit OHOS emulator does not fall back to a connected device',
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
      final devEco = await _writeDevEcoFixture(
        root,
        hdcLog: File('${root.path}/hdc.log'),
        targets: 'real-device\n',
        createEmulatorTool: false,
      );

      final result = await runOhosHapsOnDevice(
        environment: FluohEnvironment(
          homeDirectory: home,
          workingDirectory: project,
          processEnvironment: {
            'FLUOH_DEVECO_STUDIO': devEco.path,
            'FLUOH_OHOS_EMULATOR_DEPLOYED': '${root.path}/no_emulators',
          },
        ),
        ohosDirectory: ohos,
        haps: [hap],
        output: TerminalOutput(stdout: (_) {}),
        startEmulator: true,
        emulatorName: 'OHOS_API_15',
        logDuration: Duration.zero,
      );

      expect(result.passed, isFalse);
      expect(result.targetId, isNull);
      expect(result.diagnostics.single.code, 'ohos.emulator_start_failed');
      expect(result.reason, contains('Could not locate DevEco emulator'));
    },
  );

  test('reports missing device targets as a failed run result', () async {
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
    final devEco = await _writeDevEcoFixture(
      root,
      hdcLog: File('${root.path}/hdc.log'),
      targets: '[Empty]\n',
    );

    final result = await runOhosHapsOnDevice(
      environment: FluohEnvironment(
        homeDirectory: home,
        workingDirectory: project,
        processEnvironment: {
          'FLUOH_DEVECO_STUDIO': devEco.path,
          'FLUOH_OHOS_EMULATOR_DEPLOYED': '${root.path}/no_emulators',
        },
      ),
      ohosDirectory: ohos,
      haps: [hap],
      output: TerminalOutput(stdout: (_) {}),
      logDuration: Duration.zero,
    );

    expect(result.passed, isFalse);
    expect(result.reason, contains('No OHOS device target is connected'));
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.code, 'ohos.device_missing');
    expect(
      result.diagnostics.single.details,
      containsPair('connectedDevices', isEmpty),
    );
    final targetSelection =
        result.diagnostics.single.details['targetSelection'] as Map;
    expect(targetSelection, containsPair('policy', 'emulator-first'));
    expect(targetSelection['recommendation'], contains('DevEco emulator'));
    expect(targetSelection, containsPair('emulators', isEmpty));
  });

  test(
    'suggests lowest and highest API emulators when no device is connected',
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
      final deployed = await _writeEmulatorList(
        root,
        emulators: const [
          {'name': 'OHOS_API_12', 'apiVersion': 12},
          {'name': 'OHOS_API_10', 'apiVersion': 10},
          {'name': 'OHOS_API_15', 'apiVersion': 15},
        ],
      );
      final imageRoot = Directory('${root.path}/Huawei/Sdk')
        ..createSync(recursive: true);
      final devEco = await _writeDevEcoFixture(
        root,
        hdcLog: File('${root.path}/hdc.log'),
        targets: '[Empty]\n',
      );

      final result = await runOhosHapsOnDevice(
        environment: FluohEnvironment(
          homeDirectory: home,
          workingDirectory: project,
          processEnvironment: {
            'FLUOH_DEVECO_STUDIO': devEco.path,
            'FLUOH_OHOS_EMULATOR_DEPLOYED': deployed.path,
            'FLUOH_HARMONYOS_SDK_ROOT': imageRoot.path,
          },
        ),
        ohosDirectory: ohos,
        haps: [hap],
        output: TerminalOutput(stdout: (_) {}),
        logDuration: Duration.zero,
      );

      expect(result.passed, isFalse);
      expect(result.diagnostics.single.code, 'ohos.device_missing');
      final targetSelection =
          result.diagnostics.single.details['targetSelection'] as Map;
      expect(targetSelection, containsPair('policy', 'emulator-first'));
      expect(
        targetSelection['recommendation'],
        contains('lowest and highest API'),
      );
      expect(targetSelection['suggestedRunArguments'], [
        '--auto-emulator',
        '--emulator OHOS_API_10',
        '--emulator OHOS_API_15',
      ]);
      final suggested = targetSelection['suggestedEmulators'] as List;
      expect(suggested, hasLength(2));
      expect(suggested.first, containsPair('apiVersion', 10));
      expect(suggested.last, containsPair('apiVersion', 15));
    },
  );
}
