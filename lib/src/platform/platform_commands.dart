import '../cli/argument_validation.dart';
import '../cli/fluoh_command_runner.dart';
import '../cli/machine_output.dart';
import '../cli/terminal_output.dart';
import '../context/fluoh_environment.dart';
import 'platform_environment.dart';

class DevicesCommand extends FluohCommand<int> {
  DevicesCommand({
    required this.environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _output = output ?? TerminalOutput(stdout: stdout) {
    argParser
      ..addOption(
        'platform',
        allowed: const ['all', 'ohos', 'android', 'ios'],
        defaultsTo: 'all',
        help: 'Platforms to list.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print a detailed machine-readable target report.',
      );
  }

  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final TerminalOutput _output;

  @override
  String get name => 'devices';

  @override
  String get description => 'List connected FlutterOH targets.';

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
        command: name,
        ok: ok,
        exitCode: exitCode,
        fields: {
          'platforms': reports.map((report) => report.toJson()).toList(),
        },
      );
    } else {
      _printTargetReports(
        title: 'Connected devices',
        emptyLabel: 'No devices found',
        reports: reports,
        output: _output,
        lineLength: argParser.usageLineLength ?? fluohUsageLineLength(),
      );
    }
    return exitCode;
  }
}

class EmulatorsCommand extends FluohCommand<int> {
  EmulatorsCommand({
    required this.environment,
    required OutputWriter stdout,
    TerminalOutput? output,
  }) : _stdout = stdout,
       _output = output ?? TerminalOutput(stdout: stdout) {
    argParser
      ..addOption(
        'platform',
        allowed: const ['all', 'ohos', 'android', 'ios'],
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

  final FluohEnvironment environment;
  final OutputWriter _stdout;
  final TerminalOutput _output;

  @override
  String get name => 'emulators';

  @override
  String get description => 'List and launch local FlutterOH emulators.';

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
          command: name,
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
        command: name,
        ok: ok,
        exitCode: exitCode,
        fields: {
          'platforms': reports.map((report) => report.toJson()).toList(),
        },
      );
    } else {
      _printTargetReports(
        title: 'Available emulators',
        emptyLabel: 'No emulators found',
        reports: reports,
        output: _output,
        lineLength: argParser.usageLineLength ?? fluohUsageLineLength(),
      );
    }
    return exitCode;
  }

  String? _trimmedOption(String name) {
    final value = argResults!.option(name)?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}

List<FluohPlatform> platformsFromCliOption(String? value) {
  return switch (value) {
    'all' || null => const [
      FluohPlatform.ohos,
      FluohPlatform.android,
      FluohPlatform.ios,
    ],
    'ohos' => const [FluohPlatform.ohos],
    'android' => const [FluohPlatform.android],
    'ios' => const [FluohPlatform.ios],
    _ => throw ArgumentError.value(value, 'value', 'Unsupported platform.'),
  };
}

void _printTargetReports({
  required String title,
  required String emptyLabel,
  required List<PlatformTargetReport> reports,
  required TerminalOutput output,
  required int lineLength,
}) {
  output.section(title);
  for (final report in reports) {
    output.blank();
    output.write(_platformTitle(report.platform));
    if (!report.ok) {
      output.warning(report.message ?? 'Could not list targets');
      continue;
    }
    if (report.targets.isEmpty) {
      output.skipped(emptyLabel);
      continue;
    }
    for (final target in report.targets) {
      _writeWrappedTarget(
        output,
        _targetLine(target, reportKind: report.kind),
        lineLength: lineLength,
      );
    }
  }
}

String _targetLine(PlatformTarget target, {required String reportKind}) {
  final details = [
    if (target.kind != reportKind) target.kind,
    if (_showTargetState(target)) target.state!,
    if (target.details['details'] != null) target.details['details']!,
  ].map((item) => item.toString()).where((item) => item.isNotEmpty);
  return [
    target.name,
    if (target.id != target.name) target.id,
    if (details.isNotEmpty) details.join(' '),
  ].join('    ');
}

bool _showTargetState(PlatformTarget target) {
  if (target.state == null || target.state!.trim().isEmpty) {
    return false;
  }
  return !(target.platform == FluohPlatform.ios && target.kind == 'emulator');
}

void _writeWrappedTarget(
  TerminalOutput output,
  String line, {
  required int lineLength,
}) {
  const firstIndent = 2;
  const continuationIndent = 4;
  final firstWidth = (lineLength - firstIndent).clamp(20, lineLength).toInt();
  final continuationWidth = (lineLength - continuationIndent)
      .clamp(20, lineLength)
      .toInt();
  final lines = wrapTerminalText(line, width: firstWidth);
  if (lines.isEmpty) {
    output.indented('');
    return;
  }
  output.indented(lines.first, spaces: firstIndent);
  for (final line in lines.skip(1)) {
    final wrapped = wrapTerminalText(line, width: continuationWidth);
    for (final continuation in wrapped) {
      output.indented(continuation, spaces: continuationIndent);
    }
  }
}

String _platformTitle(FluohPlatform platform) {
  return switch (platform) {
    FluohPlatform.ohos => 'OHOS',
    FluohPlatform.android => 'Android',
    FluohPlatform.ios => 'iOS',
  };
}
