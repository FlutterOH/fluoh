import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

part 'release_artifacts_ci_part.dart';
part 'release_artifacts_skill_part.dart';
part 'release_artifacts_docs_part.dart';
part 'release_artifacts_commands_part.dart';

void expectContainsAll(String actual, Iterable<String> expected) {
  for (final value in expected) {
    expect(actual, contains(value), reason: 'Expected to find "$value".');
  }
}

void expectContainsNone(String actual, Iterable<String> unexpected) {
  for (final value in unexpected) {
    expect(
      actual,
      isNot(contains(value)),
      reason: 'Did not expect to find "$value".',
    );
  }
}

List<String> issueFormIds(YamlMap template) {
  final body = template['body'] as YamlList;
  return [
    for (final field in body)
      if (field is YamlMap && field['id'] != null) field['id'] as String,
  ];
}

YamlMap issueFormField(YamlMap template, String id) {
  final body = template['body'] as YamlList;
  for (final field in body) {
    if (field is YamlMap && field['id'] == id) {
      return field;
    }
  }
  fail('Expected issue form field "$id".');
}

List<String> issueFormOptions(YamlMap template, String id) {
  final field = issueFormField(template, id);
  final attributes = field['attributes'] as YamlMap;
  final options = attributes['options'] as YamlList;
  return [
    for (final option in options)
      if (option is String)
        option
      else if (option is YamlMap)
        option['label'] as String,
  ];
}

List<String> markdownHeadings(String markdown) {
  return RegExp(
    r'^## (.+)$',
    multiLine: true,
  ).allMatches(markdown).map((match) => match.group(1)!).toList();
}

void main() {
  _registerReleaseArtifactsCiTests();
  _registerReleaseArtifactsSkillTests();
  _registerReleaseArtifactsDocsTests();
  _registerReleaseArtifactsCommandTests();
}
