import 'dart:io';
import 'dart:isolate';

import 'argument_validation.dart';
import 'fluoh_command_runner.dart';
import 'machine_output.dart';
import 'terminal_output.dart';
import '../version.dart';

const fluohSkillRepository = 'FlutterOH/fluoh';
const fluohSkillRepositoryUrl = 'https://github.com/FlutterOH/fluoh';
const fluohSkillRepositoryPath = 'skills/fluoh';
const fluohSkillUrl =
    '$fluohSkillRepositoryUrl/tree/main/$fluohSkillRepositoryPath';
const fluohSkillUpgradeCommand = 'fluoh upgrade';
const fluohSkillDefaultPrompt =
    'Use \$fluoh to install fluoh if needed and adapt this Flutter project or '
    'package for OHOS.';
const fluohSkillInstallPrompt = 'Install the fluoh skill from $fluohSkillUrl.';
const fluohSkillUpgradePrompt =
    'Upgrade fluoh with `fluoh upgrade`, then run `fluoh skill --json` and '
    'reinstall or reload the returned localPath.';
const _fluohSkillScripts = {
  'preflight': _FluohSkillScript(
    relativePath: 'scripts/preflight.py',
    arguments: ['<workspace>'],
    description:
        'Inspect the workspace and return routing, commands, and '
        'delivery checks as JSON.',
  ),
  'newReport': _FluohSkillScript(
    relativePath: 'scripts/new_report.py',
    arguments: [
      '<workspace>',
      '--scope',
      '<scope>',
      '--recommendation',
      '<ready|needs-maintainer-decision|blocked>',
    ],
    description: 'Create a structured AI delivery report.',
  ),
  'checkReport': _FluohSkillScript(
    relativePath: 'scripts/check_report.py',
    arguments: ['<report-path>'],
    description: 'Validate the AI delivery report before final response.',
  ),
};
const fluohSkillExamplePrompts = [
  'Use \$fluoh to install fluoh if needed and adapt this Flutter project for '
      'OHOS.',
  'Use \$fluoh to adapt <upstream-git-url> for FlutterOH.',
  'Use \$fluoh to continue adapting <package-name> for OHOS.',
];

class SkillCommand extends FluohCommand<int> {
  SkillCommand({
    required void Function(String message) stdout,
    required TerminalOutput output,
  }) : _stdout = stdout,
       _output = output {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print bundled skill details as JSON.',
      )
      ..addFlag(
        'path',
        negatable: false,
        help: 'Print only the bundled skill local path.',
      );
  }

  final void Function(String message) _stdout;
  final TerminalOutput _output;

  @override
  String get name => 'skill';

  @override
  String get description => 'Show bundled AI skill details.';

  @override
  Future<int> run() async {
    final results = argResults!;
    expectNoArguments(results, usageException);

    final location = await resolveFluohSkillLocation();
    if (results.flag('json')) {
      writeMachineOutput(
        _stdout,
        command: name,
        ok: location.available,
        exitCode: location.available ? 0 : 1,
        fields: location.toJson(),
      );
      return location.available ? 0 : 1;
    }

    if (results.flag('path')) {
      if (location.localPath == null) {
        _output.error('Could not locate bundled fluoh skill.');
        return 1;
      }
      _stdout(location.localPath!);
      return 0;
    }

    final style = _output.style;
    _output.write(
      '${style.header('fluoh skill')} ${style.value('bundled AI workflow')}',
    );
    _output.write('${style.label('Version')} $packageVersion');
    if (location.localPath != null) {
      _output.write('${style.label('Local path')} ${location.localPath}');
      _output.write(
        '${style.label('Scripts')} preflight.py, new_report.py, '
        'check_report.py',
      );
    } else {
      _output.warning('Bundled local skill path was not found.');
    }
    _output.write('${style.label('GitHub')} $fluohSkillUrl');
    _output.write('${style.label('Ask AI')} $fluohSkillInstallPrompt');
    _output.write(
      '${style.label('Update')} Run ${style.code(fluohSkillUpgradeCommand)}, '
      'then run ${style.code('fluoh skill --json')} and reinstall or reload '
      'the returned localPath.',
    );
    _output.blank();
    _output.write(
      'First-time setup: ask your AI agent to install from GitHub, then use '
      '${style.code(r'$fluoh')} to adapt an app or package.',
    );
    _output.write(
      'Local or upgrade setup: run ${style.code('fluoh skill --json')}, install '
      'the returned localPath, then reload skills if needed.',
    );
    return location.available ? 0 : 1;
  }
}

/// Location and metadata for the bundled AI skill shipped with the package.
class FluohSkillLocation {
  const FluohSkillLocation({required this.localPath});

  final String? localPath;

  bool get available => localPath != null;

  Map<String, Object?> toJson() => {
    'available': available,
    'skillName': 'fluoh',
    'skillVersion': packageVersion,
    'localPath': localPath,
    'repository': fluohSkillRepository,
    'repositoryUrl': fluohSkillRepositoryUrl,
    'repositoryPath': fluohSkillRepositoryPath,
    'skillUrl': fluohSkillUrl,
    'defaultPrompt': fluohSkillDefaultPrompt,
    'examplePrompts': fluohSkillExamplePrompts,
    'installPrompt': fluohSkillInstallPrompt,
    'upgradeCommand': fluohSkillUpgradeCommand,
    'upgradePrompt': fluohSkillUpgradePrompt,
    'scripts': _fluohSkillScripts.map(
      (name, script) => MapEntry(name, script.toJson(localPath: localPath)),
    ),
  };
}

class _FluohSkillScript {
  const _FluohSkillScript({
    required this.relativePath,
    required this.arguments,
    required this.description,
  });

  final String relativePath;
  final List<String> arguments;
  final String description;

  Map<String, Object?> toJson({required String? localPath}) {
    final path = localPath == null
        ? null
        : [localPath, ...relativePath.split('/')].join(Platform.pathSeparator);
    return {
      'relativePath': relativePath,
      'path': path,
      'argv': [
        'python3',
        path ?? '<localPath>${Platform.pathSeparator}$relativePath',
        ...arguments,
      ],
      'description': description,
    };
  }
}

/// Resolves the installed package root and returns the bundled skill directory.
///
/// Global activation, local path activation, and `dart run` can all place the
/// package in different roots. Resolving through `package:fluoh/fluoh.dart`
/// keeps the reported `localPath` tied to the code that is actually running.
Future<FluohSkillLocation> resolveFluohSkillLocation() async {
  final packageUri = await Isolate.resolvePackageUri(
    Uri.parse('package:fluoh/fluoh.dart'),
  );
  if (packageUri == null || !packageUri.isScheme('file')) {
    return const FluohSkillLocation(localPath: null);
  }

  final packageRoot = File.fromUri(packageUri).parent.parent;
  final skillDirectory = Directory(
    '${packageRoot.path}${Platform.pathSeparator}skills'
    '${Platform.pathSeparator}fluoh',
  );
  if (!skillDirectory.existsSync()) {
    return const FluohSkillLocation(localPath: null);
  }
  return FluohSkillLocation(localPath: skillDirectory.path);
}
