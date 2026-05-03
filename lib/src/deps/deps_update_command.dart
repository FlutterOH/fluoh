import 'dart:io';

import 'package:args/command_runner.dart';

import '../cli/fluoh_command_runner.dart';
import '../context/fluoh_environment.dart';
import 'deps_analyzer.dart';

class DepsUpdateCommand extends Command<int> {
  DepsUpdateCommand({required this.environment, required OutputWriter stdout})
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
  String get name => 'update';

  @override
  String get description =>
      'Update existing OHOS adapter dependency overrides.';

  @override
  String get invocation => 'fluoh deps update';

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
    final report = await DepsAnalyzer(environment).analyze();
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
    for (final plan in plans) {
      updated = _replaceSectionRef(
        updated,
        plan.section,
        plan.packageName,
        plan.currentRef,
        plan.nextRef,
      );
    }

    await pubspec.writeAsString(updated);
    final overrideCount = plans
        .where((plan) => plan.section == 'dependency_overrides')
        .length;
    final dependencyCount = plans
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
      _stdout('Updated ${plans.length} OHOS dependency refs.');
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

  String _replaceSectionRef(
    String content,
    String section,
    String packageName,
    String currentRef,
    String nextRef,
  ) {
    final lines = content.split('\n');
    var inOverrides = false;
    var inPackage = false;

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

      lines[i] = line.replaceFirstMapped(
        RegExp(r'(\bref:\s*)' + RegExp.escape(currentRef) + r'\b'),
        (match) => '${match.group(1)}$nextRef',
      );
    }

    return lines.join('\n');
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

      final refMatch = RegExp(r'^\s+ref:\s*(\S+)\s*$').firstMatch(line);
      if (refMatch != null && currentPackage != null) {
        refs[currentPackage] = refMatch.group(1)!;
      }
    }

    return refs;
  }
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
