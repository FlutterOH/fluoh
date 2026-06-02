import 'dart:io';

import '../context/fluoh_environment.dart';
import '../schema/schema.dart';
import 'dependency_analyzer.dart';
import 'pubspec_dependency_editor.dart';

export '../schema/schema.dart'
    show
        DependencyPlan,
        DependencyPlanEntry,
        DependencyPlanPurpose,
        DependencyPlanStatus,
        implementationUpstreamVersionChange;

/// Builds a dependency rewrite plan for the current project.
Future<DependencyPlan> buildDependencyPlan({
  required FluohEnvironment environment,
  required DependencyPolicy policy,
  required DependencyPlanPurpose purpose,
}) async {
  final report = await DependencyAnalyzer(environment).analyze();
  final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
  final state = await readPubspecDependencyState(pubspec);
  return buildDependencyPlanFromReport(
    report: report,
    state: state,
    policy: policy,
    purpose: purpose,
  );
}
