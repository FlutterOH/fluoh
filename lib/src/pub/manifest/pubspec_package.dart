import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

class PubspecPackage {
  const PubspecPackage({required this.name, required this.version});

  final String name;
  final String version;
}

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
  final yaml = loadYaml(await pubspec.readAsString());
  if (yaml is! YamlMap) {
    throw UsageException('pubspec.yaml must contain a YAML map.', '');
  }
  final name = yaml['name'];
  final version = yaml['version'];
  if (name is! String || version is! String) {
    throw UsageException('pubspec.yaml must contain name and version.', '');
  }
  return PubspecPackage(name: name, version: version);
}
