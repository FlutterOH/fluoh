import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import '../schema/schema.dart';
import '../version.dart';

export '../schema/schema.dart'
    show
        DependencyPolicy,
        DependencyPubspecSection,
        DependencyVersionChangePolicy,
        orderedDependencyReleaseStatuses;

/// Adds command-level release status visibility.
void addAllReleaseStatusesFlag(ArgParser parser) {
  parser.addFlag(
    'all-release-statuses',
    negatable: false,
    help:
        'Include compatible, experimental, and broken Source releases for this command.',
  );
}

/// Applies command-level release status visibility to [policy].
DependencyPolicy applyAllReleaseStatusesFlag(
  DependencyPolicy policy,
  ArgResults results,
) {
  final statuses = results.flag('all-release-statuses')
      ? unrestrictedDependencyReleaseStatuses
      : compatibleDependencyReleaseStatuses;
  return policy.copyWithAllowedReleaseStatuses(statuses);
}

/// Reads dependency rewrite policy from project `fluoh.yaml`.
Future<DependencyPolicy> readDependencyPolicy(
  Directory workingDirectory,
) async {
  final config = File('${workingDirectory.path}/fluoh.yaml');
  if (!await config.exists()) {
    return const DependencyPolicy();
  }

  final loaded = loadYaml(await config.readAsString());
  final yaml = yamlValue(loaded);
  if (yaml is! Map<String, Object?>) {
    return const DependencyPolicy();
  }
  final kind = yaml['kind'];
  if (kind != null && kind != projectConfigKind) {
    return const DependencyPolicy();
  }
  try {
    ensureSupportedSchema(yaml, packageVersion: packageVersion);
    return parseDependencyPolicy(yaml);
  } on FormatException catch (error) {
    throw UsageException(error.message, '');
  }
}
