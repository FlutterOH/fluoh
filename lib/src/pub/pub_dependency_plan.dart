import 'dart:io';

import '../context/fluoh_environment.dart';
import '../schema/schema.dart';
import 'pub_dependency_analyzer.dart';
import 'pubspec_dependency_editor.dart';

export '../schema/schema.dart'
    show
        PubDependencyPlan,
        PubDependencyPlanEntry,
        PubDependencyPlanPurpose,
        PubDependencyPlanStatus,
        implementationUpstreamVersionChange;

Future<PubDependencyPlan> buildPubDependencyPlan({
  required FluohEnvironment environment,
  required PubDependencyPolicy policy,
  required PubDependencyPlanPurpose purpose,
}) async {
  final report = await PubDependencyAnalyzer(environment).analyze();
  final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
  final state = await readPubspecDependencyState(pubspec);
  return buildPubDependencyPlanFromReport(
    report: report,
    state: state,
    policy: policy,
    purpose: purpose,
  );
}
