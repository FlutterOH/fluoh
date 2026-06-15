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
      await _cloneUpstreamForDiscovery(upstream, scratchRepository);
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

Future<void> _cloneUpstreamForDiscovery(
  String upstream,
  Directory scratchRepository,
) async {
  final shallow = await runGit([
    'clone',
    '--quiet',
    '--depth',
    '1',
    '--single-branch',
    upstream,
    scratchRepository.path,
  ], allowFailure: true);
  if (shallow.exitCode == 0) {
    return;
  }
  if (await scratchRepository.exists()) {
    await scratchRepository.delete(recursive: true);
  }
  await runGit(['clone', '--quiet', upstream, scratchRepository.path]);
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
  final recommendedCandidates = discovery.recommendedCandidates(
    missingPlatform,
  );
  output.info(
    'Recommended adaptation entries: ${recommendedCandidates.length}',
  );
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
      TerminalTableColumn('Profile', style: TerminalTableCellStyle.muted),
      TerminalTableColumn(
        'Recommendation',
        style: TerminalTableCellStyle.muted,
      ),
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
          _profileLabel(discovery.candidates[i].adaptationProfile),
          _recommendationLabel(discovery.candidates[i], missingPlatform),
        ],
    ],
  );
  output.blank();
  if (recommendedCandidates.isNotEmpty) {
    output.next(
      packageDiscoveryCreateCommand(
        upstream: upstream,
        candidate: recommendedCandidates.first,
      ),
    );
  }
  if (recommendedCandidates.length > 1) {
    output.next(packageDiscoveryQueueCommand(recommendedCandidates));
  }
  _printImplementationRecommendations(
    output: output,
    upstream: upstream,
    missingPlatform: missingPlatform,
    discovery: discovery,
  );
  _printDiscoveryIssues(output, discovery);
}

String _profileLabel(PackageAdaptationProfile profile) {
  final categories = profile.categories.take(3).join(', ');
  if (categories.isEmpty) {
    return profile.complexity;
  }
  return '${profile.complexity}: $categories';
}

String _recommendationLabel(
  PackageDiscoveryCandidate candidate,
  String missingPlatform,
) {
  if (candidate.isRecommendedFor(missingPlatform)) {
    return 'recommended';
  }
  if (candidate.coveredByImplementationRecommendations.isNotEmpty) {
    final appFacingPackages = candidate.coveredByImplementationRecommendations
        .map((coverage) => coverage.appFacingPackage)
        .toSet()
        .join(', ');
    return 'covered by $appFacingPackages';
  }
  final reason = candidate.defaultRecommendationExclusionReason;
  if (reason == 'test_fixture') {
    return 'test fixture';
  }
  if (reason == 'platform_specific_helper_package') {
    return 'platform helper';
  }
  return 'already has $missingPlatform';
}

void _printImplementationRecommendations({
  required TerminalOutput output,
  required String upstream,
  required String missingPlatform,
  required PackageDiscovery discovery,
}) {
  var printed = false;
  for (final candidate in discovery.candidates) {
    final recommendation = candidate.implementationRecommendation(
      missingPlatform,
    );
    if (recommendation == null) {
      continue;
    }
    if (!printed) {
      output.blank();
      printed = true;
    }
    output.next(
      'Start with '
      '${packageDiscoveryCreateCommand(upstream: upstream, candidate: candidate)}, '
      'then create ${recommendation.implementationPackageName} at '
      '${recommendation.implementationPackagePath} and add '
      '$missingPlatform.default_package to '
      '${recommendation.appFacingPackage}.',
    );
  }
}

void _printDiscoveryIssues(TerminalOutput output, PackageDiscovery discovery) {
  for (final issue in discovery.issues) {
    output.warning('${issue.path}: ${issue.message}');
  }
}
