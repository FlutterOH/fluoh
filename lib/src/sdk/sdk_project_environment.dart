import 'dart:io';

import 'package:args/command_runner.dart';

import '../context/fluoh_environment.dart';
import '../schema/schema.dart';
import 'sdk_manager.dart';

/// Applies SDK selection state to a Flutter project.
class SdkProjectEnvironment {
  /// Creates a project SDK environment helper.
  const SdkProjectEnvironment(this.environment);

  /// Runtime environment for the target project.
  final FluohEnvironment environment;

  /// Installs [release] when needed and writes project SDK files.
  Future<Directory> configure(
    SdkRelease release, {
    bool writeFluohConfig = true,
  }) async {
    final manager = SdkManager(environment);
    final sdkDirectory = await manager.install(release);
    await writeFiles(release, writeFluohConfig: writeFluohConfig);
    return sdkDirectory;
  }

  /// Writes project files for [release].
  Future<void> writeFiles(
    SdkRelease release, {
    bool writeFluohConfig = true,
  }) async {
    await writeSdkVersion(release.tag, writeFluohConfig: writeFluohConfig);
  }

  /// Writes the selected SDK version to project configuration.
  Future<void> writeSdkVersion(
    String sdkVersion, {
    bool writeFluohConfig = true,
  }) async {
    if (writeFluohConfig) {
      await _writeProjectFluohConfig(sdkVersion);
    }
  }

  /// Creates or refreshes the IDE SDK symlink under `.fluoh/flutter_sdk`.
  Future<Directory> linkIdeSdk(Directory sdkDirectory) async {
    final linkRoot = Directory('${environment.workingDirectory.path}/.fluoh');
    await ensureIdeSdkLinkCanBeUpdated();
    await linkRoot.create(recursive: true);
    final link = Link('${linkRoot.path}/flutter_sdk');
    await _replaceWithLink(link, sdkDirectory);
    await _ensureGitIgnoreEntry('.fluoh/');
    await _ensureGitIgnoreEntry('flutter_*.log');
    return Directory(link.path);
  }

  /// Verifies the IDE SDK link path can be safely replaced.
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

  Future<void> _writeProjectFluohConfig(String sdkVersion) async {
    final config = File('${environment.workingDirectory.path}/fluoh.yaml');
    if (!await config.exists()) {
      await config.writeAsString(newProjectFluohConfigContent(sdkVersion));
      return;
    }

    final content = await config.readAsString();
    if (content.trim().isEmpty) {
      await config.writeAsString(newProjectFluohConfigContent(sdkVersion));
      return;
    }

    await config.writeAsString(upsertProjectSdkVersion(content, sdkVersion));
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
