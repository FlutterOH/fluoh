import 'dart:io';

import 'package:args/command_runner.dart';

import '../../cli/fluoh_command_runner.dart';
import '../../context/fluoh_environment.dart';
import '../pub_dependency_analyzer.dart';

class PubUpgradeCommand extends Command<int> {
  PubUpgradeCommand({required this.environment, required OutputWriter stdout})
    : _stdout = stdout {
    argParser
      ..addFlag(
        'yes',
        negatable: false,
        help: 'Write updated OHOS adapter refs to dependency_overrides.',
      )
      ..addFlag(
        'allow-version-change',
        negatable: false,
        help: 'Allow updating to adapters for a different upstream version.',
      );
  }

  final FluohEnvironment environment;
  final OutputWriter _stdout;

  @override
  String get name => 'upgrade';

  @override
  String get description =>
      'Upgrade existing OHOS adapter dependency overrides.';

  @override
  String get invocation => 'fluoh pub upgrade';

  @override
  Future<int> run() async {
    final pubspec = File('${environment.workingDirectory.path}/pubspec.yaml');
    final content = await pubspec.readAsString();
    final overrides = _parseSectionRefs(content, 'dependency_overrides');
    final dependencies = _parseSectionRefs(content, 'dependencies');
    if (overrides.isEmpty && dependencies.isEmpty) {
      _stdout('No OHOS dependency refs found.');
      return 0;
    }

    final allowVersionChange = argResults!.flag('allow-version-change');
    final report = await PubDependencyAnalyzer(environment).analyze();
    final plans = <AdapterUpdatePlan>[];

    for (final dependency in report.dependencies) {
      final adapter = dependency.adapter;
      if (adapter == null) {
        continue;
      }
      if (!allowVersionChange &&
          dependency.status == DependencyStatus.versionMismatch) {
        continue;
      }

      _addPlan(
        plans,
        section: 'dependency_overrides',
        packageName: dependency.name,
        currentRef: overrides[dependency.name],
        nextRef: adapter.tag,
      );
      _addPlan(
        plans,
        section: 'dependencies',
        packageName: dependency.name,
        currentRef: dependencies[dependency.name],
        nextRef: adapter.tag,
      );
    }

    if (plans.isEmpty) {
      _stdout('No OHOS dependency override updates available.');
      return 0;
    }

    for (final plan in plans) {
      _stdout(
        'Would update ${plan.packageName} ${plan.currentRef} -> ${plan.nextRef}',
      );
    }

    if (!argResults!.flag('yes')) {
      return 0;
    }

    var updated = content;
    final appliedPlans = <AdapterUpdatePlan>[];
    final failedPlans = <AdapterUpdatePlan>[];
    for (final plan in plans) {
      final result = _replaceSectionRef(
        updated,
        plan.section,
        plan.packageName,
        plan.currentRef,
        plan.nextRef,
      );
      updated = result.content;
      if (result.replaced) {
        appliedPlans.add(plan);
      } else {
        failedPlans.add(plan);
      }
    }

    if (failedPlans.isNotEmpty) {
      final failed = failedPlans
          .map((plan) => '${plan.section}.${plan.packageName}')
          .join(', ');
      throw UsageException(
        'Could not update OHOS dependency refs: $failed.',
        '',
      );
    }

    await pubspec.writeAsString(updated);
    final overrideCount = appliedPlans
        .where((plan) => plan.section == 'dependency_overrides')
        .length;
    final dependencyCount = appliedPlans
        .where((plan) => plan.section == 'dependencies')
        .length;
    if (dependencyCount == 0) {
      _stdout(
        'Updated $overrideCount dependency override${overrideCount == 1 ? '' : 's'}.',
      );
    } else if (overrideCount == 0) {
      _stdout(
        'Updated $dependencyCount OHOS dependenc${dependencyCount == 1 ? 'y' : 'ies'}.',
      );
    } else {
      _stdout('Updated ${appliedPlans.length} OHOS dependency refs.');
    }
    return 0;
  }

  void _addPlan(
    List<AdapterUpdatePlan> plans, {
    required String section,
    required String packageName,
    required String? currentRef,
    required String nextRef,
  }) {
    if (currentRef == null ||
        !currentRef.contains('-ohos-') ||
        currentRef == nextRef) {
      return;
    }
    plans.add(
      AdapterUpdatePlan(
        section: section,
        packageName: packageName,
        currentRef: currentRef,
        nextRef: nextRef,
      ),
    );
  }

  ({String content, bool replaced}) _replaceSectionRef(
    String content,
    String section,
    String packageName,
    String currentRef,
    String nextRef,
  ) {
    final lines = content.split('\n');
    var inOverrides = false;
    var inPackage = false;
    var replaced = false;

    for (var i = 0; i < lines.length; i += 1) {
      final line = lines[i];
      if (!inOverrides) {
        if (RegExp('^${RegExp.escape(section)}:\\s*\$').hasMatch(line)) {
          inOverrides = true;
        }
        continue;
      }

      if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('\t')) {
        break;
      }

      final packageMatch = RegExp(r'^  ([A-Za-z0-9_]+):\s*$').firstMatch(line);
      if (packageMatch != null) {
        inPackage = packageMatch.group(1) == packageName;
        continue;
      }

      if (!inPackage) {
        continue;
      }

      final ref = _parseRefLine(line);
      if (ref == null || ref.value != currentRef) {
        continue;
      }

      lines[i] =
          '${ref.prefix}${ref.quote ?? ''}$nextRef${ref.quote ?? ''}${ref.suffix}';
      replaced = true;
    }

    return (content: lines.join('\n'), replaced: replaced);
  }

  Map<String, String> _parseSectionRefs(String content, String section) {
    final lines = content.split('\n');
    final refs = <String, String>{};
    var inOverrides = false;
    String? currentPackage;

    for (final line in lines) {
      if (!inOverrides) {
        if (RegExp('^${RegExp.escape(section)}:\\s*\$').hasMatch(line)) {
          inOverrides = true;
        }
        continue;
      }

      if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('\t')) {
        break;
      }

      final packageMatch = RegExp(r'^  ([A-Za-z0-9_]+):\s*$').firstMatch(line);
      if (packageMatch != null) {
        currentPackage = packageMatch.group(1);
        continue;
      }

      final ref = _parseRefLine(line);
      if (ref != null && currentPackage != null) {
        refs[currentPackage] = ref.value;
      }
    }

    return refs;
  }
}

_ParsedRefLine? _parseRefLine(String line) {
  final match = RegExp(
    r'''^(\s+ref:\s*)(?:"([^"]+)"|'([^']+)'|([^#\s]+))(\s*(?:#.*)?)$''',
  ).firstMatch(line);
  if (match == null) {
    return null;
  }

  if (match.group(2) != null) {
    return _ParsedRefLine(
      prefix: match.group(1)!,
      value: match.group(2)!,
      quote: '"',
      suffix: match.group(5)!,
    );
  }
  if (match.group(3) != null) {
    return _ParsedRefLine(
      prefix: match.group(1)!,
      value: match.group(3)!,
      quote: "'",
      suffix: match.group(5)!,
    );
  }
  return _ParsedRefLine(
    prefix: match.group(1)!,
    value: match.group(4)!,
    suffix: match.group(5)!,
  );
}

class _ParsedRefLine {
  const _ParsedRefLine({
    required this.prefix,
    required this.value,
    required this.suffix,
    this.quote,
  });

  final String prefix;
  final String value;
  final String? quote;
  final String suffix;
}

class AdapterUpdatePlan {
  const AdapterUpdatePlan({
    required this.section,
    required this.packageName,
    required this.currentRef,
    required this.nextRef,
  });

  final String section;
  final String packageName;
  final String currentRef;
  final String nextRef;
}
