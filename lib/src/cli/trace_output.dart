import 'dart:convert';
import 'dart:io';

import '../context/fluoh_environment.dart';
import '../version.dart';

/// Local trace schema written by commands that support `--trace`.
const traceOutputSchema = 1;

/// Optional command trace configuration parsed from command-line options.
class TraceOptions {
  /// Creates trace options.
  const TraceOptions({required this.enabled, this.directory});

  /// Whether trace output should be written.
  final bool enabled;

  /// Explicit trace directory requested by the caller.
  final FileSystemEntity? directory;

  /// No trace output.
  static const disabled = TraceOptions(enabled: false);
}

/// Reference included in machine-readable command output.
class TraceReference {
  /// Creates a trace reference.
  const TraceReference({required this.id, required this.path});

  /// Stable local trace id.
  final String id;

  /// Trace directory.
  final Directory path;

  /// Trace manifest file.
  File get manifest => File('${path.path}/trace.json');

  /// Converts this reference to JSON.
  Map<String, Object?> toJson() {
    return {
      'schema': traceOutputSchema,
      'id': id,
      'path': path.path,
      'manifest': manifest.path,
    };
  }
}

/// Result of attempting to write a command trace.
class TraceWriteResult {
  /// Creates a trace write result.
  const TraceWriteResult({this.reference, this.error});

  /// Trace reference when writing succeeded.
  final TraceReference? reference;

  /// Human-readable write error when tracing was requested but failed.
  final String? error;

  /// No trace was requested.
  static const skipped = TraceWriteResult();
}

/// Writes one command trace manifest and returns its machine-output reference.
Future<TraceWriteResult> writeCommandTrace({
  required TraceOptions options,
  required FluohEnvironment environment,
  required String command,
  required List<String> arguments,
  required bool ok,
  required int exitCode,
  required Map<String, Object?> result,
  List<Map<String, Object?>> feedbackCandidates = const [],
}) async {
  if (!options.enabled) {
    return TraceWriteResult.skipped;
  }

  final now = DateTime.now();
  final traceId = _traceId(command, now, options: options);
  final directory = _traceDirectory(
    options: options,
    environment: environment,
    traceId: traceId,
    traceScope: _traceScope(result),
  );
  final reference = TraceReference(id: traceId, path: directory);
  try {
    await directory.create(recursive: true);

    final invocation = {
      'createdAt': now.toIso8601String(),
      'command': command,
      'commandLine': _commandLine(command, arguments),
      'ok': ok,
      'exitCode': exitCode,
      'result': result,
      'feedbackCandidates': feedbackCandidates,
    };
    final existing = await _readExistingManifest(reference.manifest);
    final invocations = [
      ..._existingInvocations(existing.manifest),
      invocation,
    ];
    final manifest = {
      'schema': traceOutputSchema,
      'kind': 'fluoh.trace',
      'id': traceId,
      'createdAt':
          _existingString(existing.manifest, 'createdAt') ??
          now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'fluohVersion': packageVersion,
      'command': command,
      'commandLine': _commandLine(command, arguments),
      'ok': ok,
      'exitCode': exitCode,
      'workspace': {
        'workingDirectory': environment.workingDirectory.path,
        'fluohHome': environment.homeDirectory.path,
      },
      'result': result,
      'feedbackCandidates': _allFeedbackCandidates(invocations),
      if (existing.error != null) 'previousManifestError': existing.error,
      'invocations': invocations,
    };
    await reference.manifest.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    );
    return TraceWriteResult(reference: reference);
  } on FileSystemException catch (error) {
    return TraceWriteResult(
      error:
          'Could not write trace manifest ${reference.manifest.path}: '
          '${error.message}',
    );
  }
}

String _traceId(String command, DateTime now, {required TraceOptions options}) {
  final requested = options.directory;
  if (requested != null) {
    final segments = requested.path
        .split(RegExp(r'[/\\]+'))
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final name = segments.isEmpty ? null : segments.last;
    if (name != null && name.trim().isNotEmpty) {
      return name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '-');
    }
  }
  final timestamp =
      '${now.year.toString().padLeft(4, '0')}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}-'
      '${now.hour.toString().padLeft(2, '0')}'
      '${now.minute.toString().padLeft(2, '0')}'
      '${now.second.toString().padLeft(2, '0')}-'
      '${now.microsecond.toString().padLeft(6, '0')}';
  final slug = command.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '-');
  return '$slug-$timestamp';
}

Directory _traceDirectory({
  required TraceOptions options,
  required FluohEnvironment environment,
  required String traceId,
  required String? traceScope,
}) {
  final requested = options.directory;
  if (requested != null) {
    if (requested is Directory) {
      return requested.isAbsolute
          ? requested
          : Directory('${environment.workingDirectory.path}/${requested.path}');
    }
    final path = requested.path;
    final directory = Directory(path);
    return directory.isAbsolute
        ? directory
        : Directory('${environment.workingDirectory.path}/$path');
  }
  final base = '${environment.workingDirectory.path}/.fluoh/traces';
  if (traceScope != null) {
    return Directory('$base/$traceScope/$traceId');
  }
  return Directory('$base/$traceId');
}

String? _traceScope(Map<String, Object?> result) {
  final targets = result['targets'];
  if (targets is! List || targets.length != 1) {
    return null;
  }
  final targetResult = targets.single;
  if (targetResult is! Map) {
    return null;
  }
  final target = targetResult['target'];
  if (target is! Map || target['kind'] != 'package') {
    return null;
  }
  final name = target['name'];
  if (name is! String || name.trim().isEmpty) {
    return null;
  }
  return _pathSlug(name);
}

String _pathSlug(String value) {
  final normalized = value
      .trim()
      .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^[-._]+|[-._]+$'), '');
  return normalized.isEmpty ? 'package' : normalized;
}

String _commandLine(String command, List<String> arguments) {
  final commandParts = command.split(' ');
  return ['fluoh', ...commandParts, ...arguments.map(_shellQuote)].join(' ');
}

Future<_ExistingTraceManifest> _readExistingManifest(File manifest) async {
  if (!await manifest.exists()) {
    return const _ExistingTraceManifest();
  }
  try {
    final decoded = jsonDecode(await manifest.readAsString());
    if (decoded is Map) {
      return _ExistingTraceManifest(
        manifest: Map<String, Object?>.from(decoded),
      );
    }
    return const _ExistingTraceManifest(
      error: 'Existing trace manifest is not a JSON object.',
    );
  } on FormatException catch (error) {
    return _ExistingTraceManifest(
      error: 'Could not parse existing trace manifest: ${error.message}',
    );
  }
}

class _ExistingTraceManifest {
  const _ExistingTraceManifest({this.manifest, this.error});

  final Map<String, Object?>? manifest;
  final String? error;
}

List<Map<String, Object?>> _existingInvocations(
  Map<String, Object?>? manifest,
) {
  final raw = manifest?['invocations'];
  if (raw is List) {
    return [
      for (final item in raw)
        if (item is Map) Map<String, Object?>.from(item),
    ];
  }
  return const [];
}

String? _existingString(Map<String, Object?>? manifest, String key) {
  final value = manifest?[key];
  return value is String && value.trim().isNotEmpty ? value : null;
}

List<Object?> _allFeedbackCandidates(List<Map<String, Object?>> invocations) {
  return [
    for (final invocation in invocations)
      if (invocation['feedbackCandidates'] is List)
        ...(invocation['feedbackCandidates']! as List),
  ];
}

String _shellQuote(String value) {
  if (value.isEmpty) {
    return "''";
  }
  if (!RegExp(r'''[\s'"\\$`]''').hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", r"'\''")}'";
}
