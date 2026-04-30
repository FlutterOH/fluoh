import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/fluoh_command_runner.dart';
import '../context/fluoh_environment.dart';
import 'deps_analyzer.dart';

class DepsCommand extends Command<int> {
  DepsCommand({
    required FluohEnvironment environment,
    required OutputWriter stdout,
  }) {
    addSubcommand(DepsCheckCommand(environment: environment, stdout: stdout));
    addSubcommand(DepsFixCommand(environment: environment, stdout: stdout));
  }

  @override
  String get name => 'deps';

  @override
  String get description => 'Check and fix Flutter OHOS dependency adapters.';
}

class DepsCheckCommand extends Command<int> {
  DepsCheckCommand({required this.environment, required this.stdout}) {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print the compatibility report as JSON.',
    );
  }

  final FluohEnvironment environment;
  final OutputWriter stdout;

  @override
  String get name => 'check';

  @override
  String get description => 'Check dependency compatibility.';

  @override
  Future<int> run() async {
    final report = await DepsAnalyzer(environment).analyze();
    if (argResults!.flag('json')) {
      stdout(jsonEncode(report.toJson()));
      return 0;
    }

    for (final dependency in report.dependencies) {
      final adapterTag = dependency.adapter?.tag;
      stdout([dependency.name, dependency.status.label, ?adapterTag].join(' '));
    }
    return 0;
  }
}

class DepsFixCommand extends Command<int> {
  DepsFixCommand({required this.environment, required this.stdout}) {
    argParser
      ..addFlag(
        'yes',
        negatable: false,
        help: 'Write the generated dependency changes.',
      )
      ..addFlag(
        'allow-version-change',
        negatable: false,
        help: 'Allow adapters that target a different upstream version.',
      )
      ..addFlag(
        'rewrite',
        negatable: false,
        help: 'Rewrite direct dependencies instead of adding overrides.',
      );
  }

  final FluohEnvironment environment;
  final OutputWriter stdout;

  @override
  String get name => 'fix';

  @override
  String get description =>
      'Generate dependency replacements for adapted packages.';

  @override
  Future<int> run() async {
    final report = await DepsAnalyzer(environment).analyze();
    final allowVersionChange = argResults!.flag('allow-version-change');
    final rewrite = argResults!.flag('rewrite');
    final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
    final content = await pubspec.readAsString();
    final existingOverrides = _existingOverrideNames(content);
    final plans = report.dependencies
        .where((dependency) {
          if (!dependency.direct || dependency.adapter == null) {
            return false;
          }
          if (dependency.status == DependencyStatus.adapted) {
            return true;
          }
          return allowVersionChange &&
              dependency.status == DependencyStatus.versionMismatch;
        })
        .toList(growable: false);
    final writablePlans = plans
        .where((plan) => rewrite || !existingOverrides.contains(plan.name))
        .toList(growable: false);

    for (final plan in plans) {
      if (!rewrite && existingOverrides.contains(plan.name)) {
        stdout(
          'Would skip ${plan.name}: dependency_overrides already contains it.',
        );
      } else if (rewrite) {
        stdout('Would rewrite ${plan.name} -> ${plan.adapter!.tag}');
      } else {
        stdout('Would override ${plan.name} -> ${plan.adapter!.tag}');
      }
    }

    if (!argResults!.flag('yes')) {
      return 0;
    }

    stdout('Will modify ${pubspec.path}.');
    final wrote = rewrite
        ? await _rewriteDependencies(writablePlans)
        : await _writeOverrides(writablePlans);
    stdout(
      rewrite
          ? 'Rewrote $wrote dependenc${wrote == 1 ? 'y' : 'ies'}.'
          : 'Wrote $wrote dependency override${wrote == 1 ? '' : 's'}.',
    );
    return 0;
  }

  Future<int> _writeOverrides(List<DependencyCompatibility> plans) async {
    if (plans.isEmpty) {
      return 0;
    }

    final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
    final content = await pubspec.readAsString();
    final lines = content.split('\n');
    final sectionIndex = _ensureOverrideSection(lines);
    var overrideEnd = _overrideSectionEnd(lines, sectionIndex);
    var wrote = 0;

    for (final plan in plans) {
      final existing = _overrideBlockRange(lines, sectionIndex, plan.name);
      if (existing != null) {
        continue;
      }

      final block = _overrideYamlLines(plan);
      lines.insertAll(overrideEnd, block);
      overrideEnd += block.length;
      wrote += 1;
    }

    if (wrote == 0) {
      return 0;
    }

    await pubspec.writeAsString(
      '${_trimTrailingEmptyLines(lines).join('\n')}\n',
    );
    return wrote;
  }

  Future<int> _rewriteDependencies(List<DependencyCompatibility> plans) async {
    if (plans.isEmpty) {
      return 0;
    }

    final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
    final lines = (await pubspec.readAsString()).split('\n');
    final sectionIndex = _topLevelSectionIndex(lines, 'dependencies');
    if (sectionIndex == -1) {
      return 0;
    }

    var wrote = 0;
    for (final plan in plans) {
      final existing = _dependencyBlockRange(lines, sectionIndex, plan.name);
      if (existing == null) {
        continue;
      }
      lines.replaceRange(
        existing.start,
        existing.end,
        _dependencyYamlLines(plan),
      );
      _removeOverrideBlock(lines, plan.name);
      wrote += 1;
    }

    if (wrote == 0) {
      return 0;
    }

    await pubspec.writeAsString(
      '${_trimTrailingEmptyLines(lines).join('\n')}\n',
    );
    return wrote;
  }

  int _ensureOverrideSection(List<String> lines) {
    final existing = _topLevelSectionIndex(lines, 'dependency_overrides');
    if (existing != -1) {
      return existing;
    }

    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    if (lines.isNotEmpty) {
      lines.add('');
    }
    lines.add('dependency_overrides:');
    return lines.length - 1;
  }

  int _overrideSectionEnd(List<String> lines, int sectionIndex) {
    for (var i = sectionIndex + 1; i < lines.length; i += 1) {
      final line = lines[i];
      if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('\t')) {
        return i;
      }
    }
    return lines.length;
  }

  int _topLevelSectionIndex(List<String> lines, String name) {
    return lines.indexWhere(
      (line) => RegExp('^${RegExp.escape(name)}:\\s*\$').hasMatch(line),
    );
  }

  _LineRange? _overrideBlockRange(
    List<String> lines,
    int sectionIndex,
    String packageName,
  ) {
    final end = _overrideSectionEnd(lines, sectionIndex);
    final packagePattern = RegExp(
      r'^  ' + RegExp.escape(packageName) + r':\s*$',
    );
    for (var i = sectionIndex + 1; i < end; i += 1) {
      if (!packagePattern.hasMatch(lines[i])) {
        continue;
      }

      var blockEnd = end;
      for (var j = i + 1; j < end; j += 1) {
        if (RegExp(r'^  \S').hasMatch(lines[j])) {
          blockEnd = j;
          break;
        }
      }
      return _LineRange(i, blockEnd);
    }
    return null;
  }

  List<String> _overrideYamlLines(DependencyCompatibility plan) {
    final adapter = plan.adapter!;
    return _gitDependencyLines(
      plan.name,
      adapter.repository,
      adapter.tag,
      adapter.path,
    );
  }

  List<String> _dependencyYamlLines(DependencyCompatibility plan) {
    final adapter = plan.adapter!;
    return _gitDependencyLines(
      plan.name,
      adapter.repository,
      adapter.tag,
      adapter.path,
    );
  }

  List<String> _gitDependencyLines(
    String packageName,
    String repository,
    String tag,
    String? path,
  ) {
    return [
      '  $packageName:',
      '    git:',
      '      url: $repository',
      '      ref: $tag',
      if (path != null && path.isNotEmpty) '      path: $path',
    ];
  }

  _LineRange? _dependencyBlockRange(
    List<String> lines,
    int sectionIndex,
    String packageName,
  ) {
    final end = _overrideSectionEnd(lines, sectionIndex);
    final scalarPattern = RegExp(
      r'^  ' + RegExp.escape(packageName) + r':(?:\s+.*)?$',
    );
    for (var i = sectionIndex + 1; i < end; i += 1) {
      if (!scalarPattern.hasMatch(lines[i])) {
        continue;
      }

      var blockEnd = i + 1;
      if (RegExp(r'^  \S[^:]*:\s*$').hasMatch(lines[i])) {
        blockEnd = end;
        for (var j = i + 1; j < end; j += 1) {
          if (RegExp(r'^  \S').hasMatch(lines[j])) {
            blockEnd = j;
            break;
          }
        }
      }
      return _LineRange(i, blockEnd);
    }
    return null;
  }

  void _removeOverrideBlock(List<String> lines, String packageName) {
    final sectionIndex = _topLevelSectionIndex(lines, 'dependency_overrides');
    if (sectionIndex == -1) {
      return;
    }
    final block = _overrideBlockRange(lines, sectionIndex, packageName);
    if (block == null) {
      return;
    }
    lines.removeRange(block.start, block.end);
    final end = _overrideSectionEnd(lines, sectionIndex);
    final hasEntries = lines
        .sublist(sectionIndex + 1, end)
        .any((line) => RegExp(r'^  \S').hasMatch(line));
    if (!hasEntries) {
      lines.removeAt(sectionIndex);
    }
  }

  Set<String> _existingOverrideNames(String content) {
    final lines = content.split('\n');
    final sectionIndex = _topLevelSectionIndex(lines, 'dependency_overrides');
    if (sectionIndex == -1) {
      return const {};
    }
    final end = _overrideSectionEnd(lines, sectionIndex);
    return lines
        .sublist(sectionIndex + 1, end)
        .map((line) => RegExp(r'^  ([A-Za-z0-9_]+):').firstMatch(line))
        .whereType<RegExpMatch>()
        .map((match) => match.group(1)!)
        .toSet();
  }

  List<String> _trimTrailingEmptyLines(List<String> lines) {
    final trimmed = lines.toList(growable: true);
    while (trimmed.isNotEmpty && trimmed.last.isEmpty) {
      trimmed.removeLast();
    }
    return trimmed;
  }
}

class _LineRange {
  const _LineRange(this.start, this.end);

  final int start;
  final int end;
}
