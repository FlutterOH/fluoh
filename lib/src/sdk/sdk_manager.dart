import 'dart:io';

import 'package:args/command_runner.dart';

import '../context/fluoh_environment.dart';
import '../source/source_registry.dart';
import 'sdk_project_config.dart';
import 'sdk_release.dart';

class SdkManager {
  const SdkManager(this.environment);

  final FluohEnvironment environment;

  Future<List<SdkRelease>> listReleases() async {
    return (await SourceRegistry(environment).loadSdkIndex()).releases;
  }

  Future<List<SdkListEntry>> listEntries() async {
    final installedTags = await installedSdkTags();
    try {
      final releases = await listReleases();
      final releaseTags = <String>{};
      final entries = <SdkListEntry>[
        for (final release in releases)
          SdkListEntry(
            tag: release.tag,
            channel: release.channel,
            installed: installedTags.contains(release.tag),
          ),
      ];
      releaseTags.addAll(releases.map((release) => release.tag));
      entries.addAll(
        installedTags
            .where((tag) => !releaseTags.contains(tag))
            .map(SdkListEntry.local),
      );
      return entries;
    } on UsageException catch (error) {
      if (!_isMissingSdkIndex(error) || installedTags.isEmpty) {
        rethrow;
      }
      return installedTags.map(SdkListEntry.local).toList(growable: false);
    }
  }

  Future<SdkRelease> resolveRelease(String version) async {
    final query = version.trim();
    final releases = await listReleases();
    final exactMatches = releases.where(
      (release) => release.tag == query || release.version == query,
    );
    if (exactMatches.isNotEmpty) {
      return exactMatches.first;
    }

    final seriesMatches = releases.where(
      (release) => release.versionSeries == query,
    );
    if (seriesMatches.isNotEmpty) {
      return latestRelease(seriesMatches, preferStable: true);
    }

    throw UsageException(
      'No SDK release matches "$version". Run "fluoh sdk list".',
      '',
    );
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

  Future<String> remove(String version) async {
    final query = version.trim();
    SdkRelease? release;
    try {
      release = await resolveRelease(query);
    } on UsageException catch (error) {
      if (!_canRemoveExactLocalSdk(error, query)) {
        rethrow;
      }
    }

    final tag = release?.tag ?? query;
    if (release == null && !await _isInstalledSdkTag(tag)) {
      throw UsageException(
        'No installed SDK matches "$query". Run "fluoh sdk list".',
        '',
      );
    }

    final destination = sdkDirectory(tag);
    if (await destination.exists()) {
      await destination.delete(recursive: true);
      return tag;
    }
    if (release == null) {
      throw UsageException(
        'No installed SDK matches "$query". Run "fluoh sdk list".',
        '',
      );
    }
    return tag;
  }

  Future<String?> currentSdkTag() async {
    return _projectSdkTag();
  }

  Directory sdkDirectory(String tag) {
    return Directory('${environment.sdksDirectory.path}/$tag');
  }

  Future<List<String>> installedSdkTags() async {
    final directory = environment.sdksDirectory;
    if (!await directory.exists()) {
      return const [];
    }

    final tags = <String>[];
    await for (final entity in directory.list(
      recursive: false,
      followLinks: false,
    )) {
      if (entity is! Directory) {
        continue;
      }
      final tag = _basename(entity.path);
      if (tag.isEmpty || tag.startsWith('.')) {
        continue;
      }
      tags.add(tag);
    }
    tags.sort(_compareSdkTagsDescending);
    return tags;
  }

  static SdkRelease latestRelease(
    Iterable<SdkRelease> releases, {
    bool preferStable = false,
  }) {
    var candidates = releases.toList(growable: false);
    if (preferStable) {
      final stable = candidates
          .where((release) => release.channel == 'stable')
          .toList(growable: false);
      if (stable.isNotEmpty) {
        candidates = stable;
      }
    }
    candidates.sort(_compareSdkReleasesDescending);
    return candidates.first;
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
    return readProjectSdkTag(environment.workingDirectory);
  }

  bool _canRemoveExactLocalSdk(UsageException error, String query) {
    return query.isNotEmpty &&
        (_isMissingSdkIndex(error) ||
            error.message.startsWith('No SDK release matches '));
  }

  Future<bool> _isInstalledSdkTag(String tag) async {
    return (await installedSdkTags()).contains(tag);
  }
}

class SdkListEntry {
  const SdkListEntry({
    required this.tag,
    required this.channel,
    required this.installed,
  });

  SdkListEntry.local(String tag)
    : this(tag: tag, channel: 'unknown', installed: true);

  final String tag;
  final String channel;
  final bool installed;
}

int _compareSdkReleasesDescending(SdkRelease a, SdkRelease b) {
  final byPublishedAt = (b.publishedAt ?? '').compareTo(a.publishedAt ?? '');
  if (byPublishedAt != 0) {
    return byPublishedAt;
  }
  return _compareNumericVersion(b.tag, a.tag);
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

int _compareSdkTagsDescending(String a, String b) {
  final byVersion = _compareNumericVersion(b, a);
  if (byVersion != 0) {
    return byVersion;
  }
  return b.compareTo(a);
}

bool _isMissingSdkIndex(UsageException error) {
  return error.message.startsWith('No readable data source index found.');
}

String _basename(String path) {
  final normalized = path.endsWith(Platform.pathSeparator)
      ? path.substring(0, path.length - 1)
      : path;
  return normalized.split(Platform.pathSeparator).last;
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
