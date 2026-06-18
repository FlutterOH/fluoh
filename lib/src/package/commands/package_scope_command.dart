import 'dart:io';

import 'package:args/command_runner.dart';

import '../../cli/argument_validation.dart';
import '../../cli/command_usage.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../manifest/package_manifest.dart';
import '../package_scope.dart';
import '../package_spec.dart';

/// Maintains package support scope.
class PackageScopeCommand extends FluohCommand<int> {
  /// Creates the package scope command group.
  PackageScopeCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    addSubcommand(
      PackageScopeInitCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      PackageScopeCheckCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
        failOnIssues: true,
      ),
    );
    addSubcommand(
      PackageScopeCheckCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
        failOnIssues: false,
      ),
    );
  }

  final TerminalOutput _output;

  @override
  String get name => 'scope';

  @override
  String get description => 'Maintain package support scope.';

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
          CommandUsageSection('Package support scope:', [
            'init',
            'check',
            'status',
          ]),
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

/// Creates package support scope.
class PackageScopeInitCommand extends FluohCommand<int> {
  /// Creates the package scope init command.
  PackageScopeInitCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    required TerminalOutput output,
  }) : _environment = environment,
       _stdout = stdout,
       _output = output {
    argParser
      ..addOption(
        'package',
        valueHelp: 'name',
        help: 'Package to initialize. Defaults to the current package branch.',
      )
      ..addOption(
        'platform',
        defaultsTo: 'ohos',
        valueHelp: 'platform',
        help: 'Target platform for the support scope template.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Overwrite the existing package support scope.',
      )
      ..addFlag(
        'from-spec',
        defaultsTo: true,
        help:
            'Seed scope rows from the Support Scope Seeds table in the package spec.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the initialization result as JSON.',
      );
  }

  final FluohEnvironment _environment;
  final OutputWriter _stdout;
  final TerminalOutput _output;

  @override
  String get name => 'init';

  @override
  String get description => 'Initialize package support scope.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final repository = _environment.workingDirectory;
    final manifest = await readPackageManifest(repository);
    final package = manifest.packageForName(argResults!.option('package'));
    final platform = _trimmedOption('platform') ?? 'ohos';
    final file = packageScopeFile(repository, package.name);
    final exists = await file.exists();
    final force = argResults!.flag('force');
    final json = argResults!.flag('json');
    final seeds = argResults!.flag('from-spec')
        ? await _specScopeSeeds(repository, package.name)
        : const <PackageScopeSeed>[];

    if (exists && !force) {
      final fields = {
        'created': false,
        'overwritten': false,
        'path': packageScopeRelativePath(package.name),
        'package': package.name,
        'platform': platform,
        'error':
            'Package support scope already exists. Use --force to overwrite.',
      };
      if (json) {
        writeMachineOutput(
          _stdout,
          command: 'package scope init',
          ok: false,
          exitCode: 1,
          fields: fields,
        );
      } else {
        _output.error(fields['error']! as String);
      }
      return 1;
    }

    await file.parent.create(recursive: true);
    await file.writeAsString(
      packageScopeTemplate(
        packageName: package.name,
        platform: platform,
        seeds: seeds,
      ),
    );
    final status = await inspectPackageScope(
      repository: repository,
      packageName: package.name,
    );
    final fields = {
      'created': !exists,
      'overwritten': exists && force,
      'path': packageScopeRelativePath(package.name),
      'package': package.name,
      'platform': platform,
      'seededFromSpec': seeds.isNotEmpty,
      'seededScopeEntries': seeds.map((seed) => seed.id).toSet().length,
      'seededPlatformRows': seeds.length,
      'supportScope': status.toJson(),
      'nextCommand':
          'fluoh package scope check --package ${package.name} --json',
    };
    if (json) {
      writeMachineOutput(
        _stdout,
        command: 'package scope init',
        ok: true,
        exitCode: 0,
        fields: fields,
      );
    } else {
      _output.success('Package scope initialized');
      _output.info('Path: ${fields['path']}');
      _output.next(fields['nextCommand']! as String);
    }
    return 0;
  }

  String? _trimmedOption(String name) {
    final value = argResults!.option(name)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<List<PackageScopeSeed>> _specScopeSeeds(
    Directory repository,
    String packageName,
  ) async {
    final file = packageSpecFile(repository, packageName);
    if (!await file.exists()) {
      return const [];
    }
    return packageScopeSeedsFromSpecContent(await file.readAsString());
  }
}

/// Checks or reports package support scope status.
class PackageScopeCheckCommand extends FluohCommand<int> {
  /// Creates the package scope check or status command.
  PackageScopeCheckCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    required TerminalOutput output,
    required bool failOnIssues,
  }) : _environment = environment,
       _stdout = stdout,
       _output = output,
       _failOnIssues = failOnIssues {
    argParser
      ..addOption(
        'package',
        valueHelp: 'name',
        help: 'Package to inspect. Defaults to the current package branch.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print support scope status as JSON.',
      );
  }

  final FluohEnvironment _environment;
  final OutputWriter _stdout;
  final TerminalOutput _output;
  final bool _failOnIssues;

  @override
  String get name => _failOnIssues ? 'check' : 'status';

  @override
  String get description => _failOnIssues
      ? 'Validate package support scope.'
      : 'Report package support scope status.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final repository = _environment.workingDirectory;
    final manifest = await readPackageManifest(repository);
    final package = manifest.packageForName(argResults!.option('package'));
    final status = await inspectPackageScope(
      repository: repository,
      packageName: package.name,
    );
    final exitCode = _failOnIssues && !status.complete ? 1 : 0;
    final json = argResults!.flag('json');
    final fields = {
      'package': package.name,
      'path': status.path,
      'supportScope': status.toJson(),
      'nextCommand': _nextCommand(package.name, status),
    };
    if (json) {
      writeMachineOutput(
        _stdout,
        command: 'package scope $name',
        ok: exitCode == 0,
        exitCode: exitCode,
        fields: fields,
      );
    } else {
      if (status.complete) {
        _output.success('Package scope complete');
      } else {
        _output.info('Package scope needs attention');
      }
      _output.info('Path: ${status.path}');
      if (status.issues.isEmpty) {
        _output.detail('No issues');
      } else {
        for (final issue in status.issues) {
          _output.detail('${issue.code}: ${issue.message}');
        }
      }
      final nextCommand = fields['nextCommand'];
      if (nextCommand is String) {
        _output.next(nextCommand);
      }
    }
    return exitCode;
  }
}

String? _nextCommand(String packageName, PackageScopeStatus status) {
  if (!status.exists) {
    return 'fluoh package scope init --package $packageName --json';
  }
  if (!status.planningReady) {
    return 'edit ${status.path} and rerun fluoh package scope check --package $packageName --json';
  }
  if (!status.functionalEvidenceReady) {
    return 'record functional evidence in ${status.path} and rerun fluoh package scope check --package $packageName --json';
  }
  return null;
}
