import 'package:args/command_runner.dart';

import 'terminal_output.dart';

class CommandUsageSection {
  const CommandUsageSection(this.title, this.commandNames);

  final String title;
  final List<String> commandNames;
}

String formatCommandUsage(
  Map<String, Command> commands, {
  required List<CommandUsageSection> sections,
  required bool isSubcommand,
  int? lineLength,
  TerminalStyle style = const TerminalStyle(),
}) {
  final visible = _visibleCommands(commands);
  final used = <String>{};
  final orderedSections = <CommandUsageSection>[
    for (final section in sections)
      CommandUsageSection(section.title, [
        for (final name in section.commandNames)
          if (visible.containsKey(name)) name,
      ]),
  ].where((section) => section.commandNames.isNotEmpty).toList();

  for (final section in orderedSections) {
    used.addAll(section.commandNames);
  }

  final remaining = [
    for (final name in visible.keys)
      if (!used.contains(name)) name,
  ];
  if (remaining.isNotEmpty) {
    orderedSections.add(CommandUsageSection('Other commands:', remaining));
  }

  final names = [
    for (final section in orderedSections) ...section.commandNames,
  ];
  if (names.isEmpty) {
    return 'Available ${isSubcommand ? "sub" : ""}commands:';
  }

  final nameLength = names
      .map((name) => name.length)
      .reduce((max, length) => length > max ? length : max);
  final columnStart = nameLength + 5;
  final buffer = StringBuffer(
    'Available ${isSubcommand ? "sub" : ""}commands:',
  );

  for (final section in orderedSections) {
    final hasTitle = section.title.isNotEmpty;
    if (hasTitle) {
      buffer
        ..writeln()
        ..writeln()
        ..write(style.section(section.title));
    }
    for (final name in section.commandNames) {
      final command = visible[name]!;
      final lines = _wrapSummary(
        command.summary,
        start: columnStart,
        lineLength: lineLength,
      );
      buffer
        ..writeln()
        ..write('  ${style.command(name.padRight(nameLength))}   ')
        ..write(lines.first);
      for (final line in lines.skip(1)) {
        buffer
          ..writeln()
          ..write(' ' * columnStart)
          ..write(line);
      }
    }
  }

  return buffer.toString();
}

Map<String, Command> _visibleCommands(Map<String, Command> commands) {
  return {
    for (final entry in commands.entries)
      if (entry.key == entry.value.name && !entry.value.hidden)
        entry.key: entry.value,
  };
}

List<String> _wrapSummary(
  String summary, {
  required int start,
  required int? lineLength,
}) {
  final maxLength = lineLength == null ? null : lineLength - start;
  if (maxLength == null || maxLength < 20 || summary.length <= maxLength) {
    return [summary];
  }

  final lines = <String>[];
  var current = '';
  for (final word in summary.split(RegExp(r'\s+'))) {
    if (current.isEmpty) {
      current = word;
      continue;
    }
    if (current.length + word.length + 1 > maxLength) {
      lines.add(current);
      current = word;
    } else {
      current = '$current $word';
    }
  }
  if (current.isNotEmpty) {
    lines.add(current);
  }
  return lines.isEmpty ? [''] : lines;
}
