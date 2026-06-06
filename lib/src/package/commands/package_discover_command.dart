import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../git/package_git.dart';
import '../package_discovery.dart';

/// Discovers upstream packages that are candidates for OHOS adaptation.
class PackageDiscoverCommand extends FluohCommand<int> {
  /// Creates the package discover command.
  PackageDiscoverCommand({required OutputWriter stdout, TerminalOutput? output})
    : _stdout = stdout,
      _output = output ?? TerminalOutput(stdout: stdout, stderr: (_) {}) {
    argParser
      ..addOption(
        'missing-platform',
        valueHelp: 'platform',
        defaultsTo: 'ohos',
        help:
            'Plugin platform that should be missing from suggested packages. '
            'Defaults to ohos.',
      )
      ..addFlag(
        'include-existing-platform',
        negatable: false,
        help:
            'Include Flutter plugins that already declare the missing platform.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print discovered package candidates as JSON.',
      );
  }

  final OutputWriter _stdout;
  final TerminalOutput _output;

  @override
  String get name => 'discover';

  @override
  String get description =>
      'Discover Flutter plugin packages that may need OHOS adaptation.';

  @override
  String get invocation => 'fluoh package discover <upstream>';

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

  @override
  Future<int> run() async {
    final rest = expectArgumentCount(
      argResults!,
      1,
      'Expected <upstream>: Git URL or local Git repo path.',
      usageException,
    );
    final upstream = rest.single;
    final missingPlatform = _missingPlatformFromOptions(argResults!);
    final includeExistingPlatform = argResults!.flag(
      'include-existing-platform',
    );
    final json = argResults!.flag('json');
    final output = json
        ? TerminalOutput(stdout: (_) {}, stderr: (_) {})
        : _output;

    Directory? tempRoot;
    try {
      tempRoot = await Directory.systemTemp.createTemp('fluoh-discover-');
      final scratchRepository = Directory('${tempRoot.path}/upstream');
      if (!json) {
        output.step('Inspecting upstream repository');
      }
      await runGit(['clone', '--quiet', upstream, scratchRepository.path]);
      final discovery = await discoverPackageAdaptationCandidates(
        repository: scratchRepository,
        missingPlatform: missingPlatform,
        includeExistingPlatform: includeExistingPlatform,
      );

      if (json) {
        writeMachineOutput(
          _stdout,
          command: 'package discover',
          ok: true,
          exitCode: 0,
          fields: {
            'changed': false,
            'discovery': discovery.toJson(
              upstream: upstream,
              missingPlatform: missingPlatform,
              includeExistingPlatform: includeExistingPlatform,
            ),
          },
        );
      } else {
        _printDiscovery(
          output: output,
          upstream: upstream,
          missingPlatform: missingPlatform,
          includeExistingPlatform: includeExistingPlatform,
          discovery: discovery,
        );
      }
      return 0;
    } finally {
      if (tempRoot != null && await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    }
  }

  String get _usageWithoutDescription {
    return [
      'Usage: $invocation',
      'Upstream: Git URL or local Git repo path.',
      '',
      argParser.usage,
      '',
      'Run "${runner!.executableName} help" to see global options.',
    ].join('\n');
  }
}

String _missingPlatformFromOptions(ArgResults argResults) {
  final platform = argResults.option('missing-platform')?.trim();
  if (platform == null || platform.isEmpty) {
    throw UsageException('--missing-platform must not be empty.', '');
  }
  return platform;
}

void _printDiscovery({
  required TerminalOutput output,
  required String upstream,
  required String missingPlatform,
  required bool includeExistingPlatform,
  required PackageDiscovery discovery,
}) {
  output.success('Package candidates discovered');
  output.info('Upstream: $upstream');
  output.info(
    includeExistingPlatform
        ? 'Filter: Flutter plugins, including plugins with $missingPlatform'
        : 'Filter: Flutter plugins missing $missingPlatform',
  );
  output.info('Pubspecs inspected: ${discovery.pubspecCount}');
  output.info('Valid Flutter plugins found: ${discovery.pluginPackageCount}');
  if (discovery.candidates.isEmpty) {
    output.info('No matching package candidates found.');
    _printDiscoveryIssues(output, discovery);
    return;
  }

  output.blank();
  output.table(
    columns: const [
      TerminalTableColumn('#', style: TerminalTableCellStyle.muted),
      TerminalTableColumn('Package', style: TerminalTableCellStyle.value),
      TerminalTableColumn('Path', style: TerminalTableCellStyle.path),
      TerminalTableColumn('Version', style: TerminalTableCellStyle.muted),
      TerminalTableColumn('Platforms', style: TerminalTableCellStyle.muted),
    ],
    rows: [
      for (var i = 0; i < discovery.candidates.length; i += 1)
        [
          '${i + 1}',
          discovery.candidates[i].name,
          discovery.candidates[i].path,
          discovery.candidates[i].version,
          discovery.candidates[i].platforms.isEmpty
              ? '-'
              : discovery.candidates[i].platforms.join(', '),
        ],
    ],
  );
  output.blank();
  output.next(
    packageDiscoveryCreateCommand(
      upstream: upstream,
      candidate: discovery.candidates.first,
    ),
  );
  if (discovery.candidates.length > 1) {
    output.next(packageDiscoveryQueueCommand(discovery.candidates));
  }
  _printDiscoveryIssues(output, discovery);
}

void _printDiscoveryIssues(TerminalOutput output, PackageDiscovery discovery) {
  for (final issue in discovery.issues) {
    output.warning('${issue.path}: ${issue.message}');
  }
}
