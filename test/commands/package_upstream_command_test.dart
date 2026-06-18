import 'dart:convert';
import 'dart:io';

import 'package:fluoh/fluoh.dart';
import 'package:fluoh/src/package/manifest/package_manifest.dart';
import 'package:test/test.dart';

import '../helpers/fluoh_command_context.dart';
import '../helpers/package_test_context.dart';

part 'package_upstream_core_part.dart';
part 'package_upstream_continuation_part.dart';
part 'package_upstream_diagnostics_part.dart';

void main() {
  _registerPackageUpstreamSyncCoreTests();
  _registerPackageUpstreamSyncContinuationTests();
  _registerPackageUpstreamSyncDiagnosticTests();
}

Future<void> _addWorkspacePackage(
  Directory repository, {
  required String path,
  required String name,
  required String version,
}) async {
  final packageDirectory = Directory('${repository.path}/$path');
  await packageDirectory.create(recursive: true);
  await File('${packageDirectory.path}/pubspec.yaml').writeAsString('''
name: $name
version: $version

environment:
  sdk: ^3.0.0
''');
  await runGit(repository, ['add', '.']);
  await runGit(repository, ['commit', '-m', 'Add $name fixture']);
}
