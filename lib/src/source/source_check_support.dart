part of 'source_check_command.dart';

extension on SourceCheckCommand {
  Future<_ProcessCheckResult> _runProcess(
    List<String> command, {
    required Directory workingDirectory,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    try {
      final result = await Process.run(
        command.first,
        command.skip(1).toList(growable: false),
        workingDirectory: workingDirectory.path,
      ).timeout(timeout);
      return _ProcessCheckResult(
        command: command,
        exitCode: result.exitCode,
        stdout: result.stdout.toString().trim(),
        stderr: result.stderr.toString().trim(),
      );
    } on TimeoutException {
      return _ProcessCheckResult(
        command: command,
        exitCode: null,
        stdout: '',
        stderr: 'Timed out after ${timeout.inSeconds}s',
      );
    } on ProcessException catch (error) {
      return _ProcessCheckResult(
        command: command,
        exitCode: null,
        stdout: '',
        stderr: error.message,
      );
    } on OSError catch (error) {
      return _ProcessCheckResult(
        command: command,
        exitCode: null,
        stdout: '',
        stderr: error.message,
      );
    }
  }

  int _positiveIntOption(String name, {required int defaultValue}) {
    final value = argResults!.option(name)?.trim();
    if (value == null || value.isEmpty) {
      return defaultValue;
    }
    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0) {
      usageException('--$name must be a positive integer.');
    }
    return parsed;
  }

  Set<String> _multiOptionSet(String name) {
    final values = <String>{};
    for (final value in argResults!.multiOption(name)) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        usageException('--$name values must not be empty.');
      }
      values.add(trimmed);
    }
    return values;
  }

  _ReleaseCheckShard? _parseShardOption(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final match = RegExp(r'^([0-9]+)/([0-9]+)$').firstMatch(value);
    if (match == null) {
      usageException('--shard must use index/total, for example 1/10.');
    }
    final index = int.parse(match.group(1)!);
    final total = int.parse(match.group(2)!);
    if (index <= 0 || total <= 0 || index > total) {
      usageException('--shard index must be between 1 and the shard total.');
    }
    return _ReleaseCheckShard(index: index, total: total);
  }

  Future<_SourceChangeSummary> _classifySourceChanges({
    required Directory source,
    required SourceRootManifest headRootManifest,
    required String? baseRef,
    required bool all,
    required bool checkAllManifests,
    required List<String> changedFiles,
    required _ReleaseCheckPlan releasePlan,
  }) async {
    final types = <String>{};
    if (all) {
      types.add('full-audit');
    }
    if (checkAllManifests) {
      types.add('diff-fallback');
    }
    if (changedFiles.isEmpty && !all && !checkAllManifests) {
      return _SourceChangeSummary.none;
    }

    if (changedFiles.contains('fluoh.yaml')) {
      types.addAll(
        await _classifyRootChange(
          source: source,
          headRootManifest: headRootManifest,
          baseRef: baseRef,
        ),
      );
    }

    final changedManifestNames = <String>{
      for (final file in changedFiles)
        if (RegExp(r'^manifests/([^/]+)/fluoh\.yaml$').firstMatch(file)
            case final match?)
          match.group(1)!,
    };
    for (final name in changedManifestNames) {
      types.addAll(
        await _classifyManifestChange(
          source: source,
          baseRef: baseRef,
          name: name,
        ),
      );
    }

    if (releasePlan.changedRecords.isNotEmpty) {
      types.add('release-record');
    }
    if (types.isEmpty && changedFiles.isNotEmpty) {
      types.add('supporting-files');
    }
    return _SourceChangeSummary(types.toList(growable: false)..sort());
  }

  Future<List<String>> _classifyRootChange({
    required Directory source,
    required SourceRootManifest headRootManifest,
    required String? baseRef,
  }) async {
    if (baseRef == null) {
      return const ['source-root'];
    }
    final baseRootManifest = await _readBaseRootManifest(source, baseRef);
    if (baseRootManifest == null) {
      return const ['source-root'];
    }
    final types = <String>{};
    if (baseRootManifest.sdkRepository != headRootManifest.sdkRepository ||
        _sdkReleaseVersions(baseRootManifest) !=
            _sdkReleaseVersions(headRootManifest)) {
      types.add('sdk-versions');
    }
    if (_rootManifestRoutes(baseRootManifest) !=
        _rootManifestRoutes(headRootManifest)) {
      types.add('manifest-route');
    }
    if (_rootManifestMetadataFingerprint(baseRootManifest) !=
        _rootManifestMetadataFingerprint(headRootManifest)) {
      types.add('source-root');
    }
    return types.isEmpty ? const ['source-root'] : types.toList();
  }

  Future<List<String>> _classifyManifestChange({
    required Directory source,
    required String? baseRef,
    required String name,
  }) async {
    final headFile = File('${source.path}/manifests/$name/fluoh.yaml');
    final headExists = await headFile.exists();
    if (baseRef == null) {
      return headExists ? const ['manifest'] : const ['manifest-deleted'];
    }
    final baseManifest = await _readBaseSourceManifest(source, baseRef, name);
    if (baseManifest == null) {
      return headExists ? const ['manifest-added'] : const ['manifest-deleted'];
    }
    if (!headExists) {
      return const ['manifest-deleted'];
    }
    final headManifest = await _readCheckedManifest(source, name);
    final head = headManifest.manifest;
    final types = <String>{};
    if (_sourceManifestMetadataFingerprint(baseManifest) !=
        _sourceManifestMetadataFingerprint(head)) {
      types.add('manifest-metadata');
    }
    final baseReleases = _manifestReleaseFingerprints(baseManifest);
    final headReleases = _manifestReleaseFingerprints(head);
    if (baseReleases.keys
        .toSet()
        .difference(headReleases.keys.toSet())
        .isNotEmpty) {
      types.add('release-record-deleted');
    }
    if (headReleases.keys
            .toSet()
            .difference(baseReleases.keys.toSet())
            .isNotEmpty ||
        headReleases.entries.any(
          (entry) =>
              baseReleases[entry.key] != null &&
              baseReleases[entry.key] != entry.value,
        )) {
      types.add('release-record');
    }
    if (types.isEmpty &&
        _advisoryMaintenanceFingerprint(baseManifest) !=
            _advisoryMaintenanceFingerprint(head)) {
      types.add('advisory-maintenance');
    }
    return types.isEmpty ? const ['manifest'] : types.toList();
  }

  void _printHumanReport(_SourceCheckReport report) {
    _output.write('Source check: ${report.recommendation}');
    _output.write('Checked manifests: ${report.checkedManifests.join(', ')}');
    if (report.errors.isNotEmpty) {
      _output.error('Errors');
      for (final error in report.errors) {
        _output.write('- $error');
      }
    }
    if (report.warnings.isNotEmpty) {
      _output.warning('Warnings');
      for (final warning in report.warnings) {
        _output.write('- $warning');
      }
    }
    if (report.ok) {
      _output.success('Technical checks completed');
    }
  }
}
