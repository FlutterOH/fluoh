import 'dart:io';

import 'package:args/command_runner.dart';

import '../../cli/fluoh_command_runner.dart';
import '../../context/fluoh_environment.dart';
import '../../sdk/sdk_manager.dart';
import '../git/pub_git.dart';
import '../manifest/pub_manifest.dart';
import '../pub_source_update.dart';

class PubReleaseCommand extends Command<int> {
  PubReleaseCommand({required this.environment, required OutputWriter stdout})
    : _stdout = stdout {
    argParser
      ..addFlag(
        'push',
        negatable: false,
        help: 'Push the release tag to origin after creating or validating it.',
      )
      ..addOption(
        'source-update',
        help: 'Write a FlutterOH/pub package update into this source path.',
      );
  }

  final FluohEnvironment environment;
  final OutputWriter _stdout;

  @override
  String get name => 'release';

  @override
  String get description => 'Create a FlutterOH pub release tag.';

  @override
  Future<int> run() async {
    final branch = await currentBranch(environment.workingDirectory);
    if (!branch.startsWith('ohos/')) {
      usageException('Release must run from an ohos/* pub branch.');
    }

    final manifest = await readPubManifest(environment.workingDirectory);
    if (branch != manifest.branch) {
      usageException(
        'Current branch $branch does not match pub branch '
        '${manifest.branch}.',
      );
    }
    await ensureCleanWorkingTree(environment.workingDirectory, 'Release');
    await _ensureSdkTagExists(manifest.sdkVersion);

    final expectedTag = pubReleaseTagForPackage(
      packageName: manifest.packageName,
      upstreamVersion: manifest.upstreamVersion,
      sdkVersion: manifest.sdkVersion,
      releaseVersion: manifest.releaseVersion,
    );
    final tag = manifest.releaseTag;
    if (tag != expectedTag) {
      usageException(
        'Release tag $tag does not match manifest values. Expected $expectedTag.',
      );
    }

    final existing = (await runGit(
      ['tag', '--list', tag],
      workingDirectory: environment.workingDirectory,
    )).stdout.toString().trim();
    if (existing == tag) {
      final tagCommit = (await runGit(
        ['rev-parse', '$tag^{}'],
        workingDirectory: environment.workingDirectory,
      )).stdout.toString().trim();
      final headCommit = await currentHead(environment.workingDirectory);
      if (tagCommit != headCommit) {
        usageException(
          'Release tag $tag already exists on a different commit.',
        );
      }
      _stdout('Release tag already exists: $tag.');
      if (argResults!.flag('push')) {
        await runGit([
          'push',
          'origin',
          tag,
        ], workingDirectory: environment.workingDirectory);
        _stdout('Pushed release tag $tag.');
      }
      await _writeSourceUpdateIfRequested(manifest, tag);
      return 0;
    }

    await runGit(['tag', tag], workingDirectory: environment.workingDirectory);
    if (argResults!.flag('push')) {
      await runGit([
        'push',
        'origin',
        tag,
      ], workingDirectory: environment.workingDirectory);
      _stdout('Pushed release tag $tag.');
    }
    await _writeSourceUpdateIfRequested(manifest, tag);
    _stdout('Created release tag $tag.');
    return 0;
  }

  Future<void> _ensureSdkTagExists(String sdkTag) async {
    final releases = await SdkManager(environment).listReleases();
    if (!releases.any((release) => release.tag == sdkTag)) {
      usageException('SDK tag $sdkTag was not found in configured sources.');
    }
  }

  Future<void> _writeSourceUpdateIfRequested(
    PubManifest manifest,
    String releaseTag,
  ) async {
    final sourcePath = argResults!.option('source-update');
    if (sourcePath == null || sourcePath.isEmpty) {
      return;
    }
    await writePubSourceUpdate(
      Directory(sourcePath),
      manifest: manifest,
      releaseTag: releaseTag,
    );
    _stdout('Wrote pub source update for ${manifest.packageName}.');
  }
}
