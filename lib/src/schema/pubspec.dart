import 'source_index.dart';
import 'yaml_utils.dart';

class PubspecPackage {
  const PubspecPackage({required this.name, required this.version});

  factory PubspecPackage.fromYaml(String content) {
    final yaml = parseYamlMap(content, label: 'pubspec.yaml');
    final name = yaml['name'];
    final version = yaml['version'];
    if (name is! String || version is! String) {
      throw const FluohSchemaException(
        'pubspec.yaml must contain name and version.',
      );
    }
    return PubspecPackage(name: name, version: version);
  }

  final String name;
  final String version;
}

class PubLockPackage {
  const PubLockPackage({
    required this.name,
    required this.version,
    this.dependencies = const <String>[],
  });

  final String name;
  final String version;
  final List<String> dependencies;
}

typedef LockedPackage = PubLockPackage;

Set<String> directDependencyNamesFromPubspec(String content) {
  final pubspec = parseYamlMap(content, label: 'pubspec.yaml');
  final dependencies = pubspec['dependencies'];
  if (dependencies is! Map<String, Object?>) {
    return const {};
  }

  return dependencies.entries
      .where((entry) {
        final value = entry.value;
        return !(value is Map<String, Object?> && value['sdk'] == 'flutter');
      })
      .map((entry) => entry.key)
      .toSet();
}

Map<String, PubLockPackage> pubLockPackagesFromLock(String content) {
  final lock = parseYamlMap(content, label: 'pubspec.lock');
  final packages = lock['packages'];
  if (packages is! Map<String, Object?>) {
    throw const FluohSchemaException('pubspec.lock packages must be a map.');
  }

  return packages.map((name, value) {
    final package = objectMap(value, 'pubspec.lock package $name');
    return MapEntry(
      name,
      PubLockPackage(
        name: name,
        version: package['version'] as String? ?? '',
        dependencies: _packageDependencies(package),
      ),
    );
  });
}

Map<String, List<String>> dependencyChains(
  Map<String, PubLockPackage> packages,
  Set<String> directDependencies,
) {
  final chains = <String, List<String>>{};
  final queue = <List<String>>[];
  for (final direct in directDependencies) {
    if (!packages.containsKey(direct)) {
      continue;
    }
    final chain = <String>[direct];
    chains[direct] = chain;
    queue.add(chain);
  }

  for (var index = 0; index < queue.length; index += 1) {
    final chain = queue[index];
    final package = packages[chain.last];
    if (package == null) {
      continue;
    }
    for (final dependency in package.dependencies) {
      if (!packages.containsKey(dependency) || chains.containsKey(dependency)) {
        continue;
      }
      final next = [...chain, dependency];
      chains[dependency] = next;
      queue.add(next);
    }
  }
  return chains;
}

List<String> _packageDependencies(Map<String, Object?> package) {
  final dependencies = package['dependencies'];
  if (dependencies is! Map<String, Object?>) {
    return const [];
  }
  return dependencies.keys.toList(growable: false);
}

enum PubspecDependencySection {
  dependencies('dependencies'),
  dependencyOverrides('dependency_overrides');

  const PubspecDependencySection(this.yamlKey);

  final String yamlKey;
}

enum PubspecDependencyChangeKind { writeOverride, rewriteDependency, updateRef }

class PubspecDependencyState {
  const PubspecDependencyState({
    required this.dependencyRefs,
    required this.overrideRefs,
    required this.overrideNames,
  });

  final Map<String, PubspecDependencyRef> dependencyRefs;
  final Map<String, PubspecDependencyRef> overrideRefs;
  final Set<String> overrideNames;

  List<PubspecDependencyRef> ohosRefsFor(String packageName) {
    final refs = <PubspecDependencyRef>[];
    final dependencyRef = dependencyRefs[packageName];
    if (dependencyRef != null && dependencyRef.value.contains('-ohos-')) {
      refs.add(dependencyRef);
    }
    final overrideRef = overrideRefs[packageName];
    if (overrideRef != null && overrideRef.value.contains('-ohos-')) {
      refs.add(overrideRef);
    }
    return refs;
  }
}

class PubspecDependencyRef {
  const PubspecDependencyRef({
    required this.section,
    required this.packageName,
    required this.value,
  });

  final PubspecDependencySection section;
  final String packageName;
  final String value;
}

class PubspecDependencyChange {
  const PubspecDependencyChange.writeOverride({
    required this.packageName,
    required this.implementation,
  }) : kind = PubspecDependencyChangeKind.writeOverride,
       section = null,
       currentRef = null;

  const PubspecDependencyChange.rewriteDependency({
    required this.packageName,
    required this.implementation,
  }) : kind = PubspecDependencyChangeKind.rewriteDependency,
       section = null,
       currentRef = null;

  const PubspecDependencyChange.updateRef({
    required this.packageName,
    required this.implementation,
    required this.section,
    required this.currentRef,
  }) : kind = PubspecDependencyChangeKind.updateRef;

  final PubspecDependencyChangeKind kind;
  final String packageName;
  final PackageImplementation implementation;
  final PubspecDependencySection? section;
  final String? currentRef;

  String get nextRef => implementation.tag;
}

class PubspecDependencyApplyResult {
  const PubspecDependencyApplyResult({
    required this.content,
    required this.applied,
  });

  final String content;
  final int applied;
}

PubspecDependencyState parsePubspecDependencyState(String content) {
  return PubspecDependencyState(
    dependencyRefs: _parseSectionRefs(
      content,
      PubspecDependencySection.dependencies,
    ),
    overrideRefs: _parseSectionRefs(
      content,
      PubspecDependencySection.dependencyOverrides,
    ),
    overrideNames: _parseSectionPackageNames(
      content,
      PubspecDependencySection.dependencyOverrides,
    ),
  );
}

PubspecDependencyApplyResult applyPubspecDependencyChangesToContent({
  required String content,
  required List<PubspecDependencyChange> changes,
}) {
  if (changes.isEmpty) {
    return PubspecDependencyApplyResult(content: content, applied: 0);
  }

  final lines = content.split('\n');
  var applied = 0;
  final failed = <String>[];

  for (final change in changes) {
    switch (change.kind) {
      case PubspecDependencyChangeKind.writeOverride:
        if (_insertOverride(lines, change)) {
          applied += 1;
        } else {
          failed.add('dependency_overrides.${change.packageName}');
        }
      case PubspecDependencyChangeKind.rewriteDependency:
        if (_rewriteDependency(lines, change)) {
          applied += 1;
        } else {
          failed.add('dependencies.${change.packageName}');
        }
      case PubspecDependencyChangeKind.updateRef:
        if (_replaceSectionRef(lines, change)) {
          applied += 1;
        } else {
          failed.add('${change.section!.yamlKey}.${change.packageName}');
        }
    }
  }

  if (failed.isNotEmpty) {
    throw FluohSchemaException(
      'Could not update FlutterOH dependency replacements: '
      '${failed.join(', ')}.',
    );
  }

  return PubspecDependencyApplyResult(
    content: '${_trimTrailingEmptyLines(lines).join('\n')}\n',
    applied: applied,
  );
}

Map<String, PubspecDependencyRef> _parseSectionRefs(
  String content,
  PubspecDependencySection section,
) {
  final lines = content.split('\n');
  final refs = <String, PubspecDependencyRef>{};
  var inSection = false;
  String? currentPackage;

  for (final line in lines) {
    if (!inSection) {
      if (_topLevelSectionPattern(section.yamlKey).hasMatch(line)) {
        inSection = true;
      }
      continue;
    }

    if (_isNextTopLevelSection(line)) {
      break;
    }

    final packageMatch = _anyPackageBlockKeyPattern.firstMatch(line);
    if (packageMatch != null) {
      currentPackage = packageMatch.group(1);
      continue;
    }

    final ref = _parseRefLine(line);
    if (ref != null && currentPackage != null) {
      refs[currentPackage] = PubspecDependencyRef(
        section: section,
        packageName: currentPackage,
        value: ref.value,
      );
    }
  }

  return refs;
}

Set<String> _parseSectionPackageNames(
  String content,
  PubspecDependencySection section,
) {
  final lines = content.split('\n');
  final sectionIndex = _topLevelSectionIndex(lines, section.yamlKey);
  if (sectionIndex == -1) {
    return const {};
  }
  final end = _sectionEnd(lines, sectionIndex);
  return lines
      .sublist(sectionIndex + 1, end)
      .map((line) => RegExp(r'^  ([A-Za-z0-9_]+):').firstMatch(line))
      .whereType<RegExpMatch>()
      .map((match) => match.group(1)!)
      .toSet();
}

bool _insertOverride(List<String> lines, PubspecDependencyChange change) {
  final sectionIndex = _ensureOverrideSection(lines);
  final existing = _dependencyBlockRange(
    lines,
    sectionIndex,
    change.packageName,
  );
  if (existing != null) {
    return false;
  }

  final insertIndex = _sectionEnd(lines, sectionIndex);
  lines.insertAll(insertIndex, _gitDependencyLines(change));
  return true;
}

bool _rewriteDependency(List<String> lines, PubspecDependencyChange change) {
  final sectionIndex = _topLevelSectionIndex(lines, 'dependencies');
  if (sectionIndex == -1) {
    return false;
  }

  final existing = _dependencyBlockRange(
    lines,
    sectionIndex,
    change.packageName,
  );
  if (existing == null) {
    return false;
  }

  lines.replaceRange(existing.start, existing.end, _gitDependencyLines(change));
  _removeOverrideBlock(lines, change.packageName);
  return true;
}

bool _replaceSectionRef(List<String> lines, PubspecDependencyChange change) {
  final section = change.section!;
  final sectionIndex = _topLevelSectionIndex(lines, section.yamlKey);
  if (sectionIndex == -1) {
    return false;
  }

  final end = _sectionEnd(lines, sectionIndex);
  var inPackage = false;
  for (var i = sectionIndex + 1; i < end; i += 1) {
    final line = lines[i];
    final packageMatch = _anyPackageBlockKeyPattern.firstMatch(line);
    if (packageMatch != null) {
      inPackage = packageMatch.group(1) == change.packageName;
      continue;
    }
    if (!inPackage) {
      continue;
    }

    final ref = _parseRefLine(line);
    if (ref == null || ref.value != change.currentRef) {
      continue;
    }

    lines[i] =
        '${ref.prefix}${ref.quote ?? ''}${change.nextRef}${ref.quote ?? ''}${ref.suffix}';
    return true;
  }

  return false;
}

List<String> _gitDependencyLines(PubspecDependencyChange change) {
  return [
    '  ${change.packageName}:',
    '    git:',
    '      url: ${change.implementation.repository}',
    '      ref: ${change.implementation.tag}',
    if (change.implementation.path != null &&
        change.implementation.path!.isNotEmpty)
      '      path: ${change.implementation.path}',
  ];
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

void _removeOverrideBlock(List<String> lines, String packageName) {
  final sectionIndex = _topLevelSectionIndex(lines, 'dependency_overrides');
  if (sectionIndex == -1) {
    return;
  }
  final block = _dependencyBlockRange(lines, sectionIndex, packageName);
  if (block == null) {
    return;
  }
  lines.removeRange(block.start, block.end);
  final end = _sectionEnd(lines, sectionIndex);
  final hasEntries = lines
      .sublist(sectionIndex + 1, end)
      .any((line) => RegExp(r'^  \S').hasMatch(line));
  if (!hasEntries) {
    lines.removeAt(sectionIndex);
  }
}

_LineRange? _dependencyBlockRange(
  List<String> lines,
  int sectionIndex,
  String packageName,
) {
  final end = _sectionEnd(lines, sectionIndex);
  final scalarPattern = RegExp(
    r'^  ' + RegExp.escape(packageName) + r':(?:\s+.*)?$',
  );
  for (var i = sectionIndex + 1; i < end; i += 1) {
    if (!scalarPattern.hasMatch(lines[i])) {
      continue;
    }

    var blockEnd = i + 1;
    if (_packageBlockKeyPattern(packageName).hasMatch(lines[i])) {
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

final _anyPackageBlockKeyPattern = RegExp(r'^  ([A-Za-z0-9_]+):\s*(?:#.*)?$');

RegExp _packageBlockKeyPattern(String packageName) {
  return RegExp('^  ${RegExp.escape(packageName)}:\\s*(?:#.*)?\$');
}

int _topLevelSectionIndex(List<String> lines, String name) {
  return lines.indexWhere(
    (line) => _topLevelSectionPattern(name).hasMatch(line),
  );
}

RegExp _topLevelSectionPattern(String name) {
  return RegExp('^${RegExp.escape(name)}:\\s*(?:#.*)?\$');
}

int _sectionEnd(List<String> lines, int sectionIndex) {
  for (var i = sectionIndex + 1; i < lines.length; i += 1) {
    if (_isNextTopLevelSection(lines[i])) {
      return i;
    }
  }
  return lines.length;
}

bool _isNextTopLevelSection(String line) {
  return line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('\t');
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

List<String> _trimTrailingEmptyLines(List<String> lines) {
  final trimmed = lines.toList(growable: true);
  while (trimmed.isNotEmpty && trimmed.last.isEmpty) {
    trimmed.removeLast();
  }
  return trimmed;
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
  final String suffix;
  final String? quote;
}

class _LineRange {
  const _LineRange(this.start, this.end);

  final int start;
  final int end;
}
