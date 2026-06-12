part of 'package_create_command.dart';

const _claudeAgentsImport = '@AGENTS.md';

Future<void> _writeClaudeInstructions(Directory destination) async {
  final file = File('${destination.path}/CLAUDE.md');
  if (!await file.exists()) {
    await file.writeAsString('$_claudeAgentsImport\n');
    return;
  }

  final existing = await file.readAsString();
  if (existing.trim().isEmpty) {
    await file.writeAsString('$_claudeAgentsImport\n');
    return;
  }
  if (_importsAgentsInstructions(existing)) {
    return;
  }

  final separator = existing.startsWith('\n') ? '' : '\n';
  await file.writeAsString('$_claudeAgentsImport\n$separator$existing');
}

bool _importsAgentsInstructions(String content) {
  return content.split('\n').any((line) => line.trim() == _claudeAgentsImport);
}
