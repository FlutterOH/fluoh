import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

class PackageInfo {
  const PackageInfo({required this.name, required this.version});

  final String name;
  final String version;
}

Directory packageDirectory(Directory repository, String packagePath) {
  if (packagePath == '.' || packagePath.isEmpty) {
    return repository;
  }
  return Directory('${repository.path}/$packagePath');
}

Future<PackageInfo> readPackageInfo(Directory repository) async {
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
  return PackageInfo(name: name, version: version);
}

Future<String> findPackagePath(Directory repository, String packageName) async {
  await for (final entity in repository.list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('/pubspec.yaml')) {
      continue;
    }
    if (entity.path.contains('/.git/')) {
      continue;
    }
    final package = await readPackageInfo(entity.parent);
    if (package.name == packageName) {
      final relative = entity.parent.path.substring(repository.path.length);
      final normalized = relative.startsWith('/')
          ? relative.substring(1)
          : relative;
      return normalized.isEmpty ? '.' : normalized;
    }
  }
  throw UsageException(
    'Package $packageName was not found in upstream repository.',
    '',
  );
}
