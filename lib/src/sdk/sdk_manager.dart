import 'dart:io';

import 'package:args/command_runner.dart';

import '../context/fluoh_environment.dart';
import '../source/source_registry.dart';
import 'sdk_release.dart';

class SdkManager {
  const SdkManager(this.environment);

  final FluohEnvironment environment;

  Future<List<SdkRelease>> listReleases() async {
    return (await SourceRegistry(environment).loadSdkIndex()).releases;
  }

  Future<SdkRelease> resolveRelease(String versionOrLine) async {
    final releases = await listReleases();
    final exactMatches = releases.where(
      (release) =>
          release.tag == versionOrLine || release.version == versionOrLine,
    );
    if (exactMatches.isNotEmpty) {
      return exactMatches.first;
    }

    final lineMatches = releases
        .where((release) => release.line == versionOrLine)
        .toList(growable: false);
    if (lineMatches.isEmpty) {
      throw UsageException('No SDK release matches "$versionOrLine".', '');
    }

    lineMatches.sort((a, b) {
      final byPublishedAt = (b.publishedAt ?? '').compareTo(
        a.publishedAt ?? '',
      );
      return byPublishedAt == 0
          ? _compareSdkTagsDescending(a.tag, b.tag)
          : byPublishedAt;
    });
    return lineMatches.first;
  }

  Future<Directory> install(SdkRelease release) async {
    final destination = sdkDirectory(release.tag);
    if (await destination.exists()) {
      return destination;
    }

    await environment.sdksDirectory.create(recursive: true);
    final repository = _resolveRepositoryPath(release.repository);
    try {
      await _git(['clone', '--quiet', repository, destination.path]);
      await _git([
        'checkout',
        '--quiet',
        'tags/${release.tag}',
      ], workingDirectory: destination);
    } catch (_) {
      if (await destination.exists()) {
        await destination.delete(recursive: true);
      }
      rethrow;
    }
    return destination;
  }

  Future<void> remove(String version) async {
    final release = await resolveRelease(version);
    final destination = sdkDirectory(release.tag);
    if (await destination.exists()) {
      await destination.delete(recursive: true);
    }
    if (await environment.currentSdkFile.exists()) {
      final current = await environment.currentSdkFile.readAsString();
      if (current.trim() == release.tag) {
        await environment.currentSdkFile.delete();
      }
    }
  }

  Future<String?> currentSdkTag() async {
    final projectTag = await _projectSdkTag();
    if (projectTag != null) {
      return projectTag;
    }
    if (!await environment.currentSdkFile.exists()) {
      return null;
    }
    return (await environment.currentSdkFile.readAsString()).trim();
  }

  Directory sdkDirectory(String tag) {
    return Directory('${environment.sdksDirectory.path}/$tag');
  }

  Future<void> markCurrent(SdkRelease release) async {
    await environment.homeDirectory.create(recursive: true);
    await environment.currentSdkFile.writeAsString(release.tag);
  }

  String _resolveRepositoryPath(String repository) {
    if (repository.startsWith('/') ||
        repository.startsWith('file:') ||
        repository.contains('://')) {
      return repository;
    }

    throw UsageException(
      'Relative SDK repositories are not supported yet: $repository',
      '',
    );
  }

  Future<String?> _projectSdkTag() async {
    final fvmrc = File('${environment.workingDirectory.path}/.fvmrc');
    if (!await fvmrc.exists()) {
      return null;
    }
    final content = await fvmrc.readAsString();
    final match = RegExp(r'"flutter"\s*:\s*"([^"]+)"').firstMatch(content);
    return match?.group(1);
  }
}

int _compareSdkTagsDescending(String a, String b) {
  return _compareNumericVersion(b, a);
}

int _compareNumericVersion(String a, String b) {
  final aParts = _numericParts(a);
  final bParts = _numericParts(b);
  final length = aParts.length > bParts.length ? aParts.length : bParts.length;
  for (var i = 0; i < length; i += 1) {
    final aPart = i < aParts.length ? aParts[i] : 0;
    final bPart = i < bParts.length ? bParts[i] : 0;
    final compared = aPart.compareTo(bPart);
    if (compared != 0) {
      return compared;
    }
  }
  return 0;
}

List<int> _numericParts(String version) {
  return RegExp(r'\d+')
      .allMatches(version)
      .map((match) => int.parse(match.group(0)!))
      .toList(growable: false);
}

Future<void> _git(List<String> arguments, {Directory? workingDirectory}) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: workingDirectory?.path,
  );
  if (result.exitCode != 0) {
    throw UsageException(
      'git ${arguments.join(' ')} failed:\n${result.stderr}',
      '',
    );
  }
}
