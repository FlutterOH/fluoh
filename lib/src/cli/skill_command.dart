import 'dart:io';
import 'dart:isolate';

import 'argument_validation.dart';
import 'fluoh_command_runner.dart';
import 'machine_output.dart';
import 'terminal_output.dart';
import '../context/fluoh_environment.dart';
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
    'Use \$fluoh to install fluoh if needed, add FlutterOH support to this '
    'Flutter project or package, or precheck this FlutterOH Source change.';

/// Prompt for installing the bundled fluoh skill.
const fluohSkillInstallPrompt =
    'Run `fluoh skill --path`, install the printed path as the fluoh skill, '
    'and overwrite any existing installation. Use $fluohSkillUrl only when '
    'fluoh is not installed yet.';

/// Prompt for updating the bundled fluoh skill.
const fluohSkillUpgradePrompt =
    'Upgrade fluoh with `fluoh upgrade`, then run `fluoh skill --path` and '
    'reinstall or reload the printed path.';

/// Environment override for the bundled skill directory.
const fluohSkillPathEnvironmentKey = 'FLUOH_SKILL_PATH';

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
    description: 'Create a monorepo package support summary report.',
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
    description:
        'AI workflow for adding FlutterOH support to an existing Flutter app.',
  ),
  'packageSupportFlow': _FluohSkillReference(
    relativePath: 'references/package-support-flow.md',
    description:
        'AI workflow for creating or porting FlutterOH package support.',
  ),
  'packageSpecTemplate': _FluohSkillReference(
    relativePath: 'references/package-spec-template.md',
    description:
        'Branch-local package requirements, API, platform, and test template.',
  ),
  'automationEvidenceFlow': _FluohSkillReference(
    relativePath: 'references/automation-evidence-flow.md',
    description:
        'Automation, integration test, and manual-assisted evidence workflow.',
  ),
  'independentReviewFlow': _FluohSkillReference(
    relativePath: 'references/independent-review-flow.md',
    description: 'Host-agent supervision and feedback loop workflow.',
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
  'Use \$fluoh to install fluoh if needed and add FlutterOH support to this '
      'Flutter project.',
  'Use \$fluoh to port <upstream-git-url> for FlutterOH.',
  'Use \$fluoh to continue implementing FlutterOH support for <package-name>.',
  'Use \$fluoh to precheck this FlutterOH Source change.',
];

/// Shows bundled AI skill metadata.
class SkillCommand extends FluohCommand<int> {
  /// Creates the skill metadata command.
  SkillCommand({
    required FluohEnvironment environment,
    required void Function(String message) stdout,
    required TerminalOutput output,
  }) : _environment = environment,
       _stdout = stdout,
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
  final FluohEnvironment _environment;

  @override
  String get name => 'skill';

  @override
  String get description => 'Show bundled AI skill details.';

  @override
  Future<int> run() async {
    final results = argResults!;
    expectNoArguments(results, usageException);

    final location = await resolveFluohSkillLocation(
      environment: _environment.processEnvironment,
      workingDirectory: _environment.workingDirectory,
    );
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
        'package-support-flow.md, package-spec-template.md, '
        'automation-evidence-flow.md, '
        'independent-review-flow.md, source-maintenance-flow.md, '
        'report-template.md, interaction-scenario-template.md',
      );
    } else {
      _output.warning('Bundled local skill path was not found.');
    }
    _output.write('${style.label('GitHub')} $fluohSkillUrl');
    _output.write('${style.label('Ask AI')} $fluohSkillInstallPrompt');
    _output.write(
      '${style.label('Update')} Run ${style.code(fluohSkillUpgradeCommand)}, '
      'then run ${style.code('fluoh skill --path')} and reinstall or reload '
      'the printed path.',
    );
    _output.blank();
    _output.write(
      'Install source: prefer the local path from '
      '${style.code('fluoh skill --path')} when fluoh is installed; use '
      '$fluohSkillUrl only before the CLI is available.',
    );
    _output.write(
      'Then use ${style.code(r'$fluoh')} to add FlutterOH support to an app '
      'or package, or precheck a FlutterOH Source change.',
    );
    _output.write(
      'Local or upgrade setup: run ${style.code('fluoh skill --path')}, install '
      'the printed path, then reload skills if needed.',
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
/// Compiled repository executables can lose package URI context, so callers may
/// pass [workingDirectory] or [fluohSkillPathEnvironmentKey] to locate a
/// checkout-local skill directory without using a pub global shim.
Future<FluohSkillLocation> resolveFluohSkillLocation({
  Map<String, String>? environment,
  Directory? workingDirectory,
}) async {
  final env = environment ?? Platform.environment;
  final configured = env[fluohSkillPathEnvironmentKey]?.trim();
  if (configured != null && configured.isNotEmpty) {
    final configuredDirectory = _resolveSkillDirectory(Directory(configured));
    if (configuredDirectory != null) {
      return FluohSkillLocation(localPath: configuredDirectory.path);
    }
  }

  final packageUri = await Isolate.resolvePackageUri(
    Uri.parse('package:fluoh/fluoh.dart'),
  );
  if (packageUri != null && packageUri.isScheme('file')) {
    final packageRoot = File.fromUri(packageUri).parent.parent;
    final skillDirectory = _resolveSkillDirectory(
      Directory(
        '${packageRoot.path}${Platform.pathSeparator}skills'
        '${Platform.pathSeparator}fluoh',
      ),
    );
    if (skillDirectory != null) {
      return FluohSkillLocation(localPath: skillDirectory.path);
    }
  }

  for (final root in _fallbackSkillSearchRoots(workingDirectory)) {
    final skillDirectory = _findSkillDirectoryFrom(root);
    if (skillDirectory != null) {
      return FluohSkillLocation(localPath: skillDirectory.path);
    }
  }

  return const FluohSkillLocation(localPath: null);
}

Iterable<Directory> _fallbackSkillSearchRoots(
  Directory? workingDirectory,
) sync* {
  if (workingDirectory != null) {
    yield workingDirectory;
  }
  yield Directory.current;

  final script = Platform.script;
  if (script.isScheme('file')) {
    yield File.fromUri(script).parent;
  }

  final executable = Platform.resolvedExecutable;
  if (executable.isNotEmpty) {
    yield File(executable).parent;
  }
}

Directory? _findSkillDirectoryFrom(Directory start) {
  var current = start.absolute;
  while (true) {
    final skillDirectory = _resolveSkillDirectory(
      Directory(
        '${current.path}${Platform.pathSeparator}skills'
        '${Platform.pathSeparator}fluoh',
      ),
    );
    if (skillDirectory != null) {
      return skillDirectory;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      return null;
    }
    current = parent;
  }
}

Directory? _resolveSkillDirectory(Directory directory) {
  final skill = File('${directory.path}${Platform.pathSeparator}SKILL.md');
  return skill.existsSync() ? directory.absolute : null;
}
