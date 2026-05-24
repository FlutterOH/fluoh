import 'dart:io';

import 'package:args/command_runner.dart';

import '../schema/schema.dart';

export '../schema/schema.dart'
    show
        PubspecDependencyChange,
        PubspecDependencyChangeKind,
        PubspecDependencyRef,
        PubspecDependencySection,
        PubspecDependencyState;

Future<PubspecDependencyState> readPubspecDependencyState(File pubspec) async {
  return parsePubspecDependencyState(await pubspec.readAsString());
}

Future<int> applyPubspecDependencyChanges({
  required File pubspec,
  required List<PubspecDependencyChange> changes,
}) async {
  try {
    final result = applyPubspecDependencyChangesToContent(
      content: await pubspec.readAsString(),
      changes: changes,
    );
    if (changes.isNotEmpty) {
      await pubspec.writeAsString(result.content);
    }
    return result.applied;
  } on FormatException catch (error) {
    throw UsageException(error.message, '');
  }
}
