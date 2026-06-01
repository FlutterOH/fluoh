import 'dart:convert';

/// Machine-output schema version shared by all `--json` commands.
const machineOutputSchemaVersion = 1;

/// Receives one JSON object produced by a machine-output command.
typedef MachineOutputWriter = void Function(String message);

/// Builds the standard top-level JSON object for `--json` command output.
///
/// The reserved keys `schemaVersion`, `command`, `ok`, and `exitCode` are owned
/// by this helper so every machine-readable command has the same envelope.
Map<String, Object?> machineOutput({
  required String command,
  required bool ok,
  required int exitCode,
  Map<String, Object?> fields = const {},
}) {
  for (final reserved in const ['schemaVersion', 'command', 'ok', 'exitCode']) {
    if (fields.containsKey(reserved)) {
      throw ArgumentError.value(
        fields[reserved],
        reserved,
        'Machine output fields must not override reserved keys.',
      );
    }
  }
  return {
    'schemaVersion': machineOutputSchemaVersion,
    'command': command,
    'ok': ok,
    'exitCode': exitCode,
    ...fields,
  };
}

/// Writes [machineOutput] to [stdout] as a single JSON line.
void writeMachineOutput(
  MachineOutputWriter stdout, {
  required String command,
  required bool ok,
  required int exitCode,
  Map<String, Object?> fields = const {},
}) {
  stdout(
    jsonEncode(
      machineOutput(
        command: command,
        ok: ok,
        exitCode: exitCode,
        fields: fields,
      ),
    ),
  );
}

/// Builds a standard machine-readable error response.
Map<String, Object?> machineErrorOutput({
  required String command,
  required int exitCode,
  required String type,
  required String message,
}) {
  return machineOutput(
    command: command,
    ok: false,
    exitCode: exitCode,
    fields: {
      'error': {'type': type, 'message': message},
    },
  );
}

/// Writes [machineErrorOutput] to [stdout] as a single JSON line.
void writeMachineErrorOutput(
  MachineOutputWriter stdout, {
  required String command,
  required int exitCode,
  required String type,
  required String message,
}) {
  stdout(
    jsonEncode(
      machineErrorOutput(
        command: command,
        exitCode: exitCode,
        type: type,
        message: message,
      ),
    ),
  );
}
