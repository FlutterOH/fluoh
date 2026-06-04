import 'dart:io';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../dependency_plan.dart';
import '../dependency_policy.dart';
import '../pubspec_dependency_editor.dart';

/// Upgrades existing FlutterOH dependency replacement refs.
class DepsUpgradeCommand extends FluohCommand<int> {
  /// Creates the dependency replacement upgrade command.
  DepsUpgradeCommand({
    required this.environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _output = output ?? TerminalOutput(stdout: stdout) {
    argParser.addFlag(
      'dry-run',
      abbr: 'n',
      negatable: false,
      help:
          'Show planned FlutterOH dependency replacement upgrades without writing pubspec.yaml.',
    );
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print the dependency upgrade result as JSON.',
    );
    addAllReleaseStatusesFlag(argParser);
  }

  /// Runtime environment containing the project and Source config.
  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final TerminalOutput _output;

  @override
  String get name => 'upgrade';

  @override
  String get description =>
      'Upgrade existing FlutterOH dependency replacements.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final dryRun = argResults!.flag('dry-run');
    final json = argResults!.flag('json');
    final policy = applyAllReleaseStatusesFlag(
      await readDependencyPolicy(environment.workingDirectory),
      argResults!,
    );
    final plan = await buildDependencyPlan(
      environment: environment,
      policy: policy,
      purpose: DependencyPlanPurpose.upgrade,
    );
    final changes = plan.changes;
    final skippedIncompatibleVersion = plan.entries
        .where(
          (entry) => entry.status == DependencyPlanStatus.incompatibleVersion,
        )
        .toList(growable: false);
    if (json) {
      if (changes.isEmpty || dryRun) {
        _writeUpgradeJson(plan: plan, dryRun: dryRun, applied: 0);
        return 0;
      }

      final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
      final applied = await applyPubspecDependencyChanges(
        pubspec: pubspec,
        changes: changes,
      );
      _writeUpgradeJson(plan: plan, dryRun: false, applied: applied);
      return 0;
    }

    if (changes.isEmpty) {
      if (skippedIncompatibleVersion.isEmpty) {
        _output.skipped(
          'No existing FlutterOH dependency replacements need upgrades',
        );
      }
      _printSkippedIncompatibleVersion(skippedIncompatibleVersion);
      return 0;
    }

    for (final entry in plan.actionableEntries) {
      for (final change in entry.changes) {
        _output.step(
          '${dryRun ? 'Would ' : ''}update ${change.packageName} '
          '${change.currentRef} -> ${change.nextRef}'
          '${implementationUpstreamVersionChange(change, entry.dependency)}',
        );
      }
    }
    _printSkippedIncompatibleVersion(skippedIncompatibleVersion);
    if (dryRun) {
      _output.warning('Dry run only; pubspec.yaml was not modified');
      _output.next(
        'Run ${_output.style.code('fluoh deps upgrade')} to apply these changes',
      );
      return 0;
    }

    final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
    final applied = await applyPubspecDependencyChanges(
      pubspec: pubspec,
      changes: changes,
    );
    _output.success(
      'Updated $applied FlutterOH dependency '
      'replacement${applied == 1 ? '' : 's'}',
    );
    _output.next('Next: run ${_output.style.code('fluoh deps get')}');
    return 0;
  }

  void _writeUpgradeJson({
    required DependencyPlan plan,
    required bool dryRun,
    required int applied,
  }) {
    writeMachineOutput(
      _stdout,
      command: 'deps upgrade',
      ok: dryRun ? plan.changes.isEmpty : true,
      exitCode: 0,
      fields: {
        'changes': _changeSummaries(plan).toList(),
        'applied': applied,
        'dryRun': dryRun,
        ...plan.toJson(),
      },
    );
  }

  void _printSkippedIncompatibleVersion(List<DependencyPlanEntry> entries) {
    for (final entry in entries) {
      _output.skipped('Skipped ${entry.dependency.name}: ${entry.reason}');
    }
    if (entries.isNotEmpty) {
      _output.warning(
        'Set dependencyPolicy.versionChanges to any in fluoh.yaml to include '
        'incompatible version changes and downgrades.',
      );
    }
  }
}

Iterable<Map<String, Object?>> _changeSummaries(DependencyPlan plan) {
  return plan.actionableEntries.expand((entry) {
    return entry.changes.map((change) {
      return {
        'packageName': change.packageName,
        'kind': change.kind.name,
        'nextRef': change.nextRef,
        if (change.currentRef != null) 'currentRef': change.currentRef,
      };
    });
  });
}
