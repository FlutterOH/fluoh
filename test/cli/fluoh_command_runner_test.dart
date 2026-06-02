import 'dart:convert';
import 'dart:io' as io;

import 'package:fluoh/fluoh.dart';
import 'package:args/command_runner.dart';
import 'package:test/test.dart';

void main() {
  test('prints Flutter-style version details from version flag', () async {
    final stdout = <String>[];
    final stderr = <String>[];
    final dartVersion = io.Platform.version.split(' ').first;
    final platformVersion = io.Platform.operatingSystemVersion
        .trim()
        .replaceFirst(RegExp(r'^Version\s+', caseSensitive: false), '')
        .replaceAllMapped(
          RegExp(r'\s*\((?:Build\s+)?([^)]+)\)', caseSensitive: false),
          (match) => ' ${match.group(1)}',
        );

    final exitCode = await runFluoh(
      ['--version'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stdout, [
      'fluoh $packageVersion - CLI for Flutter OHOS SDKs and package workflows',
      'Dart $dartVersion',
      'Platform ${io.Platform.operatingSystem} $platformVersion',
      'Repository https://github.com/FlutterOH/fluoh',
    ]);
    expect(stderr, isEmpty);
  });

  test('does not register a version command', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['version'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 64);
    expect(stdout, isEmpty);
    expect(stderr.join('\n'), contains('Could not find a command named'));
  });

  test('prints bundled AI skill details', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['skill'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stderr, isEmpty);
    final output = stdout.join('\n');
    expect(output, contains('fluoh skill bundled AI workflow'));
    expect(output, contains('Version $packageVersion'));
    expect(output, contains('Local path'));
    expect(output, contains('skills/fluoh'));
    expect(output, contains('Scripts preflight.py, new_report.py'));
    expect(output, contains('new_scenario.py'));
    expect(output, contains('inspect_session.py'));
    expect(output, contains('References report-template.md'));
    expect(output, contains('interaction-scenario-template.md'));
    expect(
      output,
      contains(
        'Install the fluoh skill from '
        'https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh.',
      ),
    );
    expect(output, contains('fluoh skill --json'));
    expect(output, contains('fluoh upgrade'));
  });

  test('prints AI skill path only', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['skill', '--path'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stderr, isEmpty);
    expect(stdout, hasLength(1));
    expect(stdout.single, endsWith('skills/fluoh'));
    expect(io.Directory(stdout.single).existsSync(), isTrue);
  });

  test('prints bundled AI skill details as json', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['skill', '--json'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stderr, isEmpty);
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schemaVersion', 1));
    expect(report, containsPair('command', 'skill'));
    expect(report, containsPair('ok', true));
    expect(report, containsPair('exitCode', 0));
    expect(report, containsPair('available', true));
    expect(report, containsPair('skillName', 'fluoh'));
    expect(report, containsPair('skillVersion', packageVersion));
    expect(report['localPath'], isA<String>());
    expect(report['localPath'], contains('skills/fluoh'));
    expect(report, containsPair('repository', 'FlutterOH/fluoh'));
    expect(
      report,
      containsPair('repositoryUrl', 'https://github.com/FlutterOH/fluoh'),
    );
    expect(report, containsPair('repositoryPath', 'skills/fluoh'));
    expect(
      report,
      containsPair(
        'skillUrl',
        'https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh',
      ),
    );
    expect(
      report,
      containsPair(
        'defaultPrompt',
        'Use \$fluoh to install fluoh if needed and adapt this Flutter project '
            'or package for OHOS.',
      ),
    );
    expect(
      report['examplePrompts'],
      containsAll([
        'Use \$fluoh to install fluoh if needed and adapt this Flutter project '
            'for OHOS.',
        'Use \$fluoh to adapt <upstream-git-url> for FlutterOH.',
        'Use \$fluoh to continue adapting <package-name> for OHOS.',
      ]),
    );
    expect(
      report,
      containsPair(
        'installPrompt',
        'Install the fluoh skill from '
            'https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh.',
      ),
    );
    expect(report, containsPair('upgradeCommand', 'fluoh upgrade'));
    expect(
      report,
      containsPair(
        'upgradePrompt',
        'Upgrade fluoh with `fluoh upgrade`, then run `fluoh skill --json` '
            'and reinstall or reload the returned localPath.',
      ),
    );
    final scripts = report['scripts'] as Map<String, Object?>;
    expect(
      scripts.keys,
      containsAll([
        'preflight',
        'newReport',
        'newScenario',
        'inspectSession',
        'checkReport',
      ]),
    );
    final preflight = scripts['preflight'] as Map<String, Object?>;
    expect(preflight['relativePath'], 'scripts/preflight.py');
    expect(preflight['path'], allOf(isA<String>(), contains('preflight.py')));
    expect(
      preflight['argv'],
      containsAllInOrder(['python3', contains('preflight.py'), '<workspace>']),
    );
    final newReport = scripts['newReport'] as Map<String, Object?>;
    expect(newReport['relativePath'], 'scripts/new_report.py');
    expect(
      newReport['argv'],
      containsAllInOrder(['python3', contains('new_report.py'), '--scope']),
    );
    expect(newReport['argv'], isNot(contains('--root')));
    expect(newReport['argv'], isNot(contains('--type')));
    final newScenario = scripts['newScenario'] as Map<String, Object?>;
    expect(newScenario['relativePath'], 'scripts/new_scenario.py');
    expect(
      newScenario['argv'],
      containsAllInOrder([
        'python3',
        contains('new_scenario.py'),
        '<workspace>',
        '--scope',
        '<scope>',
        '--platform',
        '<platform>',
        '--name',
        '<scenario-name>',
      ]),
    );
    final inspectSession = scripts['inspectSession'] as Map<String, Object?>;
    expect(inspectSession['relativePath'], 'scripts/inspect_session.py');
    expect(
      inspectSession['argv'],
      containsAllInOrder([
        'python3',
        contains('inspect_session.py'),
        '<session-file>',
        '--wait',
        '30',
        '--expect-platform',
        '<platform>',
      ]),
    );
    final checkReport = scripts['checkReport'] as Map<String, Object?>;
    expect(checkReport['relativePath'], 'scripts/check_report.py');
    expect(
      checkReport['argv'],
      containsAllInOrder(['python3', contains('check_report.py')]),
    );
    final references = report['references'] as Map<String, Object?>;
    expect(
      references.keys,
      containsAll(['reportTemplate', 'interactionScenarioTemplate']),
    );
    final reportTemplate = references['reportTemplate'] as Map<String, Object?>;
    expect(reportTemplate['relativePath'], 'references/report-template.md');
    expect(
      reportTemplate['path'],
      allOf(isA<String>(), contains('report-template.md')),
    );
    final scenarioTemplate =
        references['interactionScenarioTemplate'] as Map<String, Object?>;
    expect(
      scenarioTemplate['relativePath'],
      'references/interaction-scenario-template.md',
    );
    expect(
      scenarioTemplate['path'],
      allOf(isA<String>(), contains('interaction-scenario-template.md')),
    );
  });

  test('advertised AI skill script argv can be executed', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['skill', '--json'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stderr, isEmpty);
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    final scripts = report['scripts'] as Map<String, Object?>;
    final references = report['references'] as Map<String, Object?>;

    final workspace = await io.Directory.systemTemp.createTemp(
      'fluoh_skill_scripts_',
    );
    addTearDown(() async {
      if (await workspace.exists()) {
        await workspace.delete(recursive: true);
      }
    });
    await io.File('${workspace.path}/pubspec.yaml').writeAsString('''
name: fixture_app

dependencies:
  flutter:
    sdk: flutter
''');

    final preflight = await _runAdvertisedScript(
      scripts,
      'preflight',
      replacements: {'<workspace>': workspace.path},
    );
    expect(preflight.exitCode, 0, reason: preflight.stderr.toString());
    final preflightJson =
        jsonDecode(preflight.stdout.toString()) as Map<String, Object?>;
    expect(preflightJson['project'], containsPair('kind', 'app-project'));

    final newReport = await _runAdvertisedScript(
      scripts,
      'newReport',
      replacements: {
        '<workspace>': workspace.path,
        '<scope>': 'fixture_app',
        '<ready|needs-maintainer-decision|blocked>': 'blocked',
      },
    );
    expect(newReport.exitCode, 0, reason: newReport.stderr.toString());
    final reportPath = newReport.stdout.toString().trim();
    expect(await io.File(reportPath).exists(), isTrue);

    final newScenario = await _runAdvertisedScript(
      scripts,
      'newScenario',
      replacements: {
        '<workspace>': workspace.path,
        '<scope>': 'fixture_app',
        '<platform>': 'ohos',
        '<scenario-name>': 'permission flow',
      },
    );
    expect(newScenario.exitCode, 0, reason: newScenario.stderr.toString());
    final scenarioPath = newScenario.stdout.toString().trim();
    final scenarioFile = io.File(scenarioPath);
    expect(await scenarioFile.exists(), isTrue);
    final scenarioContent = await scenarioFile.readAsString();
    expect(scenarioContent, contains('# permission flow'));
    expect(scenarioContent, contains('- Scope: fixture_app'));
    expect(scenarioContent, contains('- Platform: ohos'));
    expect(scenarioContent, contains('functional correctness'));
    final scenarioTemplate =
        references['interactionScenarioTemplate'] as Map<String, Object?>;
    expect(
      await io.File(scenarioTemplate['path']! as String).readAsString(),
      contains('functional correctness'),
    );

    final sessionFile = io.File('${workspace.path}/session.json');
    await sessionFile.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'kind': 'flutterRunSession',
        'status': 'running',
        'platform': 'android',
        'processId': 42,
        'launchDetected': true,
        'vmServiceUri': 'http://127.0.0.1:12345/abc=/',
        'target': {'id': 'emulator-5554'},
        'updatedAt': '2026-06-01T00:00:00.000',
      }),
    );
    final inspectSession = await _runAdvertisedScript(
      scripts,
      'inspectSession',
      replacements: {
        '<session-file>': sessionFile.path,
        '<platform>': 'android',
      },
    );
    expect(
      inspectSession.exitCode,
      0,
      reason: inspectSession.stderr.toString(),
    );
    final sessionJson =
        jsonDecode(inspectSession.stdout.toString()) as Map<String, Object?>;
    expect(sessionJson, containsPair('ok', true));
    expect(sessionJson, containsPair('recommendation', 'attach-vm-service'));

    final checkReport = await _runAdvertisedScript(
      scripts,
      'checkReport',
      replacements: {'<report-path>': reportPath},
    );
    expect(checkReport.exitCode, 1);
    final checkJson =
        jsonDecode(checkReport.stdout.toString()) as Map<String, Object?>;
    expect(checkJson, containsPair('ok', false));
    expect(
      checkJson['errors'],
      contains(
        'Commands table must include at least one concrete command row.',
      ),
    );
  });

  test('prints machine-readable usage errors when json is requested', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['doctor', '--json', 'extra'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 64);
    expect(stderr, isEmpty);
    final report = jsonDecode(stdout.single) as Map<String, Object?>;
    expect(report, containsPair('schemaVersion', 1));
    expect(report, containsPair('command', 'doctor'));
    expect(report, containsPair('ok', false));
    expect(report, containsPair('exitCode', 64));
    expect(
      report['error'],
      allOf(
        isA<Map<String, Object?>>(),
        containsPair('type', 'usage'),
        containsPair('message', contains('Unexpected argument')),
      ),
    );
  });

  test('does not treat passthrough --machine as fluoh json mode', () async {
    final home = await io.Directory.systemTemp.createTemp('fluoh_test_home_');
    final project = await io.Directory.systemTemp.createTemp(
      'fluoh_test_project_',
    );
    final stdout = <String>[];
    final stderr = <String>[];

    try {
      final exitCode = await runFluoh(
        ['flutter', '--machine'],
        environment: FluohEnvironment(
          homeDirectory: home,
          workingDirectory: project,
        ),
        stdout: stdout.add,
        stderr: stderr.add,
      );

      expect(exitCode, 64);
      expect(stdout, isEmpty);
      expect(stderr.join('\n'), contains('No SDK selected'));
    } finally {
      await home.delete(recursive: true);
      await project.delete(recursive: true);
    }
  });

  test('suggests similar top-level command names', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['docter'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 64);
    expect(stdout, isEmpty);
    final output = stderr.join('\n');
    expect(output, contains('Could not find a command named "docter".'));
    expect(output, contains('Did you mean one of these?'));
    expect(output, contains('  fluoh doctor'));
    expect(output, contains('  fluoh doctor\n\nUsage:'));
  });

  test('suggests similar subcommand names', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['deps', 'chek'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 64);
    expect(stdout, isEmpty);
    final output = stderr.join('\n');
    expect(
      output,
      contains('Could not find a subcommand named "chek" for "fluoh deps".'),
    );
    expect(output, contains('Did you mean one of these?'));
    expect(output, contains('  fluoh deps check'));
    expect(output, contains('  fluoh deps check\n\nUsage:'));
  });

  test(
    'prints parent command help instead of suggestions when help is set',
    () async {
      final stdout = <String>[];
      final stderr = <String>[];

      final exitCode = await runFluoh(
        ['deps', '--help', 'udpate'],
        stdout: stdout.add,
        stderr: stderr.add,
      );

      expect(exitCode, 0);
      final output = stdout.join('\n');
      expect(output, contains('Manage FlutterOH project dependencies.'));
      expect(output, contains('Usage: fluoh deps <subcommand> [arguments]'));
      expect(output, isNot(contains('Did you mean one of these?')));
      expect(stderr, isEmpty);
    },
  );

  test('suggests upgrade for pub update-style command typos', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final topLevelExitCode = await runFluoh(
      ['udpate'],
      stdout: stdout.add,
      stderr: stderr.add,
    );
    final topLevelOutput = stderr.join('\n');

    expect(topLevelExitCode, 64);
    expect(stdout, isEmpty);
    expect(
      topLevelOutput,
      contains('Could not find a command named "udpate".'),
    );
    expect(topLevelOutput, contains('Did you mean one of these?'));
    expect(topLevelOutput, contains('  fluoh upgrade'));

    stderr.clear();
    final subcommandExitCode = await runFluoh(
      ['deps', 'udpate'],
      stdout: stdout.add,
      stderr: stderr.add,
    );
    final subcommandOutput = stderr.join('\n');

    expect(subcommandExitCode, 64);
    expect(stdout, isEmpty);
    expect(
      subcommandOutput,
      contains('Could not find a subcommand named "udpate" for "fluoh deps".'),
    );
    expect(subcommandOutput, contains('Did you mean one of these?'));
    expect(subcommandOutput, contains('  fluoh deps upgrade'));
  });

  test('suggests commands from short prefixes', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['upg'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 64);
    expect(stdout, isEmpty);
    final output = stderr.join('\n');
    expect(output, contains('Could not find a command named "upg".'));
    expect(output, contains('Did you mean one of these?'));
    expect(output, contains('  fluoh upgrade'));
  });

  test('suggests semantic command aliases without executing them', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final depsExitCode = await runFluoh(
      ['deps', 'install'],
      stdout: stdout.add,
      stderr: stderr.add,
    );
    final depsOutput = stderr.join('\n');

    expect(depsExitCode, 64);
    expect(stdout, isEmpty);
    expect(
      depsOutput,
      contains('Could not find a subcommand named "install" for "fluoh deps".'),
    );
    expect(depsOutput, contains('Did you mean one of these?'));
    expect(depsOutput, contains('  fluoh deps get'));

    stderr.clear();
    final sdkExitCode = await runFluoh(
      ['sdk', 'rm'],
      stdout: stdout.add,
      stderr: stderr.add,
    );
    final sdkOutput = stderr.join('\n');

    expect(sdkExitCode, 64);
    expect(stdout, isEmpty);
    expect(
      sdkOutput,
      contains('Could not find a subcommand named "rm" for "fluoh sdk".'),
    );
    expect(sdkOutput, contains('Did you mean one of these?'));
    expect(sdkOutput, contains('  fluoh sdk remove'));
  });

  test('does not execute update as an upgrade alias', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['update'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 64);
    expect(stdout, isEmpty);
    final output = stderr.join('\n');
    expect(output, contains('Could not find a command named "update".'));
    expect(output, contains('Did you mean one of these?'));
    expect(output, contains('  fluoh upgrade'));
  });

  test('runs registered commands', () async {
    final runner = FluohCommandRunner(commands: [_FixtureCommand()]);

    final exitCode = await runner.run(['fixture']);

    expect(exitCode, 37);
  });

  test('registers doctor command', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stdout.join('\n'), contains('doctor'));
    expect(stderr, isEmpty);
  });

  test('registers deps command group', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    expect(stdout.join('\n'), contains('deps'));
    expect(stdout.join('\n'), contains('package'));
    expect(stderr, isEmpty);
  });

  test('rejects unexpected doctor arguments', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['doctor', 'extra'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 64);
    expect(stdout, isEmpty);
    expect(stderr.join('\n'), contains('Unexpected argument: extra.'));
  });

  test('prints top-level commands by workflow group', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    final help = stdout.join('\n');
    _expectInOrder(help, [
      'Fluoh',
      '  doctor',
      '  upgrade',
      '  skill',
      '\nSDK\n',
      '  source',
      '  sdk',
      'Project',
      '  flutter',
      '  deps',
      '  verify',
      '  build',
      '  run',
      'Package',
      '  package',
      'Tools & Devices',
      '  devices',
      '  emulators',
    ]);
    expect(help, isNot(contains('  use')));
    expect(help, isNot(contains('  update')));
    expect(
      help,
      contains(
        'Shortcut: use "fluohf <flutter-args>" for '
        '"fluoh flutter <flutter-args>".',
      ),
    );
    expect(stderr, isEmpty);
  });

  test('prints moved workflow commands under their command groups', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    expect(
      await runFluoh(['sdk', '--help'], stdout: stdout.add, stderr: stderr.add),
      0,
    );
    var help = stdout.join('\n');
    _expectInOrder(help, [
      '  list',
      '  install',
      '  current',
      '  remove',
      '  use',
    ]);

    stdout.clear();
    expect(
      await runFluoh(
        ['package', '--help'],
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    help = stdout.join('\n');
    _expectInOrder(help, [
      '  list',
      '  create',
      '  add',
      '  sync',
      '  status',
      '  version',
      '  check',
      '  release',
    ]);
    expect(help, isNot(contains('  tag')));

    stdout.clear();
    expect(
      await runFluoh(
        ['verify', '--help'],
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    help = stdout.join('\n');
    expect(help, contains('Usage: fluoh verify'));
    expect(help, contains('--package=<name>'));
    expect(help, isNot(contains('  baseline')));
    expect(help, isNot(contains('  release')));

    stdout.clear();
    expect(
      await runFluoh(
        ['build', '--help'],
        stdout: stdout.add,
        stderr: stderr.add,
      ),
      0,
    );
    help = stdout.join('\n');
    expect(help, contains('Usage: fluoh build'));
    expect(help, contains('Build a FlutterOH project or package example.'));
    expect(help, contains('Generate temporary OHOS debug signing'));
    expect(help, contains('project or package example.'));
    expect(stderr, isEmpty);
  });

  test('prints deps command help', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['deps', '--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    final help = stdout.join('\n');
    expect(help, contains('Manage FlutterOH project dependencies.'));
    expect(help, contains('get'));
    expect(help, contains('check'));
    expect(help, contains('fix'));
    expect(help, contains('upgrade'));
    expect(help, isNot(contains('create')));
    expect(help, isNot(contains('sync')));
    expect(help, isNot(contains('release')));
    expect(stderr, isEmpty);
  });

  test('prints package create upstream help', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['package', 'create', '--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    final help = stdout.join('\n');
    expect(help, contains('Usage: fluoh package create <upstream>'));
    expect(help, contains('Upstream: Git URL or local Git repo path.'));
    expect(help, contains('--package-path'));
    expect(help, contains('--repository'));
    expect(help, contains('--git-author-name'));
    expect(help, contains('--git-author-email'));
    expect(stderr, isEmpty);
  });

  test('wraps leaf command option help at terminal width', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['verify', '--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    final help = stdout.join('\n');
    expect(help, contains('    --package=<name>'));
    expect(help, contains('registered in fluoh.yaml.'));
    expect(help.split('\n').where((line) => line.length > 80), isEmpty);
    expect(stderr, isEmpty);
  });

  test('prints package create upstream argument guidance', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['package', 'create'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 64);
    expect(stdout, isEmpty);
    final error = stderr.join('\n');
    expect(
      error,
      contains('Expected <upstream>: Git URL or local Git repo path.'),
    );
    expect(error, contains('Usage: fluoh package create <upstream>'));
    expect(error, contains('Upstream: Git URL or local Git repo path.'));
  });

  test('prints package subcommands in lifecycle order', () async {
    final stdout = <String>[];
    final stderr = <String>[];

    final exitCode = await runFluoh(
      ['package', '--help'],
      stdout: stdout.add,
      stderr: stderr.add,
    );

    expect(exitCode, 0);
    final help = stdout.join('\n');
    expect(help, contains('Maintain FlutterOH package repositories.'));
    _expectInOrder(help, [
      'Source packages:',
      '  list',
      'Package repositories:',
      '  create',
      '  add',
      '  sync',
      '  status',
      '  version',
      '  check',
      '  release',
    ]);
    expect(help, isNot(contains('  tag')));
    expect(stderr, isEmpty);
  });
}

class _FixtureCommand extends Command<int> {
  @override
  String get name => 'fixture';

  @override
  String get description => 'Fixture command for command registration tests.';

  @override
  int run() => 37;
}

void _expectInOrder(String text, List<String> needles) {
  var previous = -1;
  for (final needle in needles) {
    final index = text.indexOf(needle);
    expect(index, isNonNegative, reason: 'Missing "$needle" in help output.');
    expect(index, greaterThan(previous), reason: 'Expected "$needle" later.');
    previous = index;
  }
}

Future<io.ProcessResult> _runAdvertisedScript(
  Map<String, Object?> scripts,
  String name, {
  required Map<String, String> replacements,
}) {
  final script = scripts[name] as Map<String, Object?>;
  final argv = (script['argv'] as List<Object?>)
      .cast<String>()
      .map((value) {
        return replacements[value] ?? value;
      })
      .toList(growable: false);
  return io.Process.run(argv.first, argv.skip(1).toList());
}
