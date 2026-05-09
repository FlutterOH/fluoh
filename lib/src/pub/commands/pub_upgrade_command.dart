import 'dart:io';

import 'package:args/command_runner.dart';

import '../../cli/fluoh_command_runner.dart';
import '../../context/fluoh_environment.dart';
import '../pub_dependency_plan.dart';
import '../pub_dependency_policy.dart';
import '../pubspec_dependency_editor.dart';

class PubUpgradeCommand extends Command<int> {
  PubUpgradeCommand({required this.environment, required OutputWriter stdout})
    : _stdout = stdout {
    argParser.addFlag(
      'dry-run',
      abbr: 'n',
      negatable: false,
      help: 'Show planned adapter ref upgrades without writing pubspec.yaml.',
    );
  }

  final FluohEnvironment environment;
  final OutputWriter _stdout;

  @override
  String get name => 'upgrade';

  @override
  String get description => 'Upgrade existing OHOS adapter refs.';

  @override
  Future<int> run() async {
    final dryRun = argResults!.flag('dry-run');
    final policy = await readPubDependencyPolicy(environment.workingDirectory);
    final plan = await buildPubDependencyPlan(
      environment: environment,
      policy: policy,
      purpose: PubDependencyPlanPurpose.upgrade,
    );
    final changes = plan.changes;
    final skippedVersionMismatch = plan.entries
        .where(
          (entry) => entry.status == PubDependencyPlanStatus.versionMismatch,
        )
        .toList(growable: false);
    if (changes.isEmpty) {
      if (skippedVersionMismatch.isEmpty) {
        _stdout('No existing OHOS adapter refs need upgrades.');
      }
      _printSkippedVersionMismatch(skippedVersionMismatch);
      return 0;
    }

    for (final change in changes) {
      _stdout(
        '${dryRun ? 'Would ' : ''}update ${change.packageName} '
        '${change.currentRef} -> ${change.nextRef}',
      );
    }
    _printSkippedVersionMismatch(skippedVersionMismatch);
    if (dryRun) {
      _stdout('Dry run only; pubspec.yaml was not modified.');
      _stdout('Run `fluoh pub upgrade` to apply these changes.');
      return 0;
    }

    final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
    final applied = await applyPubspecDependencyChanges(
      pubspec: pubspec,
      changes: changes,
    );
    _stdout('Updated $applied OHOS dependency ref${applied == 1 ? '' : 's'}.');
    _stdout('Next: run `fluoh flutter pub get`.');
    return 0;
  }

  void _printSkippedVersionMismatch(List<PubDependencyPlanEntry> entries) {
    for (final entry in entries) {
      _stdout('Skipped ${entry.dependency.name}: ${entry.reason}');
    }
    if (entries.isNotEmpty) {
      _stdout(
        'Set dependencyPolicy.versionMismatch to allow in fluoh.yaml to include '
        'version-mismatch adapters.',
      );
    }
  }
}
