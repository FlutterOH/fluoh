import 'dart:io';

import 'package:args/command_runner.dart';

import '../../schema/schema.dart';

export '../../schema/schema.dart' show PubspecPackage;

Directory packageDirectory(Directory repository, String packagePath) {
  if (packagePath == '.' || packagePath.isEmpty) {
    return repository;
  }
  return Directory('${repository.path}/$packagePath');
}

Future<PubspecPackage> readPubspecPackage(Directory repository) async {
  final pubspec = File('${repository.path}/pubspec.yaml');
  if (!await pubspec.exists()) {
    throw UsageException('Missing pubspec.yaml in upstream repository.', '');
  }
  try {
    return PubspecPackage.fromYaml(await pubspec.readAsString());
  } on FormatException catch (error) {
    throw UsageException(error.message, '');
  }
}
