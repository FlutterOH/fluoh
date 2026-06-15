import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import 'ohos_toolchain.dart';

/// Policy for handling OHOS system permission dialogs during integration tests.
enum OhosSystemPermissionDialogPolicy {
  /// Do not operate system permission dialogs.
  disabled('disabled'),

  /// Click the system allow button when a permission dialog appears.
  allow('allow');

  const OhosSystemPermissionDialogPolicy(this.cliValue);

  /// Command-line value.
  final String cliValue;
}

/// Supported command-line values for OHOS permission dialog handling.
const ohosSystemPermissionDialogPolicyValues = ['disabled', 'allow'];

/// Returns the dialog policy for a CLI value, defaulting only when omitted.
OhosSystemPermissionDialogPolicy parseOhosSystemPermissionDialogPolicy(
  String? value,
) {
  final normalized =
      (value ?? OhosSystemPermissionDialogPolicy.disabled.cliValue)
          .trim()
          .toLowerCase();
  for (final policy in OhosSystemPermissionDialogPolicy.values) {
    if (policy.cliValue == normalized) {
      return policy;
    }
  }
  throw ArgumentError.value(
    value,
    'value',
    'Expected one of: ${ohosSystemPermissionDialogPolicyValues.join(', ')}.',
  );
}

/// Parsed OHOS permission dialog bounds.
class OhosUiBounds {
  /// Creates parsed UI bounds.
  const OhosUiBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Left edge.
  final int left;

  /// Top edge.
  final int top;

  /// Right edge.
  final int right;

  /// Bottom edge.
  final int bottom;

  /// Horizontal center.
  int get centerX => (left + right) ~/ 2;

  /// Vertical center.
  int get centerY => (top + bottom) ~/ 2;

  /// JSON representation.
  Map<String, Object?> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
    'centerX': centerX,
    'centerY': centerY,
  };
}

/// Parsed OHOS system permission dialog.
class OhosPermissionDialog {
  /// Creates parsed dialog data.
  const OhosPermissionDialog({
    required this.title,
    required this.allowBounds,
    this.reason,
  });

  /// Dialog title text.
  final String title;

  /// Dialog reason text when available.
  final String? reason;

  /// Allow button bounds.
  final OhosUiBounds allowBounds;

  /// JSON representation.
  Map<String, Object?> toJson() => {
    'title': title,
    if (reason != null && reason!.isNotEmpty) 'reason': reason,
    'allowButton': allowBounds.toJson(),
  };
}

/// Result from a system permission dialog watcher run.
class OhosSystemPermissionDialogSummary {
  /// Creates a watcher summary.
  const OhosSystemPermissionDialogSummary({
    required this.policy,
    required this.pollCount,
    required this.handledCount,
    required this.dialogs,
    required this.errors,
  });

  /// Dialog handling policy used by the watcher.
  final OhosSystemPermissionDialogPolicy policy;

  /// Number of UI dump polls attempted.
  final int pollCount;

  /// Number of permission dialogs clicked.
  final int handledCount;

  /// Permission dialogs observed and handled.
  final List<OhosPermissionDialog> dialogs;

  /// Best-effort watcher errors.
  final List<String> errors;

  /// Whether the summary should be emitted into workflow details.
  bool get hasEvidence => handledCount > 0 || errors.isNotEmpty;

  /// JSON representation.
  Map<String, Object?> toJson() => {
    'policy': policy.cliValue,
    'pollCount': pollCount,
    'handledCount': handledCount,
    if (dialogs.isNotEmpty)
      'dialogs': dialogs.map((dialog) => dialog.toJson()).toList(),
    if (errors.isNotEmpty) 'errors': errors,
  };
}

/// Best-effort OHOS permission dialog watcher.
class OhosSystemPermissionDialogWatcher {
  OhosSystemPermissionDialogWatcher._({
    required OhosToolchain toolchain,
    required String targetId,
    required OhosSystemPermissionDialogPolicy policy,
    required Duration pollInterval,
    required Duration commandTimeout,
    required TerminalOutput output,
  }) : _toolchain = toolchain,
       _targetId = targetId,
       _policy = policy,
       _pollInterval = pollInterval,
       _commandTimeout = commandTimeout,
       _output = output;

  final OhosToolchain _toolchain;
  final String _targetId;
  final OhosSystemPermissionDialogPolicy _policy;
  final Duration _pollInterval;
  final Duration _commandTimeout;
  final TerminalOutput _output;
  final _stop = Completer<void>();
  final _dialogs = <OhosPermissionDialog>[];
  final _errors = <String>[];
  Future<void>? _loop;
  int _pollCount = 0;
  int _handledCount = 0;

  /// Starts a watcher when the local OHOS toolchain is available.
  static Future<OhosSystemPermissionDialogWatcher?> start({
    required FluohEnvironment environment,
    required String targetId,
    required OhosSystemPermissionDialogPolicy policy,
    required TerminalOutput output,
    Duration pollInterval = const Duration(milliseconds: 750),
    Duration commandTimeout = const Duration(seconds: 3),
  }) async {
    if (policy == OhosSystemPermissionDialogPolicy.disabled) {
      return null;
    }
    try {
      final toolchain = await locateOhosToolchain(
        environment: environment.processEnvironment,
      );
      final watcher = OhosSystemPermissionDialogWatcher._(
        toolchain: toolchain,
        targetId: targetId,
        policy: policy,
        pollInterval: pollInterval,
        commandTimeout: commandTimeout,
        output: output,
      );
      watcher._loop = watcher._run();
      return watcher;
    } on Object {
      return null;
    }
  }

  /// Stops the watcher and returns collected evidence.
  Future<OhosSystemPermissionDialogSummary> stop() async {
    if (!_stop.isCompleted) {
      _stop.complete();
    }
    try {
      await _loop?.timeout(const Duration(seconds: 5));
    } on Object {
      _errors.add('Timed out while stopping OHOS permission dialog watcher.');
    }
    return OhosSystemPermissionDialogSummary(
      policy: _policy,
      pollCount: _pollCount,
      handledCount: _handledCount,
      dialogs: List.unmodifiable(_dialogs),
      errors: List.unmodifiable(_errors),
    );
  }

  Future<void> _run() async {
    while (!_stop.isCompleted) {
      await _pollOnce();
      if (_stop.isCompleted) {
        break;
      }
      await Future.any([Future<void>.delayed(_pollInterval), _stop.future]);
    }
  }

  Future<void> _pollOnce() async {
    _pollCount += 1;
    try {
      final dump = await _runHdc([
        '-t',
        _targetId,
        'shell',
        'uitest',
        'dumpLayout',
      ]);
      if (dump.exitCode != 0 || _containsHdcBusyFailure(dump.output)) {
        _rememberError(dump.output);
        return;
      }
      final remotePath = RegExp(
        r'DumpLayout saved to:\s*(\S+)',
      ).firstMatch(dump.output)?.group(1);
      if (remotePath == null || remotePath.isEmpty) {
        return;
      }
      final localFile = io.File(
        '${io.Directory.systemTemp.path}/fluoh-ohos-layout-$_targetId-$_pollCount.json'
            .replaceAll(':', '_'),
      );
      final recv = await _runHdc([
        '-t',
        _targetId,
        'file',
        'recv',
        remotePath,
        localFile.path,
      ]);
      if (recv.exitCode != 0 || !await localFile.exists()) {
        _rememberError(recv.output);
        return;
      }
      final layoutJson = await localFile.readAsString();
      await localFile.delete();
      final dialog = detectOhosPermissionDialog(layoutJson);
      if (dialog == null) {
        return;
      }
      final click = await _runHdc([
        '-t',
        _targetId,
        'shell',
        'uitest',
        'uiInput',
        'click',
        '${dialog.allowBounds.centerX}',
        '${dialog.allowBounds.centerY}',
      ]);
      if (click.exitCode != 0 || _containsHdcBusyFailure(click.output)) {
        _rememberError(click.output);
        return;
      }
      _handledCount += 1;
      _dialogs.add(dialog);
      _output.detail('Handled OHOS permission dialog: ${dialog.title}');
    } on Object catch (error) {
      _rememberError(error.toString());
    }
  }

  Future<_HdcRunResult> _runHdc(List<String> arguments) async {
    io.Process? process;
    try {
      process = await io.Process.start(_toolchain.hdc.path, arguments);
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(_commandTimeout);
      return _HdcRunResult(
        exitCode: exitCode,
        stdout: await stdout,
        stderr: await stderr,
      );
    } on TimeoutException {
      process?.kill();
      return const _HdcRunResult(
        exitCode: 124,
        stderr: 'hdc command timed out',
      );
    }
  }

  void _rememberError(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final normalized = trimmed.length <= 300
        ? trimmed
        : '${trimmed.substring(0, 300)}...';
    if (!_errors.contains(normalized) && _errors.length < 8) {
      _errors.add(normalized);
    }
  }
}

class _HdcRunResult {
  const _HdcRunResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  String get output => [
    if (stdout.trim().isNotEmpty) stdout.trim(),
    if (stderr.trim().isNotEmpty) stderr.trim(),
  ].join('\n');
}

bool _containsHdcBusyFailure(String output) {
  return output.contains("Mutlti commands can't be used in combination") ||
      output.contains("Multi commands can't be used in combination");
}

/// Parses an OHOS permission dialog from a `uitest dumpLayout` JSON payload.
OhosPermissionDialog? detectOhosPermissionDialog(String layoutJson) {
  final Object? decoded;
  try {
    decoded = jsonDecode(layoutJson);
  } on FormatException {
    return null;
  }

  final allow = _findAttributesById(decoded, 'permission_dialog_allow_button');
  final bounds = _parseBounds(_stringValue(allow, 'bounds'));
  if (bounds == null) {
    return null;
  }
  final title =
      _stringValue(
        _findAttributesById(decoded, 'permission_dialog_title'),
        'text',
      ) ??
      _stringValue(
        _findAttributesById(decoded, 'permission_dialog_body'),
        'text',
      ) ??
      'OHOS system permission dialog';
  final reason = _stringValue(
    _findAttributesById(decoded, 'permission_dialog_reason0'),
    'text',
  );
  return OhosPermissionDialog(
    title: title,
    reason: reason,
    allowBounds: bounds,
  );
}

Map<String, Object?>? _findAttributesById(Object? node, String id) {
  if (node is! Map) {
    return null;
  }
  final attributes = node['attributes'];
  if (attributes is Map) {
    final currentId = attributes['id'];
    final currentKey = attributes['key'];
    if (currentId == id || currentKey == id) {
      return attributes.cast<String, Object?>();
    }
  }
  final children = node['children'];
  if (children is List) {
    for (final child in children) {
      final found = _findAttributesById(child, id);
      if (found != null) {
        return found;
      }
    }
  }
  return null;
}

String? _stringValue(Map<String, Object?>? attributes, String key) {
  final value = attributes?[key];
  return value is String && value.isNotEmpty ? value : null;
}

OhosUiBounds? _parseBounds(String? value) {
  if (value == null) {
    return null;
  }
  final match = RegExp(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$').firstMatch(value);
  if (match == null) {
    return null;
  }
  final left = int.parse(match.group(1)!);
  final top = int.parse(match.group(2)!);
  final right = int.parse(match.group(3)!);
  final bottom = int.parse(match.group(4)!);
  return OhosUiBounds(left: left, top: top, right: right, bottom: bottom);
}
