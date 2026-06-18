import '../cli/argument_validation.dart';
import '../cli/fluoh_command_runner.dart';
import '../cli/machine_output.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import 'platform_environment.dart';

/// Lists connected targets for supported platforms.
class DevicesCommand extends FluohCommand<int> {
  /// Creates the devices command.
  DevicesCommand({
    required this.environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _output = output ?? TerminalOutput(stdout: stdout) {
    argParser
      ..addOption(
        'platform',
        valueHelp: 'platform',
        allowed: fluohPlatformOptionValues,
        defaultsTo: 'all',
        help: 'Platforms to list.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print a detailed machine-readable target report.',
      );
  }

  /// Runtime environment used for target discovery.
  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final TerminalOutput _output;

  @override
  String get name => 'devices';

  @override
  String get description => 'List connected Flutter targets.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final platforms = platformsFromCliOption(argResults!.option('platform'));
    final reports = await listPlatformDeviceReports(
      environment: environment,
      platforms: platforms,
    );
    final json = argResults!.flag('json');
    final ok = reports.every((report) => report.ok);
    final exitCode = ok ? 0 : 1;
    if (json) {
      writeMachineOutput(
        _stdout,
        command: 'devices',
        ok: ok,
        exitCode: exitCode,
        fields: {
          'platforms': reports.map((report) => report.toJson()).toList(),
        },
      );
    } else {
      _printTargetReports(
        kind: _TargetReportKind.devices,
        reports: reports,
        output: _output,
      );
    }
    return exitCode;
  }
}

/// Lists or launches local emulators and simulators.
class EmulatorsCommand extends FluohCommand<int> {
  /// Creates the emulators command.
  EmulatorsCommand({
    required this.environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _output = output ?? TerminalOutput(stdout: stdout) {
    argParser
      ..addOption(
        'platform',
        valueHelp: 'platform',
        allowed: fluohPlatformOptionValues,
        defaultsTo: 'all',
        help: 'Platforms to list or launch.',
      )
      ..addOption(
        'launch',
        valueHelp: 'id-or-name',
        help: 'Launch a local emulator or simulator by id or name.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print a detailed machine-readable target report.',
      );
  }

  /// Runtime environment used for emulator discovery and launch.
  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final TerminalOutput _output;

  @override
  String get name => 'emulators';

  @override
  String get description => 'List and launch local emulators and simulators.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final platforms = platformsFromCliOption(argResults!.option('platform'));
    final launch = _trimmedOption('launch');
    final json = argResults!.flag('json');
    if (launch != null) {
      if (platforms.length != 1) {
        usageException('Use --platform with one platform when launching.');
      }
      final result = await startPlatformEmulator(
        environment: environment,
        platform: platforms.single,
        emulator: launch,
      );
      if (json) {
        writeMachineOutput(
          _stdout,
          command: 'emulators',
          ok: result.ok,
          exitCode: result.ok ? 0 : 1,
          fields: {'launch': result.toJson()},
        );
      } else if (result.ok) {
        _output.success(result.message);
        if (result.command.isNotEmpty) {
          _output.detail(result.command.join(' '));
        }
      } else {
        _output.failure(result.message);
      }
      return result.ok ? 0 : 1;
    }

    final reports = await listPlatformEmulatorReports(
      environment: environment,
      platforms: platforms,
    );
    final ok = reports.every((report) => report.ok);
    final exitCode = ok ? 0 : 1;
    if (json) {
      writeMachineOutput(
        _stdout,
        command: 'emulators',
        ok: ok,
        exitCode: exitCode,
        fields: {
          'platforms': reports.map((report) => report.toJson()).toList(),
        },
      );
    } else {
      _printTargetReports(
        kind: _TargetReportKind.emulators,
        reports: reports,
        output: _output,
      );
    }
    return exitCode;
  }

  String? _trimmedOption(String name) {
    final value = argResults!.option(name)?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}

/// Parses a `--platform` option into the platform list to inspect.
List<FluohPlatform> platformsFromCliOption(String? value) {
  return fluohPlatformsFromCliOption(value);
}

enum _TargetReportKind { devices, emulators }

void _printTargetReports({
  required _TargetReportKind kind,
  required List<PlatformTargetReport> reports,
  required TerminalOutput output,
}) {
  final targets = <PlatformTarget>[];
  final warnings = <String>[];
  for (final report in reports) {
    if (!report.ok) {
      warnings.add(
        '${_platformTitle(report.platform)} ${kind.unavailableLabel}: '
        '${report.message ?? 'could not list targets'}',
      );
      continue;
    }
    targets.addAll(report.targets);
  }

  targets.sort((left, right) {
    final platform = left.platform.cliName.compareTo(right.platform.cliName);
    if (platform != 0) {
      return platform;
    }
    final name = left.name.compareTo(right.name);
    return name == 0 ? left.id.compareTo(right.id) : name;
  });

  if (targets.isEmpty) {
    output.write(kind.emptyMessage);
  } else {
    switch (kind) {
      case _TargetReportKind.devices:
        _printDeviceTargets(targets, output);
      case _TargetReportKind.emulators:
        _printEmulatorTargets(targets, output);
    }
  }

  if (warnings.isNotEmpty) {
    if (targets.isNotEmpty) {
      output.blank();
    }
    for (final warning in warnings) {
      output.warning(warning);
    }
  }
}

void _printDeviceTargets(List<PlatformTarget> targets, TerminalOutput output) {
  final wiredTargets = [
    for (final target in targets)
      if (platformTargetConnection(target) != 'wireless') target,
  ];
  final wirelessTargets = [
    for (final target in targets)
      if (platformTargetConnection(target) == 'wireless') target,
  ];

  if (wiredTargets.isNotEmpty) {
    output.write(_TargetReportKind.devices.heading(wiredTargets.length));
    for (final row in _formatDeviceRows(wiredTargets)) {
      _writeTargetRow(output, '  $row');
    }
  }

  if (wirelessTargets.isNotEmpty) {
    if (wiredTargets.isNotEmpty) {
      output.blank();
    }
    output.write(_wirelessHeading(wirelessTargets.length));
    for (final row in _formatDeviceRows(wirelessTargets)) {
      _writeTargetRow(output, '  $row');
    }
  }
}

void _printEmulatorTargets(
  List<PlatformTarget> targets,
  TerminalOutput output,
) {
  output.write(_TargetReportKind.emulators.heading(targets.length));
  output.blank();
  final widths = _emulatorColumnWidths(targets);
  _writeTargetRow(output, _formatTargetRow(_emulatorHeaderRow(), widths));
  output.blank();
  for (final row in _formatEmulatorRows(targets, widths)) {
    _writeTargetRow(output, row);
  }
  output.blank();
  output.write(
    "To run an emulator, run 'fluoh emulators --launch <emulator id>'.",
  );
}

String _wirelessHeading(int count) {
  return 'Found $count wirelessly connected device${count == 1 ? '' : 's'}:';
}

extension on _TargetReportKind {
  String heading(int count) {
    return switch (this) {
      _TargetReportKind.devices =>
        'Found $count connected device${count == 1 ? '' : 's'}:',
      _TargetReportKind.emulators =>
        '$count available emulator${count == 1 ? '' : 's'}:',
    };
  }

  String get emptyMessage {
    return switch (this) {
      _TargetReportKind.devices => 'No connected devices detected.',
      _TargetReportKind.emulators => 'No emulators available.',
    };
  }

  String get unavailableLabel {
    return switch (this) {
      _TargetReportKind.devices => 'devices unavailable',
      _TargetReportKind.emulators => 'emulators unavailable',
    };
  }
}

List<String> _formatDeviceRows(List<PlatformTarget> targets) {
  final rows = [
    for (final target in targets)
      _TargetDisplayRow(
        first: platformTargetDisplayName(target),
        second: target.id,
        third: platformTargetDisplayPlatform(target),
        fourth: platformTargetSummary(target),
      ),
  ];
  return _formatTargetRows(rows, _columnWidths(rows));
}

List<String> _formatEmulatorRows(
  List<PlatformTarget> targets,
  _TargetColumnWidths widths,
) {
  return [
    for (final target in targets)
      _formatTargetRow(
        _TargetDisplayRow(
          first: target.id,
          second: platformTargetEmulatorName(target),
          third: platformTargetManufacturer(target) ?? '',
          fourth: target.platform.cliName,
        ),
        widths,
      ),
  ];
}

_TargetDisplayRow _emulatorHeaderRow() {
  return const _TargetDisplayRow(
    first: 'Id',
    second: 'Name',
    third: 'Manufacturer',
    fourth: 'Platform',
  );
}

_TargetColumnWidths _emulatorColumnWidths(List<PlatformTarget> targets) {
  return _columnWidths([
    _emulatorHeaderRow(),
    for (final target in targets)
      _TargetDisplayRow(
        first: target.id,
        second: platformTargetEmulatorName(target),
        third: platformTargetManufacturer(target) ?? '',
        fourth: target.platform.cliName,
      ),
  ]);
}

List<String> _formatTargetRows(
  List<_TargetDisplayRow> rows,
  _TargetColumnWidths widths,
) {
  return [for (final row in rows) _formatTargetRow(row, widths)];
}

String _formatTargetRow(_TargetDisplayRow row, _TargetColumnWidths widths) {
  return [
    row.first.padRight(widths.first),
    row.second.padRight(widths.second),
    row.third.padRight(widths.third),
    row.fourth,
  ].where((part) => part.trim().isNotEmpty).join(' • ');
}

_TargetColumnWidths _columnWidths(List<_TargetDisplayRow> rows) {
  if (rows.isEmpty) {
    return const _TargetColumnWidths(first: 0, second: 0, third: 0);
  }
  return _TargetColumnWidths(
    first: rows.map((row) => row.first.length).reduce(_max),
    second: rows.map((row) => row.second.length).reduce(_max),
    third: rows.map((row) => row.third.length).reduce(_max),
  );
}

void _writeTargetRow(TerminalOutput output, String line) {
  output.write(line);
}

int _max(int left, int right) {
  return left > right ? left : right;
}

String _platformTitle(FluohPlatform platform) {
  return switch (platform) {
    FluohPlatform.ohos => 'OHOS',
    FluohPlatform.android => 'Android',
    FluohPlatform.ios => 'iOS',
    FluohPlatform.macos => 'macOS',
    FluohPlatform.linux => 'Linux',
    FluohPlatform.web => 'Web',
    FluohPlatform.windows => 'Windows',
  };
}

class _TargetDisplayRow {
  const _TargetDisplayRow({
    required this.first,
    required this.second,
    required this.third,
    required this.fourth,
  });

  final String first;
  final String second;
  final String third;
  final String fourth;
}

class _TargetColumnWidths {
  const _TargetColumnWidths({
    required this.first,
    required this.second,
    required this.third,
  });

  final int first;
  final int second;
  final int third;
}
