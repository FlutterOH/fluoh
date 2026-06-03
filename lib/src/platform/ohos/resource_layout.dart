import 'dart:io' as io;

/// Result of moving one OHOS generated resource into its stable location.
class OhosResourceLayoutMove {
  /// Creates a resource layout move record.
  const OhosResourceLayoutMove({
    required this.from,
    required this.to,
    required this.moved,
  });

  /// Source path relative to the OHOS project directory.
  final String from;

  /// Destination path relative to the OHOS project directory.
  final String to;

  /// Whether a filesystem move happened.
  final bool moved;
}

/// Normalizes generated OHOS resources into the stable rawfile layout.
///
/// Some FlutterOH/Hvigor builds move selected files from
/// `resources/base/profile` into `resources/rawfile`. Running this before and
/// after builds keeps tracked package example diffs stable.
Future<List<OhosResourceLayoutMove>> stabilizeOhosResourceLayout(
  io.Directory ohosDirectory,
) async {
  final moves = <OhosResourceLayoutMove>[];
  for (final fileName in const ['buildinfo.json5', 'framesconfig.json']) {
    final from = 'entry/src/main/resources/base/profile/$fileName';
    final to = 'entry/src/main/resources/rawfile/$fileName';
    final moved = await _moveIfNeeded(ohosDirectory, from: from, to: to);
    if (moved != null) {
      moves.add(OhosResourceLayoutMove(from: from, to: to, moved: moved));
    }
  }
  return moves;
}

Future<bool?> _moveIfNeeded(
  io.Directory ohosDirectory, {
  required String from,
  required String to,
}) async {
  final source = io.File('${ohosDirectory.path}/$from');
  if (!await source.exists()) {
    return null;
  }
  final destination = io.File('${ohosDirectory.path}/$to');
  if (await destination.exists()) {
    if (await source.readAsString() == await destination.readAsString()) {
      await source.delete();
      return false;
    }
    return null;
  }
  await destination.parent.create(recursive: true);
  await source.rename(destination.path);
  return true;
}
