import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:pub_semver/pub_semver.dart';

import 'git/package_git.dart';
import 'manifest/package_manifest.dart';
import 'license_checker.dart';

/// Validates blocking package release metadata rules.
Future<void> validatePackageReleaseMetadata({
  required Directory repository,
  required PackageManifest manifest,
  required PackageManifestPackage package,
  required String tag,
}) async {
  await _ensureReleaseVersionAfterPreviousTags(
    repository,
    manifest,
    package,
    tag,
  );
}

/// Returns non-blocking package release metadata warnings.
Future<List<String>> packageReleaseMetadataWarnings({
  required Directory repository,
  required PackageManifest manifest,
  required PackageManifestPackage package,
  required String tag,
}) async {
  final warnings = <String>[];
  final releaseHistoryWarning = await _fluohReleaseHistoryWarning(
    repository,
    package,
    tag,
  );
  if (releaseHistoryWarning != null) {
    warnings.add(releaseHistoryWarning);
  }
  warnings.addAll(
    await packageLicenseWarnings(
      repository: repository,
      packagePath: package.path,
      packageName: package.name,
    ),
  );
  return warnings;
}

Future<void> _ensureReleaseVersionAfterPreviousTags(
  Directory repository,
  PackageManifest manifest,
  PackageManifestPackage package,
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

Future<String?> _fluohReleaseHistoryWarning(
  Directory repository,
  PackageManifestPackage package,
  String tag,
) async {
  final fluoh = File('${repository.path}/FLUOH.md');
  if (!await fluoh.exists()) {
    return 'Warning: Missing FLUOH.md release history for '
        '${package.name} release ${package.releaseVersion}.';
  }

  final content = await fluoh.readAsString();
  final entryLines = _releaseHistoryEntryLines(content, package, tag);
  if (entryLines == null || !_hasNonEmptyReleaseHistoryLine(entryLines)) {
    return 'Warning: FLUOH.md FlutterOH Release History does not contain '
        'a non-empty entry for ${package.name} release '
        '${package.releaseVersion}.';
  }
  if (_containsPlaceholderReleaseHistoryLine(entryLines)) {
    return 'Warning: FLUOH.md FlutterOH Release History entry for '
        '${package.name} release ${package.releaseVersion} still contains '
        'TODO placeholder release notes.';
  }
  return null;
}

List<String>? _releaseHistoryEntryLines(
  String content,
  PackageManifestPackage package,
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
          requirePackage: false,
        )) {
      continue;
    }

    final entryLines = <String>[];
    for (var j = i + 1; j < lines.length; j += 1) {
      final nextHeading = _markdownHeading(lines[j]);
      if (nextHeading != null && nextHeading.level <= releaseHeading.level) {
        break;
      }
      if (nextHeading != null) {
        continue;
      }

      entryLines.add(lines[j]);
    }
    return entryLines;
  }
  return null;
}

bool _hasNonEmptyReleaseHistoryLine(List<String> entryLines) {
  return entryLines.any((line) => line.trim().isNotEmpty);
}

bool _containsPlaceholderReleaseHistoryLine(List<String> entryLines) {
  return entryLines.any((line) {
    final trimmed = line.trimLeft();
    final withoutBullet = trimmed.startsWith('- ') || trimmed.startsWith('* ')
        ? trimmed.substring(2).trimLeft()
        : trimmed;
    return withoutBullet.toLowerCase().startsWith('todo:');
  });
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
  PackageManifestPackage package,
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
  try {
    return Version.parse(a).compareTo(Version.parse(b));
  } on FormatException catch (error) {
    throw UsageException(
      'Release versions must be valid pub semantic versions: ${error.message}',
      '',
    );
  }
}

class _MarkdownHeading {
  const _MarkdownHeading(this.level, this.text);

  final int level;
  final String text;
}
