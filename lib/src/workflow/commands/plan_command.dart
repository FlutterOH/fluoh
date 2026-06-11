import 'dart:io';

import 'package:args/command_runner.dart';

import '../../cli/argument_validation.dart';
import '../../cli/command_usage.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../package/git/package_git.dart';
import '../../package/manifest/package_manifest.dart';
import '../../schema/yaml_utils.dart';
import '../../sdk/sdk_project_config.dart';

/// Top-level `fluoh plan` command group.
class PlanCommand extends FluohCommand<int> {
  /// Creates the plan command group.
  PlanCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    addSubcommand(
      PlanAppCommand(environment: environment, stdout: stdout, output: _output),
    );
    addSubcommand(
      PlanPackageCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
  }

  final TerminalOutput _output;

  @override
  String get name => 'plan';

  @override
  String get description => 'Plan AI-assisted FlutterOH adaptation work.';

  @override
  String get usage => '$description\n\n$_usageWithoutDescription';

  @override
  void printUsage() {
    _output.write(usage);
  }

  @override
  Never usageException(String message) {
    throw UsageException(message, _usageWithoutDescription);
  }

  String get _usageWithoutDescription {
    return [
      'Usage: $invocation',
      argParser.usage,
      '',
      formatCommandUsage(
        subcommands,
        sections: const [
          CommandUsageSection('Adaptation plans:', ['app', 'package']),
        ],
        isSubcommand: true,
        lineLength: argParser.usageLineLength,
        style: _output.style,
      ),
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }
}

/// Prints a read-only plan for continuing a FlutterOH package branch.
class PlanPackageCommand extends FluohCommand<int> {
  /// Creates the package adaptation planning command.
  PlanPackageCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser
      ..addOption(
        'package',
        valueHelp: 'name',
        help: 'Package name. Defaults to the current package branch.',
      )
      ..addFlag('json', negatable: false, help: 'Print the plan as JSON.');
  }

  /// Runtime environment.
  final FluohEnvironment environment;

  /// JSON output writer.
  final OutputWriter stdout;

  final TerminalOutput _output;

  @override
  String get name => 'package';

  @override
  String get description => 'Plan adapting the current package branch to OHOS.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final json = argResults!.flag('json');
    final plan = await _buildPackageAdaptationPlan(
      environment,
      requestedPackage: argResults!.option('package')?.trim(),
    );
    if (json) {
      writeMachineOutput(
        stdout,
        command: 'plan package',
        ok: plan['readyToPlan'] == true,
        exitCode: 0,
        fields: {'changed': false, 'applied': false, 'plan': plan},
      );
    } else {
      _printPlan(plan);
    }
    return 0;
  }

  void _printPlan(Map<String, Object?> plan) {
    _output.success('Package adaptation plan');
    final package = plan['package'] as Map<String, Object?>?;
    _output.info('Package: ${package?['name'] ?? '<unknown>'}');
    _output.info('SDK: ${(plan['sdk'] as Map<String, Object?>)['selected']}');
    final repository = plan['repository'] as Map<String, Object?>?;
    _output.info('Branch: ${repository?['branch'] ?? '<unknown>'}');
    for (final item in plan['queue'] as List<Object?>) {
      final step = item as Map<String, Object?>;
      _output.next(step['command'] as String);
    }
  }
}

/// Prints a read-only plan for adapting a Flutter app project to OHOS.
class PlanAppCommand extends FluohCommand<int> {
  /// Creates the app adaptation planning command.
  PlanAppCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser
      ..addOption(
        'sdk',
        valueHelp: 'version-or-series',
        help: 'FlutterOH SDK version or version series to plan for.',
      )
      ..addFlag('json', negatable: false, help: 'Print the plan as JSON.');
  }

  /// Runtime environment.
  final FluohEnvironment environment;

  /// JSON output writer.
  final OutputWriter stdout;

  final TerminalOutput _output;

  @override
  String get name => 'app';

  @override
  String get description => 'Plan adapting the current Flutter app to OHOS.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final json = argResults!.flag('json');
    final plan = await _buildAppAdaptationPlan(
      environment,
      requestedSdk: argResults!.option('sdk')?.trim(),
    );
    if (json) {
      writeMachineOutput(
        stdout,
        command: 'plan app',
        ok: plan['readyToPlan'] == true,
        exitCode: 0,
        fields: {'changed': false, 'applied': false, 'plan': plan},
      );
    } else {
      _printPlan(plan);
    }
    return 0;
  }

  void _printPlan(Map<String, Object?> plan) {
    _output.success('App adaptation plan');
    _output.info('Project: ${plan['projectName'] ?? '<unknown>'}');
    _output.info('SDK: ${(plan['sdk'] as Map<String, Object?>)['selected']}');
    _output.info(
      'OHOS directory: '
      '${(plan['project'] as Map<String, Object?>)['hasOhos'] == true ? 'present' : 'missing'}',
    );
    for (final item in plan['queue'] as List<Object?>) {
      final step = item as Map<String, Object?>;
      _output.next(step['command'] as String);
    }
  }
}

Future<Map<String, Object?>> _buildAppAdaptationPlan(
  FluohEnvironment environment, {
  required String? requestedSdk,
}) async {
  final root = environment.workingDirectory;
  final pubspec = File('${root.path}/pubspec.yaml');
  final pubspecContent = await pubspec.exists()
      ? await pubspec.readAsString()
      : '';
  final projectName = pubspecContent.isEmpty
      ? null
      : _topLevelString(pubspecContent, 'name');
  final isFlutterProject = _isFlutterProject(pubspecContent);
  final readyToPlan = pubspec.existsSync() && isFlutterProject;
  final selectedSdk = requestedSdk?.isNotEmpty == true
      ? requestedSdk
      : await readProjectSdkVersion(root);
  final sdkValue = selectedSdk ?? '<sdk-version-or-line>';
  final scope = projectName ?? _scopePlaceholder();
  final traceDir =
      '.fluoh/traces/${_scopeSlug(projectName ?? 'app', fallback: 'app')}/adaptation';
  final platforms = {
    for (final platform in const [
      'ohos',
      'android',
      'ios',
      'macos',
      'linux',
      'web',
      'windows',
    ])
      platform: Directory('${root.path}/$platform').existsSync(),
  };
  return {
    'schema': 1,
    'adaptationKind': 'app',
    'readyToPlan': readyToPlan,
    'workingDirectory': root.path,
    'projectName': projectName,
    if (!readyToPlan)
      'error': {
        'message': pubspec.existsSync()
            ? 'Current directory is not a Flutter app project.'
            : 'Missing pubspec.yaml.',
      },
    'project': {
      'hasPubspec': pubspec.existsSync(),
      'isFlutter': isFlutterProject,
      'hasOhos': platforms['ohos'],
      'platformDirectories': platforms,
    },
    'sdk': {
      'selected': sdkValue,
      'source': requestedSdk?.isNotEmpty == true
          ? 'option'
          : selectedSdk == null
          ? 'placeholder'
          : 'fluoh.yaml',
    },
    'queue': readyToPlan
        ? _appAdaptationQueue(
            sdkValue,
            platforms,
            scope: scope,
            traceDir: traceDir,
          )
        : const <Map<String, Object?>>[],
    'safety': _adaptationSafety(),
  };
}

Future<Map<String, Object?>> _buildPackageAdaptationPlan(
  FluohEnvironment environment, {
  required String? requestedPackage,
}) async {
  final root = environment.workingDirectory;
  PackageManifest? manifest;
  Object? manifestError;
  try {
    manifest = await readPackageManifest(root);
  } on Object catch (error) {
    manifestError = error;
  }
  if (manifest == null) {
    return {
      'schema': 1,
      'adaptationKind': 'package',
      'readyToPlan': false,
      'workingDirectory': root.path,
      'error': {
        'message': manifestError is UsageException
            ? manifestError.message
            : manifestError?.toString() ?? 'Missing package fluoh.yaml.',
      },
      'sdk': {'selected': '<sdk-version-or-line>', 'source': 'placeholder'},
      'queue': const <Map<String, Object?>>[],
      'safety': _adaptationSafety(),
    };
  }

  final package = manifest.packageForName(requestedPackage);
  final branch = await _currentBranchOrNull(root);
  final status = await runGit(
    ['status', '--short'],
    workingDirectory: root,
    allowFailure: true,
  );
  final dirty = status.stdout.toString().trim().isNotEmpty;
  final packageDirectory = Directory(
    package.path == '.' ? root.path : '${root.path}/${package.path}',
  );
  final exampleDirectory = Directory('${packageDirectory.path}/example');
  final platforms = _packageExamplePlatforms(exampleDirectory);
  final scope = package.name;
  final traceDir = '.fluoh/traces/$scope/adaptation';
  return {
    'schema': 1,
    'adaptationKind': 'package',
    'readyToPlan': true,
    'workingDirectory': root.path,
    'repository': {
      'url': manifest.repositoryUrl,
      'branch': branch,
      'manifestBranch': manifest.branch,
      'branchMatchesManifest': branch == manifest.branch,
      'dirty': dirty,
      'statusShort': [
        for (final line in status.stdout.toString().split('\n'))
          if (line.trim().isNotEmpty) line,
      ],
    },
    'upstream': {
      'url': manifest.upstreamUrl,
      'branch': manifest.upstreamBranch,
    },
    'sdk': {'selected': manifest.sdkVersion, 'source': 'fluoh.yaml'},
    'package': {
      'name': package.name,
      'path': package.path,
      'upstreamVersion': package.upstreamVersion,
      'upstreamRef': package.upstreamRef,
      'upstreamCommit': package.upstreamCommit,
      'releaseVersion': package.version,
      'releaseStatus': package.status,
      'examplePath': _relativePath(root, exampleDirectory),
      'hasExample': exampleDirectory.existsSync(),
      'examplePlatforms': platforms,
    },
    'queue': _packageAdaptationQueue(scope, traceDir, platforms),
    'safety': _adaptationSafety(),
  };
}

List<Map<String, Object?>> _appAdaptationQueue(
  String sdk,
  Map<String, bool> platforms, {
  required String scope,
  required String traceDir,
}) {
  final items = <Map<String, Object?>>[
    _queueItem(
      phase: 'setup',
      command: 'fluoh source update',
      mutating: true,
      requiresApproval: true,
      evidence: 'source update result',
    ),
    _queueItem(
      phase: 'setup',
      command: 'fluoh sdk use $sdk --pub-get',
      mutating: true,
      requiresApproval: true,
      evidence: 'selected SDK and OHOS platform directory',
    ),
    _queueItem(
      phase: 'deps',
      command: 'fluoh deps check --json',
      mutating: false,
      evidence: 'dependency support JSON',
    ),
    _queueItem(
      phase: 'deps',
      command: 'fluoh deps fix --dry-run --json',
      mutating: false,
      evidence: 'dependency rewrite plan',
    ),
    _queueItem(
      phase: 'deps',
      command: 'fluoh deps fix',
      mutating: true,
      requiresApproval: true,
      evidence: 'pubspec dependency rewrite summary',
    ),
    _queueItem(
      phase: 'ohos',
      command: 'fluoh doctor -p --platform ohos --json --strict',
      mutating: false,
      evidence: 'OHOS toolchain diagnostics',
    ),
    _queueItem(
      phase: 'ohos',
      command: 'fluoh build ohos --auto-sign --json --trace-dir $traceDir',
      mutating: true,
      evidence: 'signed HAP build JSON',
    ),
    _queueItem(
      phase: 'ohos',
      command: 'fluoh devices --platform ohos --json',
      mutating: false,
      evidence: 'connected OHOS target inventory',
    ),
    _queueItem(
      phase: 'ohos',
      command: 'fluoh emulators --platform ohos --json',
      mutating: false,
      evidence: 'local OHOS emulator inventory',
    ),
    _queueItem(
      phase: 'ohos',
      command: 'fluoh run ohos --auto-emulator --json --trace-dir $traceDir',
      mutating: true,
      evidence: 'install, launch, hilog, and runtime findings',
    ),
    _queueItem(
      phase: 'automation',
      command: 'fluoh drive all --json --trace-dir $traceDir',
      mutating: true,
      evidence: 'automation coverage policy, scenarios, and repair queue',
    ),
  ];
  for (final platform in const [
    'android',
    'ios',
    'macos',
    'linux',
    'web',
    'windows',
  ]) {
    if (platforms[platform] != true) {
      continue;
    }
    items.add(
      _queueItem(
        phase: 'regression',
        command: _regressionCommand(platform, traceDir),
        mutating: true,
        evidence: '$platform regression smoke evidence',
      ),
    );
  }
  items.add(
    _queueItem(
      phase: 'report',
      command:
          'fluoh report create --scope $scope --trace-dir $traceDir --json',
      mutating: true,
      evidence: 'local AI report path',
    ),
  );
  return items;
}

List<Map<String, Object?>> _packageAdaptationQueue(
  String packageName,
  String traceDir,
  Map<String, bool> platforms,
) {
  final items = <Map<String, Object?>>[
    _queueItem(
      phase: 'docs',
      command: 'fluoh package docs refresh --dry-run',
      mutating: false,
      evidence: 'generated package docs refresh plan',
    ),
    _queueItem(
      phase: 'docs',
      command: 'fluoh package docs refresh',
      mutating: true,
      requiresApproval: true,
      evidence: 'refreshed FLUOH.md and AGENTS.md generated sections',
    ),
    _queueItem(
      phase: 'verify',
      command:
          'fluoh verify --package $packageName --json --trace-dir $traceDir',
      mutating: false,
      evidence: 'pub get, analysis, tests, and trace manifest',
    ),
    _queueItem(
      phase: 'ohos',
      command: 'fluoh doctor -p --platform ohos --json --strict',
      mutating: false,
      evidence: 'OHOS toolchain diagnostics',
    ),
    _queueItem(
      phase: 'ohos',
      command:
          'fluoh build ohos --package $packageName --auto-sign --json --trace-dir $traceDir',
      mutating: true,
      evidence: 'signed HAP build JSON',
    ),
    _queueItem(
      phase: 'ohos',
      command: 'fluoh devices --platform ohos --json',
      mutating: false,
      evidence: 'connected OHOS target inventory',
    ),
    _queueItem(
      phase: 'ohos',
      command: 'fluoh emulators --platform ohos --json',
      mutating: false,
      evidence: 'local OHOS emulator inventory',
    ),
    _queueItem(
      phase: 'ohos',
      command:
          'fluoh run ohos --package $packageName --auto-emulator --json --trace-dir $traceDir',
      mutating: true,
      evidence: 'install, launch, hilog, and runtime findings',
    ),
    _queueItem(
      phase: 'automation',
      command:
          'fluoh drive all --package $packageName --json --trace-dir $traceDir',
      mutating: true,
      evidence: 'automation coverage policy, scenarios, and repair queue',
    ),
  ];
  for (final platform in const [
    'android',
    'ios',
    'macos',
    'linux',
    'web',
    'windows',
  ]) {
    if (platforms[platform] != true) {
      continue;
    }
    items.add(
      _queueItem(
        phase: 'regression',
        command: _packageRegressionCommand(platform, packageName, traceDir),
        mutating: true,
        evidence: '$platform package example regression evidence',
      ),
    );
  }
  items
    ..add(
      _queueItem(
        phase: 'release-check',
        command: 'fluoh package status --package $packageName',
        mutating: false,
        evidence: 'release readiness summary',
      ),
    )
    ..add(
      _queueItem(
        phase: 'handoff',
        command: 'fluoh package handoff --package $packageName --json',
        mutating: false,
        evidence: 'branch state, reports, traces, and next commands',
      ),
    )
    ..add(
      _queueItem(
        phase: 'report',
        command:
            'fluoh report create --scope $packageName --package $packageName --trace-dir $traceDir --json',
        mutating: true,
        evidence: 'local AI report path',
      ),
    )
    ..add(
      _queueItem(
        phase: 'release-check',
        command: 'fluoh package check --package $packageName --json',
        mutating: false,
        evidence: 'release gate JSON',
      ),
    );
  return items;
}

Map<String, Object?> _queueItem({
  required String phase,
  required String command,
  required bool mutating,
  required String evidence,
  bool requiresApproval = false,
}) {
  return {
    'phase': phase,
    'command': command,
    'mutating': mutating,
    'requiresApproval': requiresApproval || mutating,
    'expectedEvidence': evidence,
  };
}

Map<String, Object?> _adaptationSafety() {
  return {
    'requiresConfirmationBeforeMutation': true,
    'willNotRunWithoutSeparateApproval': [
      'release',
      'push',
      'force-push',
      'destructive git commands',
      'public API breaks',
    ],
  };
}

String _regressionCommand(String platform, String traceDir) {
  return switch (platform) {
    'android' =>
      'fluoh run android --auto-emulator --json --trace-dir $traceDir',
    'ios' => 'fluoh run ios --auto-emulator --json --trace-dir $traceDir',
    'macos' => 'fluoh run macos --json --trace-dir $traceDir',
    'linux' => 'fluoh build linux --json --trace-dir $traceDir',
    'web' =>
      'fluoh run web --device-id web-server --json --trace-dir $traceDir',
    'windows' => 'fluoh build windows --json --trace-dir $traceDir',
    _ => 'fluoh run $platform --json --trace-dir $traceDir',
  };
}

String _packageRegressionCommand(
  String platform,
  String packageName,
  String traceDir,
) {
  return switch (platform) {
    'android' =>
      'fluoh run android --package $packageName --auto-emulator --json --trace-dir $traceDir',
    'ios' =>
      'fluoh run ios --package $packageName --auto-emulator --json --trace-dir $traceDir',
    'macos' =>
      'fluoh run macos --package $packageName --json --trace-dir $traceDir',
    'linux' =>
      'fluoh build linux --package $packageName --json --trace-dir $traceDir',
    'web' =>
      'fluoh run web --package $packageName --device-id web-server --json --trace-dir $traceDir',
    'windows' =>
      'fluoh build windows --package $packageName --json --trace-dir $traceDir',
    _ =>
      'fluoh run $platform --package $packageName --json --trace-dir $traceDir',
  };
}

String _scopePlaceholder() => '<scope>';

String _scopeSlug(String value, {required String fallback}) {
  if (value.startsWith('<') && value.endsWith('>')) {
    return fallback;
  }
  final normalized = value
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^[-._]+|[-._]+$'), '');
  return normalized.isEmpty ? fallback : normalized;
}

Map<String, bool> _packageExamplePlatforms(Directory exampleDirectory) {
  return {
    for (final platform in const [
      'ohos',
      'android',
      'ios',
      'macos',
      'linux',
      'web',
      'windows',
    ])
      platform: Directory('${exampleDirectory.path}/$platform').existsSync(),
  };
}

Future<String?> _currentBranchOrNull(Directory root) async {
  final result = await runGit(
    ['branch', '--show-current'],
    workingDirectory: root,
    allowFailure: true,
  );
  if (result.exitCode != 0) {
    return null;
  }
  final branch = result.stdout.toString().trim();
  return branch.isEmpty ? null : branch;
}

String _relativePath(Directory root, Directory directory) {
  final rootPath = root.absolute.path;
  final path = directory.absolute.path;
  if (path == rootPath) {
    return '.';
  }
  if (path.startsWith('$rootPath/')) {
    return path.substring(rootPath.length + 1);
  }
  return path;
}

bool _isFlutterProject(String content) {
  if (content.trim().isEmpty) {
    return false;
  }
  try {
    final yaml = parseYamlMap(content, label: 'pubspec.yaml');
    final dependencies = yaml['dependencies'];
    return dependencies is Map<String, Object?> &&
        dependencies['flutter'] is Map<String, Object?> &&
        (dependencies['flutter'] as Map<String, Object?>)['sdk'] == 'flutter';
  } on Object {
    return false;
  }
}

String? _topLevelString(String content, String key) {
  try {
    final yaml = parseYamlMap(content, label: 'pubspec.yaml');
    final value = yaml[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  } on Object {
    return null;
  }
}
