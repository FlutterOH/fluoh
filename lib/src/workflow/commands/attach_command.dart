part of 'workflow_commands.dart';

/// Attaches Flutter debug tooling to a running platform session.
class AttachCommand extends FluohCommand<int> {
  /// Creates the attach command.
  AttachCommand({
    required this.environment,
    required OutputWriter stdout,
    required OutputWriter stderr,
    required bool inheritStdio,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _stderr = stderr,
       _inheritStdio = inheritStdio,
       _output = output ?? TerminalOutput(stdout: stdout, stderr: stderr) {
    argParser
      ..addOption(
        'session-file',
        valueHelp: 'path',
        help: 'Read target and VM Service details from a flutterRunSession.',
      )
      ..addOption(
        'vm-service-uri',
        valueHelp: 'uri',
        help: 'Attach directly to a Flutter VM Service or debug service URI.',
      )
      ..addOption(
        'device-id',
        abbr: 'd',
        valueHelp: 'id',
        help: 'Attach to a running Flutter app on this device id.',
      )
      ..addOption(
        'wait',
        valueHelp: 'seconds',
        defaultsTo: '0',
        help: 'Seconds to wait for the session file to expose attach details.',
      )
      ..addFlag(
        'require-vm-service',
        negatable: false,
        help:
            'Fail instead of falling back to the target id when no VM Service URI is available.',
      )
      ..addFlag(
        'dry-run',
        abbr: 'n',
        negatable: false,
        help: 'Resolve the attach command without running Flutter.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the attach result as JSON.',
      );
  }

  /// Runtime environment for the selected project or package repository.
  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final OutputWriter _stderr;
  final TerminalOutput _output;
  final bool _inheritStdio;

  @override
  String get name => 'attach';

  @override
  String get description =>
      'Attach Flutter debug tooling to a run session or device.';

  @override
  String get invocation =>
      '${runner?.executableName ?? 'fluoh'} attach <platform> [arguments]';

  @override
  Future<int> run() async {
    final platform = _platformArgument(
      argResults!,
      usageException,
      allowed: _attachPlatforms,
      label: 'attach',
    );
    final json = argResults!.flag('json');
    final output = _outputFor(json, _output);
    final sessionFilePath = _trimmedOption(argResults!, 'session-file');
    final directVmServiceUri = _trimmedOption(argResults!, 'vm-service-uri');
    final directDeviceId = _trimmedOption(argResults!, 'device-id');
    final wait = _durationOption('wait');
    final requireVmService = argResults!.flag('require-vm-service');
    final dryRun = argResults!.flag('dry-run');

    if (sessionFilePath == null &&
        directVmServiceUri == null &&
        directDeviceId == null) {
      usageException(
        'Use --session-file, --vm-service-uri, or --device-id to select an attach target.',
      );
    }
    if (requireVmService &&
        sessionFilePath == null &&
        directVmServiceUri == null) {
      usageException(
        'Use --require-vm-service with --session-file or --vm-service-uri.',
      );
    }

    final sessionFile = sessionFilePath == null
        ? null
        : _resolveOutputFile(environment.workingDirectory, sessionFilePath);
    final sessionResult = sessionFile == null
        ? const _AttachSessionResult()
        : await _readAttachSession(
            sessionFile,
            platform: platform,
            wait: wait,
            requireVmService: requireVmService,
          );
    if (!sessionResult.ok) {
      return _finishAttachFailure(
        json: json,
        stdout: _stdout,
        output: output,
        platform: platform,
        code: sessionResult.code!,
        message: sessionResult.message!,
        details: {
          'sessionFile': sessionFile!.path,
          if (sessionResult.details.isNotEmpty) ...sessionResult.details,
        },
      );
    }

    final session = sessionResult.session;
    final targetId = directDeviceId ?? session?.targetId;
    final preferDetachedTarget =
        directVmServiceUri == null &&
        directDeviceId == null &&
        !requireVmService &&
        session?.detached == true &&
        targetId != null;
    final vmServiceUri = preferDetachedTarget
        ? null
        : directVmServiceUri ?? session?.vmServiceUri;
    if (requireVmService && vmServiceUri == null) {
      return _finishAttachFailure(
        json: json,
        stdout: _stdout,
        output: output,
        platform: platform,
        code: '$platform.vm_service_missing',
        message: 'No VM Service URI is available for attach.',
        details: {
          if (sessionFile != null) 'sessionFile': sessionFile.path,
          if (session != null) 'session': session.toJson(),
        },
      );
    }
    if (vmServiceUri == null && targetId == null) {
      return _finishAttachFailure(
        json: json,
        stdout: _stdout,
        output: output,
        platform: platform,
        code: '$platform.attach_target_missing',
        message: 'No VM Service URI or target id is available for attach.',
        details: {
          if (sessionFile != null) 'sessionFile': sessionFile.path,
          if (session != null) 'session': session.toJson(),
        },
      );
    }

    final arguments = [
      'attach',
      if (vmServiceUri != null) ...[
        '--debug-uri',
        vmServiceUri,
      ] else ...[
        '-d',
        targetId!,
      ],
    ];
    final command = 'flutter ${arguments.map(_workflowShellQuote).join(' ')}';
    final details = <String, Object?>{
      'platform': platform,
      'flutterCommand': command,
      'arguments': arguments,
      'source': sessionFile == null ? 'arguments' : 'sessionFile',
      if (preferDetachedTarget) 'attachTargetSource': 'detachedSessionTargetId',
      if (sessionFile != null) 'sessionFile': sessionFile.path,
      if (session != null) 'session': session.toJson(),
    };
    if (vmServiceUri != null) {
      details['vmServiceUri'] = vmServiceUri;
    }
    if (targetId != null) {
      details['targetId'] = targetId;
    }

    if (dryRun) {
      if (json) {
        writeMachineOutput(
          _stdout,
          command: 'attach',
          ok: true,
          exitCode: 0,
          fields: details,
        );
      } else {
        output.success('Attach command resolved');
        output.detail(command);
      }
      return 0;
    }

    output.step('Running $command in ${environment.workingDirectory.path}');
    final result = await runSelectedFlutterResult(
      environment: environment,
      arguments: arguments,
      workingDirectory: environment.workingDirectory,
      stdout: json ? (_) {} : _stdout,
      stderr: json ? (_) {} : _stderr,
      output: output,
      inheritStdio: _inheritStdio && !json,
      usage: usage,
    );
    final resultDetails = {
      ...details,
      'flutterExitCode': result.exitCode,
      ..._attachOutputDetails(result),
    };
    if (json) {
      writeMachineOutput(
        _stdout,
        command: 'attach',
        ok: result.exitCode == 0,
        exitCode: result.exitCode,
        fields: resultDetails,
      );
    } else if (result.exitCode == 0) {
      output.success('Attach completed');
    } else {
      output.failure('Attach failed');
    }
    return result.exitCode;
  }

  Duration _durationOption(String name) {
    final seconds = int.tryParse(argResults!.option(name) ?? '');
    if (seconds == null || seconds < 0) {
      usageException('Use a non-negative integer for --$name.');
    }
    return Duration(seconds: seconds);
  }
}

Future<_AttachSessionResult> _readAttachSession(
  File file, {
  required String platform,
  required Duration wait,
  required bool requireVmService,
}) async {
  final deadline = DateTime.now().add(wait);
  Object? lastError;
  while (true) {
    if (await file.exists()) {
      try {
        final session = _AttachSession.fromJson(
          jsonObject(jsonDecode(await file.readAsString()), file.path),
        );
        if (session.kind != 'flutterRunSession') {
          return _AttachSessionResult.failure(
            code: '$platform.session_invalid',
            message: 'Session file is not a flutterRunSession.',
            details: {'kind': session.kind},
          );
        }
        if (session.platform != platform) {
          return _AttachSessionResult.failure(
            code: '$platform.session_platform_mismatch',
            message:
                'Session platform ${session.platform} does not match $platform.',
            details: {'sessionPlatform': session.platform},
          );
        }
        final hasAttachTarget =
            session.vmServiceUri != null ||
            (!requireVmService && session.targetId != null);
        if (hasAttachTarget || !DateTime.now().isBefore(deadline)) {
          return _AttachSessionResult(session: session);
        }
      } on Object catch (error) {
        lastError = error;
        if (!DateTime.now().isBefore(deadline)) {
          return _AttachSessionResult.failure(
            code: '$platform.session_invalid',
            message: 'Could not read attach session.',
            details: {'error': error.toString()},
          );
        }
      }
    } else if (!DateTime.now().isBefore(deadline)) {
      return _AttachSessionResult.failure(
        code: '$platform.session_missing',
        message: 'Session file was not found.',
        details: {if (lastError != null) 'error': lastError.toString()},
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

int _finishAttachFailure({
  required bool json,
  required OutputWriter stdout,
  required TerminalOutput output,
  required String platform,
  required String code,
  required String message,
  required Map<String, Object?> details,
}) {
  if (json) {
    writeMachineOutput(
      stdout,
      command: 'attach',
      ok: false,
      exitCode: 1,
      fields: {
        'platform': platform,
        'diagnostic': {
          'code': code,
          'message': message,
          if (details.isNotEmpty) 'details': details,
        },
      },
    );
  } else {
    output.failure(message);
    output.detail(code);
  }
  return 1;
}

Map<String, Object?> _attachOutputDetails(SelectedToolResult result) {
  return {
    if (result.stdout.trim().isNotEmpty) 'stdout': result.stdout.trim(),
    if (result.stderr.trim().isNotEmpty) 'stderr': result.stderr.trim(),
  };
}

class _AttachSessionResult {
  const _AttachSessionResult({
    this.session,
    this.code,
    this.message,
    this.details = const {},
  });

  factory _AttachSessionResult.failure({
    required String code,
    required String message,
    Map<String, Object?> details = const {},
  }) {
    return _AttachSessionResult(code: code, message: message, details: details);
  }

  final _AttachSession? session;
  final String? code;
  final String? message;
  final Map<String, Object?> details;

  bool get ok => code == null;
}

class _AttachSession {
  const _AttachSession({
    required this.kind,
    required this.platform,
    this.status,
    this.command,
    this.processId,
    this.targetId,
    this.vmServiceUri,
    this.outputLog,
    this.launchDetected,
    this.detached,
  });

  factory _AttachSession.fromJson(Map<String, Object?> json) {
    return _AttachSession(
      kind: optionalString(json, 'kind'),
      platform: optionalString(json, 'platform'),
      status: optionalString(json, 'status'),
      command: optionalString(json, 'command'),
      processId: json['processId'],
      targetId: optionalString(json, 'targetId'),
      vmServiceUri: optionalString(json, 'vmServiceUri'),
      outputLog: optionalString(json, 'outputLog'),
      launchDetected: json['launchDetected'] == true,
      detached: json['detached'] == true,
    );
  }

  final String? kind;
  final String? platform;
  final String? status;
  final String? command;
  final Object? processId;
  final String? targetId;
  final String? vmServiceUri;
  final String? outputLog;
  final bool? launchDetected;
  final bool? detached;

  Map<String, Object?> toJson() {
    return {
      if (kind != null) 'kind': kind,
      if (platform != null) 'platform': platform,
      if (status != null) 'status': status,
      if (command != null) 'command': command,
      if (processId != null) 'processId': processId,
      if (targetId != null) 'targetId': targetId,
      if (vmServiceUri != null) 'vmServiceUri': vmServiceUri,
      if (outputLog != null) 'outputLog': outputLog,
      if (launchDetected != null) 'launchDetected': launchDetected,
      if (detached != null) 'detached': detached,
    };
  }
}
