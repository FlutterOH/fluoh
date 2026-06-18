import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../cli/argument_validation.dart';
import '../cli/command_usage.dart';
import '../cli/fluoh_command_runner.dart';
import '../cli/machine_output.dart';
import '../cli/terminal_output.dart';
import '../config/fluoh_config.dart';
import '../context/fluoh_environment.dart';
import '../package/git/package_git.dart';
import '../package/manifest/package_manifest.dart';
import '../schema/schema.dart';
import 'source_runtime.dart';
import 'source_check_command.dart';
import 'source_sync.dart';

part 'source_sync_command.dart';
part 'source_sync_command_support.dart';
part 'source_config_commands.dart';

/// Top-level `fluoh source` command group.
class SourceCommand extends FluohCommand<int> {
  /// Creates the Source command group and subcommands.
  SourceCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    addSubcommand(
      SourceListCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      SourceStatsCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      SourceInitCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      SourceSyncCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      SourceRegisterCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      SourceCheckCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      SourceEnableCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      SourceDisableCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
    addSubcommand(
      SourceUpdateCommand(
        environment: environment,
        stdout: stdout,
        output: _output,
      ),
    );
  }

  final TerminalOutput _output;

  @override
  String get name => 'source';

  @override
  String get description => 'Manage FlutterOH package metadata sources.';

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
        sections: _sourceCommandSections,
        isSubcommand: true,
        lineLength: argParser.usageLineLength,
        style: _output.style,
      ),
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }
}

const _sourceCommandSections = [
  CommandUsageSection('Configured sources:', [
    'list',
    'stats',
    'enable',
    'disable',
    'update',
  ]),
  CommandUsageSection('Source repositories:', [
    'init',
    'register',
    'sync',
    'check',
  ]),
];

/// Lists configured Source entries.
class SourceListCommand extends FluohCommand<int> {
  /// Creates the Source list command.
  SourceListCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print configured sources as JSON.',
    );
  }

  /// Runtime environment containing persisted config paths.
  final FluohEnvironment environment;

  /// Writer used for plain output.
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'list';

  @override
  String get description => 'List Sources enabled on this machine.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final config = await FluohConfigStore(environment).load();
    final sources = config.sources.entries.toList(growable: false);
    if (argResults!.flag('json')) {
      writeMachineOutput(
        stdout,
        command: 'source list',
        ok: true,
        exitCode: 0,
        fields: {
          'count': sources.length,
          'sources': [
            for (final entry in sources)
              {
                'name': entry.key,
                'source': entry.value.displayValue,
                'path': entry.value.path,
                if (entry.value.url != null) 'url': entry.value.url,
                'priority': entry.value.priority,
              },
          ],
        },
      );
      return 0;
    }
    if (config.sources.isEmpty) {
      _output.warning('No sources configured');
      return 0;
    }

    if (_output.style.capabilities.decorated) {
      _output.table(
        columns: const [
          TerminalTableColumn('#', style: TerminalTableCellStyle.muted),
          TerminalTableColumn('Name', style: TerminalTableCellStyle.value),
          TerminalTableColumn('Source', style: TerminalTableCellStyle.path),
        ],
        rows: [
          for (var index = 0; index < sources.length; index += 1)
            [
              '${index + 1}',
              sources[index].key,
              sources[index].value.displayValue,
            ],
        ],
      );
      return 0;
    }

    var index = 1;
    for (final entry in sources) {
      stdout('[$index] ${entry.key} ${entry.value.displayValue}');
      index += 1;
    }
    return 0;
  }
}

/// Prints FlutterOH Source package compatibility statistics.
class SourceStatsCommand extends FluohCommand<int> {
  /// Creates the Source stats command.
  SourceStatsCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser
      ..addOption(
        'sdk',
        valueHelp: 'version-or-line',
        help: 'Limit stats to one FlutterOH SDK version or SDK line.',
      )
      ..addFlag('json', negatable: false, help: 'Print Source stats as JSON.');
  }

  /// Runtime environment containing persisted config paths.
  final FluohEnvironment environment;

  /// Writer used for plain output.
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'stats';

  @override
  String get description => 'Summarize FlutterOH Source package coverage.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final sdkFilter = _sdkLineFilter(argResults!.option('sdk'));
    final runtime = SourceRuntime(environment);
    final sdkIndex = await runtime.loadSdkIndex();
    final packageIndex = await runtime.loadPackageIndex(
      releaseStatuses: unrestrictedDependencyReleaseStatuses,
    );
    final stats = _SourceStats.fromIndexes(
      sdkIndex: sdkIndex,
      packageIndex: packageIndex,
      sdkLineFilter: sdkFilter,
    );

    if (argResults!.flag('json')) {
      writeMachineOutput(
        stdout,
        command: 'source stats',
        ok: true,
        exitCode: 0,
        fields: stats.toJson(),
      );
      return 0;
    }

    if (stats.sdks.isEmpty) {
      _output.warning('No FlutterOH SDK package coverage found');
      return 0;
    }
    if (_output.style.capabilities.decorated) {
      _output.table(
        columns: const [
          TerminalTableColumn('SDK', style: TerminalTableCellStyle.value),
          TerminalTableColumn('Line', style: TerminalTableCellStyle.muted),
          TerminalTableColumn('Packages', style: TerminalTableCellStyle.value),
          TerminalTableColumn(
            'Compatible',
            style: TerminalTableCellStyle.status,
          ),
          TerminalTableColumn(
            'Experimental',
            style: TerminalTableCellStyle.muted,
          ),
          TerminalTableColumn('Broken', style: TerminalTableCellStyle.status),
        ],
        rows: [
          for (final sdk in stats.sdks)
            [
              sdk.version ?? '(line only)',
              sdk.line,
              '${sdk.supportedCount}',
              '${sdk.implementedCount}',
              '${sdk.experimentalCount}',
              '${sdk.brokenCount}',
            ],
        ],
      );
      return 0;
    }

    stdout('FlutterOH Source package coverage:');
    for (final sdk in stats.sdks) {
      stdout(
        '- ${sdk.version ?? sdk.line}: ${sdk.supportedCount} packages '
        '(${sdk.implementedCount} compatible, '
        '${sdk.experimentalCount} experimental, ${sdk.brokenCount} broken)',
      );
    }
    return 0;
  }

  String? _sdkLineFilter(String? value) {
    final query = value?.trim();
    if (query == null || query.isEmpty) {
      return null;
    }
    if (RegExp(r'^\d+\.\d+$').hasMatch(query)) {
      return query;
    }
    try {
      return sdkLineFromSdkVersion(query);
    } on FormatException {
      usageException(
        'Expected --sdk to be a FlutterOH SDK version or SDK line.',
      );
    }
  }
}

/// Creates a local Source repository template.
class SourceInitCommand extends FluohCommand<int> {
  /// Creates the Source init command.
  SourceInitCommand({
    required this.environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout);

  /// Runtime environment used to resolve template paths.
  final FluohEnvironment environment;
  final TerminalOutput _output;

  @override
  String get name => 'init';

  @override
  String get description => 'Create a local source repository template.';

  @override
  String get invocation => 'fluoh source init <path>';

  @override
  Future<int> run() async {
    final rest = expectArgumentCount(
      argResults!,
      1,
      'Expected a local source path.',
      usageException,
    );
    final source = _resolveUserSourceDirectory(
      environment.workingDirectory,
      Directory(rest.single),
    );
    final metadata = File('${source.path}/fluoh.yaml');
    final exampleManifest = File('${source.path}/manifests/example/fluoh.yaml');
    final readme = File('${source.path}/README.md');
    final existed =
        await metadata.exists() ||
        await exampleManifest.exists() ||
        await readme.exists();

    await exampleManifest.parent.create(recursive: true);
    if (!await metadata.exists()) {
      await source.create(recursive: true);
      await metadata.writeAsString(_localSourceMetadata());
    }
    if (!await exampleManifest.exists()) {
      await exampleManifest.writeAsString(_localSourceManifestTemplate());
    }
    if (!await readme.exists()) {
      await readme.writeAsString(_localSourceReadme());
    }

    if (existed) {
      _output.skipped(
        'Local source template already exists at ${_output.style.path(source.path)}',
      );
    } else {
      _output.success(
        'Created local source template at ${_output.style.path(source.path)}',
      );
    }
    _output.next(
      'Edit manifest files directly, or sync released packages with:',
    );
    _output.next('  fluoh source sync ${_output.style.path(source.path)}');
    _output.next(
      'Enable it locally with: fluoh source enable <name> ${_output.style.path(source.path)}',
    );
    return 0;
  }
}

/// Registers the current release metadata from one package repository.
class SourceRegisterCommand extends FluohCommand<int> {
  /// Creates the source register command.
  SourceRegisterCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser
      ..addOption(
        'source',
        valueHelp: 'path',
        help: 'Source repository path. Defaults to the current directory.',
      )
      ..addOption(
        'package',
        valueHelp: 'name',
        help: 'Package to register. Defaults to the package branch.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the registration result as JSON.',
      );
  }

  /// Runtime environment used to resolve repositories.
  final FluohEnvironment environment;

  /// Writer used for JSON output.
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'register';

  @override
  String get description =>
      'Add the first released package branch to a Source repository.';

  @override
  String get invocation => 'fluoh source register <package-repo>';

  @override
  Future<int> run() async {
    final rest = expectArgumentCount(
      argResults!,
      1,
      'Expected <package-repo>.',
      usageException,
    );
    final json = argResults!.flag('json');
    final sourceOption = argResults!.option('source')?.trim();
    final source = sourceOption == null || sourceOption.isEmpty
        ? environment.workingDirectory
        : _resolveUserSourceDirectory(
            environment.workingDirectory,
            Directory(sourceOption),
          );
    final packageRepository = _resolveUserSourceDirectory(
      environment.workingDirectory,
      Directory(rest.single),
    );
    final manifest = await readPackageManifest(packageRepository);
    final package = manifest.packageForName(argResults!.option('package'));
    final releaseTag = package.releaseTag(manifest.sdkVersion);
    final result = await _writeSourcePackageMetadata(
      source: source,
      manifestName: package.name,
      packageName: package.name,
      packageUrl: manifest.repositoryUrl,
      packagePath: package.path,
      originKind: manifest.originKind,
      upstreamGitUrl: manifest.upstreamUrl,
      upstreamVersion: package.upstreamVersion,
      upstreamRef: package.upstreamRef,
      upstreamCommit: package.upstreamCommit,
      sdkVersion: manifest.sdkVersion,
      releaseVersion: package.releaseVersion,
      releaseTag: releaseTag,
      releaseStatus: package.status ?? 'compatible',
      usageException: usageException,
    );
    if (json) {
      writeMachineOutput(
        stdout,
        command: 'source register',
        ok: true,
        exitCode: 0,
        fields: {
          'source': source.path,
          'packageRepository': packageRepository.path,
          'package': package.name,
          'manifestPath': result.manifestPath,
          'tag': releaseTag,
          'status': result.skippedFrozen ? 'skipped' : 'registered',
          if (result.frozenReason != null) 'reason': result.frozenReason,
        },
      );
      return 0;
    }
    if (result.skippedFrozen) {
      _output.skipped(
        'Skipped source metadata update for ${package.name} because maintenance.frozen is true',
      );
      if (result.frozenReason != null) {
        _output.next(result.frozenReason!);
      }
    } else {
      _output.success(
        'Registered source metadata for ${package.name} from ${_output.style.path(packageRepository.path)}',
      );
    }
    return 0;
  }
}

class _SourceStats {
  const _SourceStats({required this.packageCount, required this.sdks});

  factory _SourceStats.fromIndexes({
    required SdkIndex sdkIndex,
    required PackageIndex packageIndex,
    String? sdkLineFilter,
  }) {
    final sdkVersionsByLine = <String, List<String>>{};
    for (final release in sdkIndex.releases) {
      final line = sdkLineFromSdkVersion(release.version);
      if (sdkLineFilter != null && line != sdkLineFilter) {
        continue;
      }
      sdkVersionsByLine.putIfAbsent(line, () => []).add(release.version);
    }

    final statusByLine = <String, Map<String, Set<String>>>{};
    for (final packageEntry in packageIndex.packages.entries) {
      final packageName = packageEntry.key;
      for (final status in packageEntry.value.compatibility) {
        if (sdkLineFilter != null && status.sdkLine != sdkLineFilter) {
          continue;
        }
        final bucket = statusByLine
            .putIfAbsent(status.sdkLine, () => <String, Set<String>>{})
            .putIfAbsent(status.status, () => <String>{});
        bucket.add(packageName);
      }
    }

    final lines = <String>{
      ...sdkVersionsByLine.keys,
      ...statusByLine.keys,
    }.toList(growable: false)..sort((a, b) => compareNumericVersion(b, a));
    final sdks = <_SourceStatsSdk>[];
    for (final line in lines) {
      final versions = sdkVersionsByLine[line];
      if (versions == null || versions.isEmpty) {
        sdks.add(
          _SourceStatsSdk.fromLine(line: line, statuses: statusByLine[line]),
        );
        continue;
      }
      versions.sort((a, b) => compareNumericVersion(b, a));
      for (final version in versions) {
        sdks.add(
          _SourceStatsSdk.fromLine(
            version: version,
            line: line,
            statuses: statusByLine[line],
          ),
        );
      }
    }
    return _SourceStats(packageCount: packageIndex.packages.length, sdks: sdks);
  }

  final int packageCount;
  final List<_SourceStatsSdk> sdks;

  Map<String, Object?> toJson() {
    return {
      'packageCount': packageCount,
      'sdkCount': sdks.length,
      'sdks': [for (final sdk in sdks) sdk.toJson()],
    };
  }
}

class _SourceStatsSdk {
  _SourceStatsSdk._({
    required this.version,
    required this.line,
    required this.packagesByStatus,
  });

  factory _SourceStatsSdk.fromLine({
    String? version,
    required String line,
    Map<String, Set<String>>? statuses,
  }) {
    final packagesByStatus = <String, List<String>>{};
    for (final status in ['implemented', 'experimental', 'broken']) {
      final packages = (statuses?[status] ?? const <String>{}).toList(
        growable: false,
      )..sort();
      packagesByStatus[status] = packages;
    }
    return _SourceStatsSdk._(
      version: version,
      line: line,
      packagesByStatus: packagesByStatus,
    );
  }

  final String? version;
  final String line;
  final Map<String, List<String>> packagesByStatus;

  int get implementedCount => packagesByStatus['implemented']!.length;
  int get experimentalCount => packagesByStatus['experimental']!.length;
  int get brokenCount => packagesByStatus['broken']!.length;
  int get supportedCount {
    return <String>{
      ...packagesByStatus['implemented']!,
      ...packagesByStatus['experimental']!,
      ...packagesByStatus['broken']!,
    }.length;
  }

  Map<String, Object?> toJson() {
    return {
      if (version != null) 'version': version,
      'line': line,
      'packageCount': supportedCount,
      'compatibleCount': implementedCount,
      'experimentalCount': experimentalCount,
      'brokenCount': brokenCount,
      'packagesByStatus': packagesByStatus,
    };
  }
}

/// Synchronizes package release metadata into a Source repository.
