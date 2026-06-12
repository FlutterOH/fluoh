part of 'device_runner_test.dart';

void _registerOhosDeviceRunnerFailureTests() {
  test('returns diagnostics when runtime crash lines are found', () async {
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
      crashHilog: true,
    );

    final result = await runOhosHapsOnDevice(
      environment: FluohEnvironment(
        homeDirectory: home,
        workingDirectory: project,
        processEnvironment: {'FLUOH_DEVECO_STUDIO': devEco.path},
      ),
      ohosDirectory: ohos,
      haps: [hap],
      output: TerminalOutput(stdout: (_) {}),
      logDuration: const Duration(milliseconds: 10),
    );

    expect(result.passed, isFalse);
    expect(
      result.findings,
      contains('E CppCrash Process crashed with SIGSEGV'),
    );
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.code, 'ohos.runtime_crash');
    expect(
      result.diagnostics.single.details,
      containsPair('findings', result.findings),
    );
  });

  test(
    'returns diagnostics when Flutter plugin channels are not implemented',
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
        flutterMissingPluginHilog: true,
      );

      final result = await runOhosHapsOnDevice(
        environment: FluohEnvironment(
          homeDirectory: home,
          workingDirectory: project,
          processEnvironment: {'FLUOH_DEVECO_STUDIO': devEco.path},
        ),
        ohosDirectory: ohos,
        haps: [hap],
        output: TerminalOutput(stdout: (_) {}),
        logDuration: const Duration(milliseconds: 10),
      );

      expect(result.passed, isFalse);
      expect(
        result.findings,
        contains('W A000ff/Flutter: MethodChannel# --> method not implemented'),
      );
      expect(result.diagnostics, hasLength(1));
      expect(result.diagnostics.single.code, 'ohos.runtime_crash');
      expect(
        result.diagnostics.single.details,
        containsPair('findings', result.findings),
      );
    },
  );

  test('drains hilog before classifying runtime crashes', () async {
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
      shutdownCrashHilog: true,
    );

    final result = await runOhosHapsOnDevice(
      environment: FluohEnvironment(
        homeDirectory: home,
        workingDirectory: project,
        processEnvironment: {'FLUOH_DEVECO_STUDIO': devEco.path},
      ),
      ohosDirectory: ohos,
      haps: [hap],
      output: TerminalOutput(stdout: (_) {}),
      logDuration: const Duration(milliseconds: 10),
    );

    expect(result.passed, isFalse);
    expect(
      result.findings,
      contains('E CppCrash Process crashed with SIGABRT'),
    );
    expect(
      result.logFile!.readAsStringSync(),
      contains('E CppCrash Process crashed with SIGABRT'),
    );
  });

  test('does not block when clearing old hilog output hangs', () async {
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
      hangClearHilog: true,
    );

    final result = await runOhosHapsOnDevice(
      environment: FluohEnvironment(
        homeDirectory: home,
        workingDirectory: project,
        processEnvironment: {'FLUOH_DEVECO_STUDIO': devEco.path},
      ),
      ohosDirectory: ohos,
      haps: [hap],
      output: TerminalOutput(stdout: (_) {}),
      logDuration: const Duration(milliseconds: 10),
    );

    expect(result.passed, isTrue, reason: result.reason);
    expect(result.logFile!.readAsStringSync(), contains('app started'));
  });

  test('returns diagnostics when hdc devicesing fails', () async {
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
      listTargetsExitCode: 1,
    );

    final result = await runOhosHapsOnDevice(
      environment: FluohEnvironment(
        homeDirectory: home,
        workingDirectory: project,
        processEnvironment: {'FLUOH_DEVECO_STUDIO': devEco.path},
      ),
      ohosDirectory: ohos,
      haps: [hap],
      output: TerminalOutput(stdout: (_) {}),
      logDuration: Duration.zero,
    );

    expect(result.passed, isFalse);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.code, 'ohos.hdc_targets_failed');
    expect(result.diagnostics.single.details['error'], contains('hdc offline'));
  });

  test('returns diagnostics when launch info is missing', () async {
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
    await File('${ohos.path}/entry/src/main/module.json5').writeAsString('''
{
  "module": {
    "name": "entry",
    "type": "entry"
  }
}
''');
    final hap = File('${project.path}/entry-default-signed.hap')
      ..writeAsStringSync('hap');
    final devEco = await _writeDevEcoFixture(
      root,
      hdcLog: File('${root.path}/hdc.log'),
    );

    final result = await runOhosHapsOnDevice(
      environment: FluohEnvironment(
        homeDirectory: home,
        workingDirectory: project,
        processEnvironment: {'FLUOH_DEVECO_STUDIO': devEco.path},
      ),
      ohosDirectory: ohos,
      haps: [hap],
      output: TerminalOutput(stdout: (_) {}),
      logDuration: Duration.zero,
    );

    expect(result.passed, isFalse);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.code, 'ohos.launch_info_missing');
  });
}
