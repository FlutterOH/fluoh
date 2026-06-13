part of 'workflow_commands.dart';

void _addPackageSelectionOptions(ArgParser parser) {
  parser.addOption(
    'package',
    valueHelp: 'name',
    help: 'Package to use. Defaults to the current package branch.',
  );
}

void _addTraceOptions(ArgParser parser) {
  parser
    ..addFlag(
      'trace',
      negatable: false,
      help:
          'Write a local AI diagnostic trace under .fluoh/traces, grouped by package when possible.',
    )
    ..addOption(
      'trace-dir',
      valueHelp: 'path',
      help: 'Write the AI diagnostic trace to a specific directory.',
    );
}

TraceOptions _traceOptionsFrom(ArgResults results) {
  final traceDir = _trimmedOption(results, 'trace-dir');
  return TraceOptions(
    enabled: results.flag('trace') || traceDir != null,
    directory: traceDir == null ? null : Directory(traceDir),
  );
}
