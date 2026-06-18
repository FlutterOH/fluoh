import 'dart:io';

import 'package:args/command_runner.dart';

import '../../schema/schema.dart';

export '../../schema/schema.dart' show PubspecPackage;

/// Resolves a package path inside [repository].
Directory packageDirectory(Directory repository, String packagePath) {
  if (packagePath == '.' || packagePath.isEmpty) {
    return repository;
  }
  return Directory('${repository.path}/$packagePath');
}

/// Reads package name and version from a package pubspec.
Future<PubspecPackage> readPubspecPackage(
  Directory repository, {
  String description = 'package directory',
}) async {
  final pubspec = File('${repository.path}/pubspec.yaml');
  if (!await pubspec.exists()) {
    throw UsageException('Missing pubspec.yaml in $description.', '');
  }
  try {
    return PubspecPackage.fromYaml(await pubspec.readAsString());
  } on FormatException catch (error) {
    throw UsageException(error.message, '');
  }
}
