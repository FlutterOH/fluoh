import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../../cli/fluoh_command_runner.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../pub_dependency_analyzer.dart';
import '../pub_dependency_plan.dart';
import '../pub_dependency_policy.dart';
import '../pubspec_dependency_editor.dart';

class PubCheckCommand extends Command<int> {
  PubCheckCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print the OHOS support report as JSON.',
    );
  }

  final FluohEnvironment environment;
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'check';

  @override
  String get description => 'Check dependency OHOS support.';

  @override
  Future<int> run() async {
    final policy = await readPubDependencyPolicy(environment.workingDirectory);
    final plan = await buildPubDependencyPlan(
      environment: environment,
      policy: policy,
      purpose: PubDependencyPlanPurpose.fix,
    );
    if (argResults!.flag('json')) {
      stdout(jsonEncode(plan.toJson()));
      return 0;
    }

    _printCheckPlan(_output, plan);
    return 0;
  }
}

class PubFixCommand extends Command<int> {
  PubFixCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser.addFlag(
      'dry-run',
      abbr: 'n',
      negatable: false,
      help: 'Show planned dependency changes without writing pubspec.yaml.',
    );
  }

  final FluohEnvironment environment;
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'fix';

  @override
  String get description =>
      'Apply recommended OHOS dependency implementation changes.';

  @override
  Future<int> run() async {
    final dryRun = argResults!.flag('dry-run');
    final policy = await readPubDependencyPolicy(environment.workingDirectory);
    final plan = await buildPubDependencyPlan(
      environment: environment,
      policy: policy,
      purpose: PubDependencyPlanPurpose.fix,
    );
    _printMutationPlan(_output, plan, dryRun: dryRun);

    if (plan.changes.isEmpty || dryRun) {
      return 0;
    }

    final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
    final applied = await applyPubspecDependencyChanges(
      pubspec: pubspec,
      changes: plan.changes,
    );
    _output.success(
      'Updated pubspec.yaml with $applied dependency change${_s(applied)}.',
    );
    _printNextStep(_output);
    return 0;
  }
}

void _printCheckPlan(TerminalOutput output, PubDependencyPlan plan) {
  output.heading(
    'Dependency OHOS support for Flutter OHOS SDK ${plan.sdkVersion}.',
  );
  output.info(
    'Policy: pubspecSection=${plan.policy.pubspecSection.yamlValue}, '
    'versionChanges=${plan.policy.versionChanges.yamlValue}.',
  );

  final ready = plan.entries
      .where((entry) => entry.changes.isNotEmpty)
      .toList(growable: false);
  final needsDecision = plan.entries
      .where(
        (entry) => entry.status == PubDependencyPlanStatus.incompatibleVersion,
      )
      .toList(growable: false);
  final manual = plan.entries
      .where(
        (entry) =>
            entry.dependency.direct &&
            const {
              PubDependencyPlanStatus.overrideExists,
            }.contains(entry.status),
      )
      .toList(growable: false);
  final unavailable = plan.entries
      .where(
        (entry) =>
            entry.dependency.direct &&
            const {
              PubDependencyPlanStatus.blocked,
              PubDependencyPlanStatus.sdkMismatch,
              PubDependencyPlanStatus.unknown,
            }.contains(entry.status),
      )
      .toList(growable: false);
  final ok = plan.entries
      .where(
        (entry) =>
            entry.dependency.direct &&
            const {
              PubDependencyPlanStatus.alreadyCurrent,
              PubDependencyPlanStatus.native,
            }.contains(entry.status),
      )
      .toList(growable: false);
  final transitive = plan.entries
      .where((entry) => entry.status == PubDependencyPlanStatus.transitive)
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
    '${ok.length} already OK, ${transitive.length} transitive.',
  );
  if (ready.isNotEmpty) {
    output.next(
      'Next: run ${output.style.code('fluoh pub fix')}, then '
      '${output.style.code('fluoh pub get')}.',
    );
  } else {
    output.skipped('No dependency changes are currently available.');
  }
}

void _printAdvisories(
  TerminalOutput output,
  List<PubDependencyPlanEntry> entries,
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
  PubDependencyPlan plan, {
  required bool dryRun,
}) {
  final changes = plan.changes;
  if (changes.isEmpty) {
    output.skipped('No dependency changes are currently available.');
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
        (entry) => entry.status == PubDependencyPlanStatus.incompatibleVersion,
      )
      .toList(growable: false);
  for (final entry in skippedIncompatibleVersion) {
    output.skipped('Skipped ${entry.dependency.name}: ${entry.reason}');
  }
  final skippedManual = plan.entries
      .where(
        (entry) =>
            entry.dependency.direct &&
            const {
              PubDependencyPlanStatus.overrideExists,
            }.contains(entry.status),
      )
      .toList(growable: false);
  for (final entry in skippedManual) {
    output.skipped('Skipped ${entry.dependency.name}: ${entry.reason}');
  }
  if (skippedIncompatibleVersion.isNotEmpty &&
      plan.policy.versionChanges ==
          PubDependencyVersionChangePolicy.compatible) {
    output.warning(
      'Set dependencyPolicy.versionChanges to any in fluoh.yaml to include '
      'incompatible version changes and downgrades.',
    );
  }

  if (changes.isNotEmpty && dryRun) {
    output.warning('Dry run only; pubspec.yaml was not modified.');
  }
  if (changes.isNotEmpty && dryRun) {
    output.next(
      'Run ${output.style.code('fluoh pub fix')} to apply these changes.',
    );
  }
}

void _printEntries(
  TerminalOutput output,
  String title,
  List<PubDependencyPlanEntry> entries,
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

String _entryMessage(PubDependencyPlanEntry entry) {
  final dependency = entry.dependency;
  return '${dependency.name} ${dependency.version}: ${_entryDetails(entry)}';
}

String _entryDetails(PubDependencyPlanEntry entry) {
  if (entry.changes.isNotEmpty) {
    return entry.changes
        .map((change) => _changeSummary(change, dependency: entry.dependency))
        .join('; ');
  }
  return entry.reason;
}

List<String> _advisoryMessages(PubDependencyPlanEntry entry) {
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
    messages.add('${entry.dependency.name}: advisory available.');
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
  output.next('Next: run ${output.style.code('fluoh pub get')}.');
}

String _s(int count) => count == 1 ? '' : 's';
