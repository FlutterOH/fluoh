import 'dart:io';

import 'package:args/command_runner.dart';

import 'git/pub_git.dart';
import 'manifest/pub_manifest.dart';
import 'pub_license_checker.dart';

Future<void> validatePubReleaseMetadata({
  required Directory repository,
  required PubManifest manifest,
  required PubManifestPackage package,
  required String tag,
}) async {
  await _ensureReleaseVersionAfterPreviousTags(
    repository,
    manifest,
    package,
    tag,
  );
}

Future<List<String>> pubReleaseMetadataWarnings({
  required Directory repository,
  required PubManifest manifest,
  required PubManifestPackage package,
  required String tag,
}) async {
  final warnings = <String>[];
  final changelogWarning = await _fluohChangelogWarning(
    repository,
    manifest,
    package,
    tag,
  );
  if (changelogWarning != null) {
    warnings.add(changelogWarning);
  }
  warnings.addAll(
    await pubLicenseWarnings(
      repository: repository,
      packagePath: package.dependencyPath,
      packageName: package.name,
    ),
  );
  return warnings;
}

Future<void> _ensureReleaseVersionAfterPreviousTags(
  Directory repository,
  PubManifest manifest,
  PubManifestPackage package,
  String tag,
) async {
  final prefix = tag.substring(0, tag.length - package.releaseVersion.length);
  final result = await runGit([
    'tag',
    '--list',
    '$prefix*',
  ], workingDirectory: repository);
  final previousVersions = result.stdout
      .toString()
      .split('\n')
      .map((line) => line.trim())
      .where((existingTag) => existingTag.isNotEmpty && existingTag != tag)
      .where((existingTag) => existingTag.startsWith(prefix))
      .map((existingTag) => existingTag.substring(prefix.length))
      .where((version) => version.isNotEmpty)
      .toList(growable: false);
  if (previousVersions.isEmpty) {
    return;
  }

  final latest = previousVersions.reduce((a, b) {
    return _compareReleaseVersions(a, b) >= 0 ? a : b;
  });
  if (_compareReleaseVersions(package.releaseVersion, latest) <= 0) {
    throw UsageException(
      'Release version ${package.releaseVersion} must be greater than '
          'latest release version $latest for this package, upstream version, '
          'and SDK.',
      '',
    );
  }
}

Future<String?> _fluohChangelogWarning(
  Directory repository,
  PubManifest manifest,
  PubManifestPackage package,
  String tag,
) async {
  final changelog = File('${repository.path}/FLUOH_CHANGELOG.md');
  if (!await changelog.exists()) {
    return 'Warning: Missing FLUOH_CHANGELOG.md for '
        '${package.name} release ${package.releaseVersion}.';
  }

  final content = await changelog.readAsString();
  if (!_hasChangelogEntry(content, manifest, package, tag)) {
    return 'Warning: FLUOH_CHANGELOG.md does not contain a non-empty '
        'entry for ${package.name} release ${package.releaseVersion}.';
  }
  return null;
}

bool _hasChangelogEntry(
  String content,
  PubManifest manifest,
  PubManifestPackage package,
  String tag,
) {
  final lines = content.split('\n');
  for (var i = 0; i < lines.length; i += 1) {
    final releaseHeading = _markdownHeading(lines[i]);
    if (releaseHeading == null ||
        !_isReleaseHeading(
          releaseHeading,
          package,
          tag,
          requirePackage: manifest.packages.length > 1,
        )) {
      continue;
    }

    for (var j = i + 1; j < lines.length; j += 1) {
      final nextHeading = _markdownHeading(lines[j]);
      if (nextHeading != null && nextHeading.level <= releaseHeading.level) {
        return false;
      }
      if (nextHeading != null) {
        continue;
      }

      final line = lines[j].trim();
      if (line.isNotEmpty) {
        return true;
      }
    }
    return false;
  }
  return false;
}

_MarkdownHeading? _markdownHeading(String line) {
  final match = RegExp(r'^\s{0,3}(#{1,6})\s+(.+?)\s*$').firstMatch(line);
  if (match == null) {
    return null;
  }
  return _MarkdownHeading(match.group(1)!.length, match.group(2)!);
}

bool _isReleaseHeading(
  _MarkdownHeading heading,
  PubManifestPackage package,
  String tag, {
  required bool requirePackage,
}) {
  if (_headingContainsRelease(heading.text, tag)) {
    return true;
  }
  if (!_headingContainsRelease(heading.text, package.releaseVersion)) {
    return false;
  }
  return !requirePackage || heading.text.contains(package.name);
}

bool _headingContainsRelease(String heading, String value) {
  final escaped = RegExp.escape(value);
  return RegExp(r'(^|[\[\s])' + escaped + r'($|[\]\s):,-])').hasMatch(heading);
}

int _compareReleaseVersions(String a, String b) {
  final aParts = _numericReleaseParts(a);
  final bParts = _numericReleaseParts(b);
  final maxLength = aParts.length > bParts.length
      ? aParts.length
      : bParts.length;
  for (var i = 0; i < maxLength; i += 1) {
    final left = i < aParts.length ? aParts[i] : 0;
    final right = i < bParts.length ? bParts[i] : 0;
    if (left != right) {
      return left.compareTo(right);
    }
  }
  return 0;
}

List<int> _numericReleaseParts(String version) {
  final core = version.split(RegExp(r'[-+]')).first;
  if (!RegExp(r'^\d+(?:\.\d+)*$').hasMatch(core)) {
    throw UsageException(
      'Release version $version must use numeric dot-separated parts.',
      '',
    );
  }
  return core.split('.').map(int.parse).toList(growable: false);
}

class _MarkdownHeading {
  const _MarkdownHeading(this.level, this.text);

  final int level;
  final String text;
}
