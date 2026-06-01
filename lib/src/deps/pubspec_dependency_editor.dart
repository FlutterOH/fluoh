import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

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
  final originalContent = await pubspec.readAsString();
  try {
    final result = applyPubspecDependencyChangesToContent(
      content: originalContent,
      changes: changes,
    );
    if (changes.isNotEmpty) {
      loadYaml(result.content);
      await pubspec.writeAsString(result.content);
    }
    return result.applied;
  } on FormatException catch (error) {
    if (changes.isNotEmpty) {
      try {
        await pubspec.writeAsString(originalContent);
      } catch (_) {}
    }
    throw UsageException(error.message, '');
  } on Object {
    if (changes.isNotEmpty) {
      try {
        await pubspec.writeAsString(originalContent);
      } catch (_) {}
    }
    rethrow;
  }
}
