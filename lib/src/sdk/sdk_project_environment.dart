import 'dart:io';

import 'package:args/command_runner.dart';

import '../context/fluoh_environment.dart';
import 'sdk_manager.dart';
import 'sdk_release.dart';

class SdkProjectEnvironment {
  const SdkProjectEnvironment(this.environment);

  final FluohEnvironment environment;

  Future<Directory> configure(
    SdkRelease release, {
    bool writeFluohConfig = true,
  }) async {
    final manager = SdkManager(environment);
    final sdkDirectory = await manager.install(release);
    await writeFiles(release, writeFluohConfig: writeFluohConfig);
    return sdkDirectory;
  }

  Future<void> writeFiles(
    SdkRelease release, {
    bool writeFluohConfig = true,
  }) async {
    if (writeFluohConfig) {
      await _writeProjectFluohConfig(release);
    }
  }

  Future<Directory> linkIdeSdk(Directory sdkDirectory) async {
    final linkRoot = Directory('${environment.workingDirectory.path}/.fluoh');
    await ensureIdeSdkLinkCanBeUpdated();
    await linkRoot.create(recursive: true);
    final link = Link('${linkRoot.path}/flutter_sdk');
    await _replaceWithLink(link, sdkDirectory);
    await _ensureGitIgnoreEntry('.fluoh/');
    return Directory(link.path);
  }

  Future<void> ensureIdeSdkLinkCanBeUpdated() async {
    final linkRoot = Directory('${environment.workingDirectory.path}/.fluoh');
    final rootType = await FileSystemEntity.type(
      linkRoot.path,
      followLinks: false,
    );
    if (rootType != FileSystemEntityType.notFound &&
        rootType != FileSystemEntityType.directory) {
      throw UsageException(
        'Cannot create IDE Flutter SDK link because ${linkRoot.path} already '
            'exists and is not a directory. Move it aside and run the command again.',
        '',
      );
    }

    final link = Link('${linkRoot.path}/flutter_sdk');
    final type = await FileSystemEntity.type(link.path, followLinks: false);
    if (type == FileSystemEntityType.notFound ||
        type == FileSystemEntityType.link) {
      return;
    }

    throw UsageException(
      'Cannot create IDE Flutter SDK link because ${link.path} already '
          'exists and is not a symlink. Move it aside and run the command again.',
      '',
    );
  }

  Future<void> _writeProjectFluohConfig(SdkRelease release) async {
    final config = File('${environment.workingDirectory.path}/fluoh.yaml');
    if (!await config.exists()) {
      await config.writeAsString(_newProjectFluohConfig(release));
      return;
    }

    final content = await config.readAsString();
    if (content.trim().isEmpty) {
      await config.writeAsString(_newProjectFluohConfig(release));
      return;
    }

    await config.writeAsString(_updatedProjectFluohConfig(content, release));
  }

  Future<void> _replaceWithLink(Link link, Directory target) async {
    if (await link.exists()) {
      await link.delete();
    }
    await link.create(target.path);
  }

  Future<void> _ensureGitIgnoreEntry(String entry) async {
    final gitignore = File('${environment.workingDirectory.path}/.gitignore');
    if (!await gitignore.exists()) {
      await gitignore.writeAsString('$entry\n');
      return;
    }

    final content = await gitignore.readAsString();
    final exists = content
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .contains(entry);
    if (exists) {
      return;
    }

    final separator = content.isEmpty || content.endsWith('\n') ? '' : '\n';
    await gitignore.writeAsString('$content$separator$entry\n');
  }
}

String _newProjectFluohConfig(SdkRelease release) {
  return [
    'schema: 1',
    '',
    'sdk:',
    '  version: ${release.tag}',
    '',
    'dependencyPolicy:',
    '  # replacementMode controls where fluoh pub fix writes OHOS adapters:',
    '  # - overrides: add dependency_overrides without changing dependencies.',
    '  # - rewrite: replace matching entries in dependencies directly.',
    '  replacementMode: overrides',
    '  # versionMismatch controls version differences after exact matches and compatible upgrades:',
    '  # - skip: leave incompatible version changes and downgrades for manual review.',
    '  # - allow: apply the recommended adapter anyway.',
    '  versionMismatch: skip',
    '',
  ].join('\n');
}

String _updatedProjectFluohConfig(String content, SdkRelease release) {
  final lines = content.split('\n');
  if (content.endsWith('\n')) {
    lines.removeLast();
  }

  final sdkIndex = _topLevelKeyIndex(lines, 'sdk');
  if (sdkIndex != -1) {
    if (_isTopLevelBlockSection(lines[sdkIndex], 'sdk')) {
      _upsertSdkVersion(lines, sdkIndex, release.tag);
    } else {
      lines[sdkIndex] = 'sdk:';
      lines.insert(sdkIndex + 1, '  version: ${release.tag}');
    }
    return '${lines.join('\n')}\n';
  }

  final schemaIndex = _topLevelKeyIndex(lines, 'schema');
  final insertIndex = schemaIndex == -1 ? 0 : schemaIndex + 1;
  lines.insertAll(insertIndex, [
    if (schemaIndex != -1) '',
    'sdk:',
    '  version: ${release.tag}',
    '',
  ]);
  return '${lines.join('\n')}\n';
}

void _upsertSdkVersion(List<String> lines, int sdkIndex, String sdkTag) {
  final end = _topLevelSectionEnd(lines, sdkIndex);
  for (var i = sdkIndex + 1; i < end; i += 1) {
    final match = RegExp(
      r'^([ \t]+)version\s*:(?:\s*[^#]*)?(\s+#.*)?$',
    ).firstMatch(lines[i]);
    if (match == null) {
      continue;
    }
    lines[i] = '${match.group(1)}version: $sdkTag${match.group(2) ?? ''}';
    return;
  }

  lines.insert(sdkIndex + 1, '  version: $sdkTag');
}

int _topLevelKeyIndex(List<String> lines, String name) {
  return lines.indexWhere(
    (line) => RegExp('^${RegExp.escape(name)}:(?:\\s.*)?\$').hasMatch(line),
  );
}

bool _isTopLevelBlockSection(String line, String name) {
  return RegExp('^${RegExp.escape(name)}:\\s*(?:#.*)?\$').hasMatch(line);
}

int _topLevelSectionEnd(List<String> lines, int sectionIndex) {
  for (var i = sectionIndex + 1; i < lines.length; i += 1) {
    final line = lines[i];
    if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('\t')) {
      return i;
    }
  }
  return lines.length;
}
