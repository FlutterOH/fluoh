part of 'source_runtime.dart';

Future<_SourceSnapshotTransaction> _replaceSourceSnapshotForTransaction({
  required Directory source,
  required Directory destination,
}) async {
  final parent = destination.parent;
  await parent.create(recursive: true);
  var staging = await parent.createTemp('.${basename(destination.path)}-next-');
  Directory? backup;
  var installed = false;
  try {
    await copySourceSnapshot(source, staging);
    final fingerprint = await _snapshotFingerprint(staging);
    await _writeSnapshotState(
      staging,
      await _calculateSnapshotHash(staging),
      fingerprint,
    );
    if (await destination.exists()) {
      backup = await destination.rename(
        '${parent.path}/.${basename(destination.path)}-previous-'
        '${DateTime.now().microsecondsSinceEpoch}',
      );
    }
    await staging.rename(destination.path);
    staging = Directory('');
    installed = true;
    return _SourceSnapshotTransaction(destination: destination, backup: backup);
  } catch (_) {
    if (installed && await destination.exists()) {
      await deleteIfExists(destination);
    }
    if (backup != null &&
        await backup.exists() &&
        !await destination.exists()) {
      await backup.rename(destination.path);
    }
    rethrow;
  } finally {
    if (staging.path.isNotEmpty) {
      await deleteIfExists(staging);
    }
  }
}

class _SourceSnapshotTransaction {
  const _SourceSnapshotTransaction({required this.destination, this.backup});

  final Directory destination;
  final Directory? backup;

  Future<void> restore() async {
    if (await destination.exists()) {
      await deleteIfExists(destination);
    }
    if (backup != null && await backup!.exists()) {
      await backup!.rename(destination.path);
    }
  }

  Future<void> cleanup() async {
    if (backup != null && await backup!.exists()) {
      await deleteIfExists(backup!);
    }
  }
}

class _NamedSource {
  const _NamedSource(this.name, this.config);

  final String name;
  final SourceConfig config;
}

class _PrioritizedRelease {
  const _PrioritizedRelease(this.source, this.release);

  String get name => source.name;

  final _NamedSource source;
  final SdkRelease release;
}

class _Replacement {
  const _Replacement({
    required this.repository,
    required this.tag,
    required this.path,
    required this.status,
    required this.priority,
    required this.sourceName,
  });

  factory _Replacement.fromImplementation(
    PackageImplementation implementation,
    String sourceName,
  ) {
    return _Replacement(
      repository: implementation.repository,
      tag: implementation.tag,
      path: implementation.path,
      status: implementation.status,
      priority: implementation.sourcePriority,
      sourceName: sourceName,
    );
  }

  final String repository;
  final String tag;
  final String? path;
  final String status;
  final int priority;
  final String sourceName;

  @override
  bool operator ==(Object other) {
    return other is _Replacement &&
        repository == other.repository &&
        tag == other.tag &&
        path == other.path &&
        status == other.status &&
        priority == other.priority;
  }

  @override
  int get hashCode => Object.hash(repository, tag, path, status, priority);
}

class _CompatibilityStatus {
  const _CompatibilityStatus({
    required this.status,
    required this.priority,
    required this.sourceName,
  });

  final String status;
  final int priority;
  final String sourceName;
}
