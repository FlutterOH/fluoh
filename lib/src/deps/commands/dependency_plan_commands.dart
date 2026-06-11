import 'dart:io';

import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../deps/dependency_analyzer.dart';
import '../../deps/dependency_plan.dart';
import '../../deps/dependency_policy.dart';
import '../../deps/pubspec_dependency_editor.dart';

/// Implements `fluoh deps check`.
class DepsCheckCommand extends FluohCommand<int> {
  /// Creates the project dependency check command.
  DepsCheckCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print the dependency OHOS support report as JSON.',
    );
    addAllReleaseStatusesFlag(argParser);
  }

  /// Runtime environment containing the project and Source config.
  final FluohEnvironment environment;

  /// Writer used for JSON output.
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'check';

  @override
  String get description => 'Check whether dependencies support OHOS.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final policy = applyAllReleaseStatusesFlag(
      await readDependencyPolicy(environment.workingDirectory),
      argResults!,
    );
    final plan = await buildDependencyPlan(
      environment: environment,
      policy: policy,
      purpose: DependencyPlanPurpose.fix,
    );
    if (argResults!.flag('json')) {
      writeMachineOutput(
        stdout,
        command: 'deps check',
        ok: _dependencyPlanOk(plan),
        exitCode: 0,
        fields: plan.toJson(),
      );
      return 0;
    }

    _printCheckPlan(_output, plan);
    return 0;
  }
}

bool _dependencyPlanOk(DependencyPlan plan) {
  return plan.entries.every((entry) {
    if (!entry.dependency.direct) {
      return true;
    }
    return const {
      DependencyPlanStatus.alreadyCurrent,
      DependencyPlanStatus.native,
    }.contains(entry.status);
  });
}

String _displayReleaseStatuses(Set<String> statuses) {
  return orderedDependencyReleaseStatuses(statuses).join(',');
}

/// Implements `fluoh deps fix`.
class DepsFixCommand extends FluohCommand<int> {
  /// Creates the project dependency fix command.
  DepsFixCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser.addFlag(
      'dry-run',
      abbr: 'n',
      negatable: false,
      help: 'Show planned dependency rewrites without writing pubspec.yaml.',
    );
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print the dependency fix result as JSON.',
    );
    addAllReleaseStatusesFlag(argParser);
  }

  /// Runtime environment containing the project and Source config.
  final FluohEnvironment environment;

  /// Writer used for JSON output.
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'fix';

  @override
  String get description =>
      'Rewrite dependencies to recommended FlutterOH replacements.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final dryRun = argResults!.flag('dry-run');
    final jsonMode = argResults!.flag('json');
    final policy = applyAllReleaseStatusesFlag(
      await readDependencyPolicy(environment.workingDirectory),
      argResults!,
    );
    final plan = await buildDependencyPlan(
      environment: environment,
      policy: policy,
      purpose: DependencyPlanPurpose.fix,
    );

    if (plan.changes.isEmpty || dryRun) {
      if (jsonMode) {
        writeMachineOutput(
          stdout,
          command: 'deps fix',
          ok: plan.changes.isEmpty,
          exitCode: 0,
          fields: {
            'changes': _changeSummaries(plan).toList(),
            'applied': 0,
            'dryRun': dryRun,
            ...plan.toJson(),
          },
        );
      } else {
        _printMutationPlan(_output, plan, dryRun: dryRun);
      }
      return 0;
    }

    final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
    final applied = await applyPubspecDependencyChanges(
      pubspec: pubspec,
      changes: plan.changes,
    );
    if (jsonMode) {
      writeMachineOutput(
        stdout,
        command: 'deps fix',
        ok: true,
        exitCode: 0,
        fields: {
          'changes': _changeSummaries(plan).toList(),
          'applied': applied,
          'dryRun': false,
          ...plan.toJson(),
        },
      );
    } else {
      _printMutationPlan(_output, plan, dryRun: dryRun);
      _output.success(
        'Updated pubspec.yaml with $applied dependency change${_s(applied)}',
      );
      _printNextStep(_output);
    }
    return 0;
  }
}

void _printCheckPlan(TerminalOutput output, DependencyPlan plan) {
  output.heading(
    'Dependency OHOS support for FlutterOH SDK ${plan.sdkVersion}',
  );
  output.info(
    'Policy: pubspecSection=${plan.policy.pubspecSection.yamlValue}, '
    'versionChanges=${plan.policy.versionChanges.yamlValue}, '
    'releaseStatuses=${_displayReleaseStatuses(plan.policy.allowedReleaseStatuses)}',
  );

  final ready = plan.entries
      .where((entry) => entry.changes.isNotEmpty)
      .toList(growable: false);
  final needsDecision = plan.entries
      .where(
        (entry) => entry.status == DependencyPlanStatus.incompatibleVersion,
      )
      .toList(growable: false);
  final manual = plan.entries
      .where(
        (entry) =>
            entry.dependency.direct &&
            const {DependencyPlanStatus.overrideExists}.contains(entry.status),
      )
      .toList(growable: false);
  final unavailable = plan.entries
      .where(
        (entry) =>
            entry.dependency.direct &&
            const {
              DependencyPlanStatus.blocked,
              DependencyPlanStatus.sdkMismatch,
              DependencyPlanStatus.unknown,
            }.contains(entry.status),
      )
      .toList(growable: false);
  final ok = plan.entries
      .where(
        (entry) =>
            entry.dependency.direct &&
            const {
              DependencyPlanStatus.alreadyCurrent,
              DependencyPlanStatus.native,
            }.contains(entry.status),
      )
      .toList(growable: false);
  final transitive = plan.entries
      .where((entry) => entry.status == DependencyPlanStatus.transitive)
      .toList(growable: false);
  final advisories = plan.entries
      .where(
        (entry) => entry.dependency.direct && entry.dependency.advisory != null,
      )
      .toList(growable: false);

  _printEntries(output, 'Ready to fix:', ready);
  _printEntries(output, 'Needs decision:', needsDecision);
  _printEntries(output, 'Needs manual action:', manual);
  _printEntries(output, 'Unavailable:', unavailable);
  _printEntries(output, 'Already OK:', ok);
  _printEntries(output, 'Transitive dependencies:', transitive);
  _printAdvisories(output, advisories);

  output.info(
    'Summary: ${ready.length} ready, ${needsDecision.length} needs decision, '
    '${manual.length} manual, ${unavailable.length} unavailable, '
    '${ok.length} already OK, ${transitive.length} transitive',
  );
  if (ready.isNotEmpty) {
    output.next(
      'Next: run ${output.style.code('fluoh deps fix')}, then '
      '${output.style.code('fluoh deps get')}',
    );
  } else {
    output.skipped('No dependency changes are currently available');
  }
}

void _printAdvisories(
  TerminalOutput output,
  List<DependencyPlanEntry> entries,
) {
  if (entries.isEmpty) {
    return;
  }

  output.blank();
  output.section('Advisories:');
  for (final entry in entries) {
    for (final message in _advisoryMessages(entry)) {
      output.indented(message);
    }
  }
}

void _printMutationPlan(
  TerminalOutput output,
  DependencyPlan plan, {
  required bool dryRun,
}) {
  final changes = plan.changes;
  if (changes.isEmpty) {
    output.skipped('No dependency changes are currently available');
  } else {
    for (final entry in plan.actionableEntries) {
      for (final change in entry.changes) {
        output.step(
          '${dryRun ? 'Would ' : ''}'
          '${_changeMessage(change, dependency: entry.dependency)}',
        );
      }
    }
  }

  final skippedIncompatibleVersion = plan.entries
      .where(
        (entry) => entry.status == DependencyPlanStatus.incompatibleVersion,
      )
      .toList(growable: false);
  for (final entry in skippedIncompatibleVersion) {
    output.skipped('Skipped ${entry.dependency.name}: ${entry.reason}');
  }
  final skippedManual = plan.entries
      .where(
        (entry) =>
            entry.dependency.direct &&
            const {DependencyPlanStatus.overrideExists}.contains(entry.status),
      )
      .toList(growable: false);
  for (final entry in skippedManual) {
    output.skipped('Skipped ${entry.dependency.name}: ${entry.reason}');
  }
  if (skippedIncompatibleVersion.isNotEmpty &&
      plan.policy.versionChanges == DependencyVersionChangePolicy.compatible) {
    output.warning(
      'Set dependencyPolicy.versionChanges to any in fluoh.yaml to include '
      'incompatible version changes and downgrades.',
    );
  }

  if (changes.isNotEmpty && dryRun) {
    output.warning('Dry run only; pubspec.yaml was not modified');
  }
  if (changes.isNotEmpty && dryRun) {
    output.next(
      'Run ${output.style.code('fluoh deps fix')} to apply these changes',
    );
  }
}

void _printEntries(
  TerminalOutput output,
  String title,
  List<DependencyPlanEntry> entries,
) {
  if (entries.isEmpty) {
    return;
  }

  output.blank();
  output.section(title);
  if (output.style.capabilities.decorated) {
    output.table(
      columns: const [
        TerminalTableColumn('Package', style: TerminalTableCellStyle.value),
        TerminalTableColumn('Version', style: TerminalTableCellStyle.muted),
        TerminalTableColumn('Details'),
      ],
      rows: [
        for (final entry in entries)
          [
            entry.dependency.name,
            entry.dependency.version,
            _entryDetails(entry),
          ],
      ],
    );
    return;
  }

  for (final entry in entries) {
    output.indented(_entryMessage(entry));
  }
}

String _entryMessage(DependencyPlanEntry entry) {
  final dependency = entry.dependency;
  return '${dependency.name} ${dependency.version}: ${_entryDetails(entry)}';
}

String _entryDetails(DependencyPlanEntry entry) {
  if (entry.changes.isNotEmpty) {
    return entry.changes
        .map((change) => _changeSummary(change, dependency: entry.dependency))
        .join('; ');
  }
  return entry.reason;
}

List<String> _advisoryMessages(DependencyPlanEntry entry) {
  final advisory = entry.dependency.advisory!;
  final messages = <String>[];
  if (advisory.message != null && advisory.message!.trim().isNotEmpty) {
    messages.add('${entry.dependency.name}: ${advisory.message}');
  }
  for (final alternative in advisory.alternatives) {
    final details = [
      if (alternative.reason != null && alternative.reason!.trim().isNotEmpty)
        alternative.reason!,
      if (alternative.url != null && alternative.url!.trim().isNotEmpty)
        alternative.url!,
    ].join(' ');
    messages.add(
      '${entry.dependency.name}: consider ${alternative.name}'
      '${details.isEmpty ? '' : ' - $details'}',
    );
  }
  if (messages.isEmpty) {
    messages.add('${entry.dependency.name}: advisory available');
  }
  return messages;
}

String _changeMessage(
  PubspecDependencyChange change, {
  required DependencyCompatibility dependency,
}) {
  final message = switch (change.kind) {
    PubspecDependencyChangeKind.writeOverride =>
      'override ${change.packageName} -> ${change.nextRef}',
    PubspecDependencyChangeKind.rewriteDependency =>
      'rewrite ${change.packageName} -> ${change.nextRef}',
    PubspecDependencyChangeKind.updateRef =>
      'update ${change.packageName} ${change.currentRef} -> ${change.nextRef}',
  };
  return '$message${implementationUpstreamVersionChange(change, dependency)}';
}

String _changeSummary(
  PubspecDependencyChange change, {
  required DependencyCompatibility dependency,
}) {
  final summary = switch (change.kind) {
    PubspecDependencyChangeKind.writeOverride =>
      'override -> ${change.nextRef}',
    PubspecDependencyChangeKind.rewriteDependency =>
      'rewrite -> ${change.nextRef}',
    PubspecDependencyChangeKind.updateRef =>
      'update ${change.currentRef} -> ${change.nextRef}',
  };
  return '$summary${implementationUpstreamVersionChange(change, dependency)}';
}

void _printNextStep(TerminalOutput output) {
  output.next('Next: run ${output.style.code('fluoh deps get')}');
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

String _s(int count) => count == 1 ? '' : 's';
