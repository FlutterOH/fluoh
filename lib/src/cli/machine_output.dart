import 'dart:convert';

const machineOutputSchemaVersion = 1;

typedef MachineOutputWriter = void Function(String message);

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
