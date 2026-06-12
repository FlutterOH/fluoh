import 'dart:io';
import 'dart:isolate';

import 'argument_validation.dart';
import 'fluoh_command_runner.dart';
import 'machine_output.dart';
import 'terminal_output.dart';
import '../version.dart';

/// GitHub repository that contains the bundled fluoh skill.
const fluohSkillRepository = 'FlutterOH/fluoh';

/// Repository URL for the bundled fluoh skill.
const fluohSkillRepositoryUrl = 'https://github.com/FlutterOH/fluoh';

/// Repository-relative path to the bundled fluoh skill.
const fluohSkillRepositoryPath = 'skills/fluoh';

/// Public URL for the bundled fluoh skill.
const fluohSkillUrl =
    '$fluohSkillRepositoryUrl/tree/main/$fluohSkillRepositoryPath';

/// Command users should run before reinstalling an outdated skill.
const fluohSkillUpgradeCommand = 'fluoh upgrade';

/// Default agent prompt for using the fluoh skill.
const fluohSkillDefaultPrompt =
    'Use \$fluoh to install fluoh if needed, adapt this Flutter project or '
    'package for OHOS, or precheck this FlutterOH Source change.';

/// Prompt for installing the bundled fluoh skill.
const fluohSkillInstallPrompt =
    'Run `fluoh skill --json`, install the returned localPath as the fluoh '
    'skill, and overwrite any existing installation. Use $fluohSkillUrl only '
    'when fluoh is not installed yet.';

/// Prompt for updating the bundled fluoh skill.
const fluohSkillUpgradePrompt =
    'Upgrade fluoh with `fluoh upgrade`, then run `fluoh skill --json` and '
    'reinstall or reload the returned localPath.';
const _fluohSkillScripts = {
  'preflight': _FluohSkillScript(
    relativePath: 'scripts/preflight.py',
    arguments: ['<workspace>'],
    description:
        'Inspect the workspace and return routing, command queues, '
        'automation runbook, and delivery gates as JSON.',
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
  'newSummary': _FluohSkillScript(
    relativePath: 'scripts/new_summary.py',
    arguments: ['<workspace>', '--scope', '<scope>'],
    description: 'Create a monorepo package adaptation summary report.',
  ),
  'newScenario': _FluohSkillScript(
    relativePath: 'scripts/new_scenario.py',
    arguments: [
      '<workspace>',
      '--scope',
      '<scope>',
      '--platform',
      '<platform>',
      '--name',
      '<scenario-name>',
    ],
    description:
        'Create a device-side functional interaction scenario skeleton.',
  ),
  'inspectSession': _FluohSkillScript(
    relativePath: 'scripts/inspect_session.py',
    arguments: [
      '<session-file>',
      '--wait',
      '30',
      '--expect-platform',
      '<platform>',
    ],
    description: 'Inspect a live Flutter debug session JSON file.',
  ),
  'collectFeedback': _FluohSkillScript(
    relativePath: 'scripts/collect_feedback.py',
    arguments: ['<trace-dir-or-manifest>'],
    description:
        'Collect trace feedback candidates for the Fluoh Feedback report section.',
  ),
  'checkReport': _FluohSkillScript(
    relativePath: 'scripts/check_report.py',
    arguments: ['<report-path>'],
    description: 'Validate the AI delivery report before final response.',
  ),
};
const _fluohSkillReferences = {
  'appProjectFlow': _FluohSkillReference(
    relativePath: 'references/app-project-flow.md',
    description: 'AI workflow for adapting an existing Flutter app project.',
  ),
  'packageAdaptationFlow': _FluohSkillReference(
    relativePath: 'references/package-adaptation-flow.md',
    description: 'AI workflow for adapting third-party Flutter packages.',
  ),
  'automationEvidenceFlow': _FluohSkillReference(
    relativePath: 'references/automation-evidence-flow.md',
    description:
        'Automation, integration test, and manual-assisted evidence workflow.',
  ),
  'sourceMaintenanceFlow': _FluohSkillReference(
    relativePath: 'references/source-maintenance-flow.md',
    description: 'FlutterOH Source check and maintenance workflow.',
  ),
  'reportTemplate': _FluohSkillReference(
    relativePath: 'references/report-template.md',
    description: 'Structured AI delivery report template.',
  ),
  'interactionScenarioTemplate': _FluohSkillReference(
    relativePath: 'references/interaction-scenario-template.md',
    description:
        'Device-side functional interaction scenario template for flows that '
        'are not fully covered by integration tests.',
  ),
};

/// Example prompts shown to AI agents for using fluoh.
const fluohSkillExamplePrompts = [
  'Use \$fluoh to install fluoh if needed and adapt this Flutter project for '
      'OHOS.',
  'Use \$fluoh to adapt <upstream-git-url> for FlutterOH.',
  'Use \$fluoh to continue adapting <package-name> for OHOS.',
  'Use \$fluoh to precheck this FlutterOH Source change.',
];

/// Shows bundled AI skill metadata.
class SkillCommand extends FluohCommand<int> {
  /// Creates the skill metadata command.
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
        'new_summary.py, new_scenario.py, inspect_session.py, '
        'collect_feedback.py, check_report.py',
      );
      _output.write(
        '${style.label('References')} app-project-flow.md, '
        'package-adaptation-flow.md, automation-evidence-flow.md, '
        'source-maintenance-flow.md, report-template.md, '
        'interaction-scenario-template.md',
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
      'Install source: prefer the local path from '
      '${style.code('fluoh skill --path')} when fluoh is installed; use '
      '$fluohSkillUrl only before the CLI is available.',
    );
    _output.write(
      'Then use ${style.code(r'$fluoh')} to adapt an app or package, or '
      'precheck a FlutterOH Source change.',
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
  /// Creates a bundled skill location value.
  const FluohSkillLocation({required this.localPath});

  /// Local filesystem path to the skill directory, when bundled files exist.
  final String? localPath;

  /// Whether the bundled skill is available on disk.
  bool get available => localPath != null;

  /// Converts this location to the `fluoh skill --json` contract.
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
    'references': _fluohSkillReferences.map(
      (name, reference) =>
          MapEntry(name, reference.toJson(localPath: localPath)),
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

class _FluohSkillReference {
  const _FluohSkillReference({
    required this.relativePath,
    required this.description,
  });

  final String relativePath;
  final String description;

  Map<String, Object?> toJson({required String? localPath}) {
    final path = localPath == null
        ? null
        : [localPath, ...relativePath.split('/')].join(Platform.pathSeparator);
    return {
      'relativePath': relativePath,
      'path': path,
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
