import '../../cli/argument_validation.dart';
import '../../cli/fluoh_command_runner.dart';
import '../../cli/machine_output.dart';
import '../../cli/terminal_output.dart';
import '../../context/fluoh_environment.dart';
import '../../schema/schema.dart';
import '../../source/source_runtime.dart';

/// Lists FlutterOH packages advertised by configured Sources.
class PackageListCommand extends FluohCommand<int> {
  /// Creates the package list command.
  PackageListCommand({
    required this.environment,
    required this.stdout,
    TerminalOutput? output,
  }) : _output = output ?? TerminalOutput(stdout: stdout) {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print packages from configured sources as JSON.',
    );
  }

  /// Runtime environment containing Source config and cache paths.
  final FluohEnvironment environment;

  /// Writer used for JSON and plain output.
  final OutputWriter stdout;
  final TerminalOutput _output;

  @override
  String get name => 'list';

  @override
  String get description => 'List packages from configured sources.';

  @override
  Future<int> run() async {
    expectNoArguments(argResults!, usageException);
    final index = await SourceRuntime(environment).loadPackageIndex();
    final packages = _listedPackages(index);

    if (argResults!.flag('json')) {
      writeMachineOutput(
        stdout,
        command: 'package list',
        ok: true,
        exitCode: 0,
        fields: {
          'count': packages.length,
          'packages': packages.map((package) => package.toJson()).toList(),
        },
      );
      return 0;
    }

    if (packages.isEmpty) {
      _output.warning('No packages found in configured sources');
      return 0;
    }

    if (_output.style.capabilities.decorated) {
      _output.table(
        columns: const [
          TerminalTableColumn('#', style: TerminalTableCellStyle.muted),
          TerminalTableColumn('Package', style: TerminalTableCellStyle.value),
          TerminalTableColumn('SDK lines', style: TerminalTableCellStyle.muted),
          TerminalTableColumn('Sources', style: TerminalTableCellStyle.muted),
        ],
        rows: [
          for (var index = 0; index < packages.length; index += 1)
            [
              '${index + 1}',
              packages[index].name,
              _displayList(packages[index].sdkLines),
              _displayList(packages[index].sources),
            ],
        ],
      );
      return 0;
    }

    for (var index = 0; index < packages.length; index += 1) {
      stdout(_plainPackageLine(index + 1, packages[index]));
    }
    return 0;
  }
}

List<_ListedPackage> _listedPackages(PackageIndex index) {
  final entries = index.packages.entries.toList(growable: false)
    ..sort((a, b) => a.key.compareTo(b.key));
  return [
    for (final entry in entries)
      _ListedPackage(
        name: entry.key,
        sdkLines: _sdkLines(entry.value),
        sources: _sources(entry.value),
        compatibleReleaseCount: entry.value.implementations.length,
      ),
  ];
}

List<String> _sdkLines(PackageEntry entry) {
  final lines = <String>{
    for (final implementation in entry.implementations) implementation.sdkLine,
    for (final status in entry.compatibility) status.sdkLine,
  }.toList(growable: false)..sort();
  return lines;
}

List<String> _sources(PackageEntry entry) {
  if (entry.sourceNames.isNotEmpty) {
    return entry.sourceNames;
  }
  return <String>{
    for (final implementation in entry.implementations)
      if (implementation.sourceName != null) implementation.sourceName!,
  }.toList(growable: false)..sort();
}

String _displayList(List<String> values) {
  return values.isEmpty ? '-' : values.join(',');
}

String _plainPackageLine(int index, _ListedPackage package) {
  return '[$index] ${package.name} '
      '${_displayList(package.sdkLines)} ${_displayList(package.sources)}';
}

class _ListedPackage {
  const _ListedPackage({
    required this.name,
    required this.sdkLines,
    required this.sources,
    required this.compatibleReleaseCount,
  });

  final String name;
  final List<String> sdkLines;
  final List<String> sources;
  final int compatibleReleaseCount;

  Map<String, Object?> toJson() {
    return {
      'package': name,
      'sdkLines': sdkLines,
      'sources': sources,
      'compatibleReleaseCount': compatibleReleaseCount,
    };
  }
}
