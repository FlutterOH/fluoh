import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

/// Default terminal width used when no TTY width is available.
const defaultTerminalLineLength = 80;

/// Semantic category for a human-readable terminal message.
enum TerminalMessageKind {
  /// Successful operation.
  success,

  /// Warning that does not stop the current command.
  warning,

  /// Error reported to the user.
  error,

  /// Informational message.
  info,

  /// Progress step in a multi-step workflow.
  step,

  /// Step or item skipped intentionally.
  skipped,
}

/// Status level used when coloring status text.
enum TerminalStatus {
  /// Successful status.
  ok,

  /// Warning status.
  warning,

  /// Error status.
  error,
}

/// ANSI color names supported by [TerminalStyle].
enum TerminalColor {
  /// Red foreground color.
  red,

  /// Green foreground color.
  green,

  /// Yellow foreground color.
  yellow,

  /// Blue foreground color.
  blue,

  /// Cyan foreground color.
  cyan,

  /// Gray foreground color.
  gray,
}

/// Semantic style for a terminal table cell.
enum TerminalTableCellStyle {
  /// Default table cell text.
  normal,

  /// Low-emphasis table cell text.
  muted,

  /// Command fragment.
  command,

  /// Filesystem path.
  path,

  /// URL value.
  url,

  /// Field-like value.
  value,

  /// Status value.
  status,
}

/// Formatting capabilities detected for the current terminal.
class TerminalCapabilities {
  /// Creates a terminal capability set.
  const TerminalCapabilities({
    required this.ansi,
    required this.decorated,
    required this.unicode,
  });

  /// Capability set that disables ANSI and decorative output.
  const TerminalCapabilities.plain()
    : ansi = false,
      decorated = false,
      unicode = true;

  /// Detects formatting support from process environment and stdout.
  factory TerminalCapabilities.detect({
    required bool enableFormatting,
    Map<String, String>? environment,
    bool? supportsAnsiEscapes,
  }) {
    final env = environment ?? io.Platform.environment;
    final term = env['TERM'] ?? '';
    final termIsDumb = term.toLowerCase() == 'dumb';
    final disabledColor =
        env.containsKey('NO_COLOR') || env['CLICOLOR'] == '0' || termIsDumb;
    final forcedColor =
        _isTruthyForceColor(env['FORCE_COLOR']) || env['CLICOLOR_FORCE'] == '1';
    final supportsAnsi =
        supportsAnsiEscapes ?? (enableFormatting && _stdoutSupportsAnsi());

    return TerminalCapabilities(
      ansi: enableFormatting && !disabledColor && (forcedColor || supportsAnsi),
      decorated:
          enableFormatting && !termIsDumb && (forcedColor || supportsAnsi),
      unicode: _supportsUnicode(env) && !termIsDumb,
    );
  }

  /// Whether ANSI escape sequences should be emitted.
  final bool ansi;

  /// Whether symbols and message markers should be emitted.
  final bool decorated;

  /// Whether unicode symbols are safe for the terminal.
  final bool unicode;
}

/// Applies terminal styling to human-readable output.
class TerminalStyle {
  /// Creates a style backed by [capabilities].
  const TerminalStyle({this.capabilities = const TerminalCapabilities.plain()});

  /// Detected terminal capabilities for this style.
  final TerminalCapabilities capabilities;

  /// Symbols selected for the terminal's unicode capability.
  TerminalSymbols get symbols =>
      capabilities.unicode ? TerminalSymbols.unicode : TerminalSymbols.ascii;

  /// Styles a top-level heading.
  String header(String text) =>
      paint(text, color: TerminalColor.cyan, bold: true);

  /// Styles a command help section title.
  String section(String text) => paint(text, bold: true);

  /// Styles a field label.
  String label(String text) => paint(text, color: TerminalColor.blue);

  /// Styles a field value.
  String value(String text) => text;

  /// Styles a command fragment.
  String command(String text) => paint(text, color: TerminalColor.cyan);

  /// Styles a filesystem path.
  String path(String text) => text;

  /// Styles a URL.
  String url(String text) => paint(text, color: TerminalColor.blue);

  /// Styles low-emphasis text.
  String muted(String text) => paint(text, color: TerminalColor.gray);

  /// Styles inline code, adding backticks when ANSI is unavailable.
  String code(String text) => capabilities.ansi ? command(text) : '`$text`';

  /// Styles status text according to [status].
  String status(TerminalStatus status, String text) {
    final color = switch (status) {
      TerminalStatus.ok => TerminalColor.green,
      TerminalStatus.warning => TerminalColor.yellow,
      TerminalStatus.error => TerminalColor.red,
    };
    return paint(text, color: color);
  }

  /// Adds a marker to [text] when decorated output is enabled.
  String message(TerminalMessageKind kind, String text) {
    if (!capabilities.decorated) {
      return text;
    }

    return '${messageMarker(kind)} $text';
  }

  /// Returns the colored marker for [kind].
  String messageMarker(TerminalMessageKind kind) {
    final marker = switch (kind) {
      TerminalMessageKind.success => symbols.success,
      TerminalMessageKind.warning => symbols.warning,
      TerminalMessageKind.error => symbols.error,
      TerminalMessageKind.info => symbols.info,
      TerminalMessageKind.step => symbols.step,
      TerminalMessageKind.skipped => symbols.skipped,
    };
    final color = switch (kind) {
      TerminalMessageKind.success => TerminalColor.green,
      TerminalMessageKind.warning => TerminalColor.yellow,
      TerminalMessageKind.error => TerminalColor.red,
      TerminalMessageKind.info => TerminalColor.blue,
      TerminalMessageKind.step => TerminalColor.cyan,
      TerminalMessageKind.skipped => TerminalColor.gray,
    };
    return paint(marker, color: color);
  }

  /// Applies ANSI color and emphasis when ANSI output is enabled.
  String paint(
    String text, {
    TerminalColor? color,
    bool bold = false,
    bool dim = false,
  }) {
    if (!capabilities.ansi || text.isEmpty) {
      return text;
    }

    final codes = <String>[
      if (bold) '1',
      if (dim) '2',
      if (color != null) _colorCode(color),
    ];
    if (codes.isEmpty) {
      return text;
    }
    return '\u001b[${codes.join(';')}m$text\u001b[0m';
  }
}

/// Writes human-readable CLI output with consistent styling and wrapping.
class TerminalOutput {
  /// Creates a terminal output writer.
  const TerminalOutput({
    required void Function(String message) stdout,
    void Function(String message)? stderr,
    void Function(String text)? transient,
    this.style = const TerminalStyle(),
    this.lineLength = defaultTerminalLineLength,
  }) : _stdout = stdout,
       _stderr = stderr ?? stdout,
       _transient = transient;

  final void Function(String message) _stdout;
  final void Function(String message) _stderr;
  final void Function(String text)? _transient;

  /// Styling rules used for human-readable output.
  final TerminalStyle style;

  /// Maximum line length used for wrapped output.
  final int lineLength;

  /// Writes a raw line to stdout.
  void write(String message) {
    _stdout(message);
  }

  /// Writes a raw line to stderr.
  void writeError(String message) {
    _stderr(message);
  }

  /// Writes a blank stdout line.
  void blank() {
    _stdout('');
  }

  /// Writes a styled heading.
  void heading(String text) {
    _stdout(style.header(text));
  }

  /// Writes a styled section title.
  void section(String text) {
    _stdout(style.section(text));
  }

  /// Writes a success message.
  void success(String message) {
    _writeMessage(_stdout, TerminalMessageKind.success, message);
  }

  /// Writes a warning message to stdout.
  void warning(String message) {
    _writeMessage(_stdout, TerminalMessageKind.warning, message);
  }

  /// Writes a warning message to stderr.
  void warningError(String message) {
    _writeMessage(_stderr, TerminalMessageKind.warning, message);
  }

  /// Writes an error message to stderr.
  void error(String message) {
    _writeMessage(_stderr, TerminalMessageKind.error, message);
  }

  /// Writes a failure message to stdout for command result summaries.
  void failure(String message) {
    _writeMessage(_stdout, TerminalMessageKind.error, message);
  }

  /// Writes an informational message.
  void info(String message) {
    _writeMessage(_stdout, TerminalMessageKind.info, message);
  }

  /// Writes a progress step message.
  void step(String message) {
    _writeMessage(_stdout, TerminalMessageKind.step, message);
  }

  /// Writes a skipped-action message.
  void skipped(String message) {
    _writeMessage(_stdout, TerminalMessageKind.skipped, message);
  }

  /// Writes a next-step hint.
  void next(String message) {
    final prefix = style.capabilities.decorated
        ? '${style.paint(style.symbols.arrow, color: TerminalColor.cyan)} '
        : '';
    final visiblePrefix = style.capabilities.decorated ? '  ' : '';
    _writeWrapped(
      _stdout,
      message,
      prefix: prefix,
      visiblePrefix: visiblePrefix,
    );
  }

  /// Writes an indented detail bullet.
  void detail(String message) {
    final bullet = style.paint(style.symbols.bullet, color: TerminalColor.gray);
    _writeWrapped(
      _stdout,
      message,
      prefix: '    $bullet ',
      visiblePrefix: '      ',
    );
  }

  /// Writes a wrapped message with a fixed indentation.
  void indented(String message, {int spaces = 2}) {
    final indent = ' ' * spaces;
    _writeWrapped(_stdout, message, prefix: indent, visiblePrefix: indent);
  }

  /// Runs [task] while showing transient progress when the terminal supports it.
  Future<T> withProgress<T>(
    String message,
    Future<T> Function() task, {
    bool showWhenPlain = false,
    String? successMessage,
  }) async {
    final transient = _transient;
    if (transient == null || !style.capabilities.decorated) {
      if (showWhenPlain) {
        step(message);
      }
      final result = await task();
      if (successMessage != null) {
        success(successMessage);
      }
      return result;
    }

    final frames = style.capabilities.unicode
        ? const ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
        : const ['-', r'\', '|', '/'];
    var frameIndex = 0;
    var visibleLength = 0;
    Timer? timer;

    void render() {
      final frame = frames[frameIndex % frames.length];
      frameIndex += 1;
      final line = '${style.paint(frame, color: TerminalColor.cyan)} $message';
      visibleLength = frame.length + message.length + 1;
      transient('\r$line');
    }

    void clear() {
      timer?.cancel();
      transient('\r${' ' * visibleLength}\r');
    }

    render();
    timer = Timer.periodic(const Duration(milliseconds: 90), (_) => render());
    try {
      final result = await task();
      clear();
      if (successMessage != null) {
        success(successMessage);
      }
      return result;
    } catch (_) {
      clear();
      rethrow;
    }
  }

  /// Writes a simple aligned table.
  void table({
    required List<TerminalTableColumn> columns,
    required List<List<String>> rows,
  }) {
    if (rows.isEmpty) {
      return;
    }

    final widths = <int>[];
    for (var column = 0; column < columns.length; column += 1) {
      var width = columns[column].header.length;
      for (final row in rows) {
        if (column >= row.length) {
          continue;
        }
        final cellWidth = row[column].length;
        if (cellWidth > width) {
          width = cellWidth;
        }
      }
      widths.add(width);
    }

    _stdout(
      [
        for (var i = 0; i < columns.length; i += 1)
          _tableHeader(columns[i].header, widths[i], columns[i].alignRight),
      ].join('  '),
    );
    for (final row in rows) {
      _stdout(
        [
          for (var i = 0; i < columns.length; i += 1)
            _tableCell(
              i < row.length ? row[i] : '',
              widths[i],
              columns[i].style,
              columns[i].alignRight,
            ),
        ].join('  '),
      );
    }
  }

  String _tableHeader(String text, int width, bool alignRight) {
    return _pad(
      style.paint(text, color: TerminalColor.cyan, bold: true),
      text,
      width,
      alignRight,
    );
  }

  String _tableCell(
    String text,
    int width,
    TerminalTableCellStyle cellStyle,
    bool alignRight,
  ) {
    return _pad(_styleTableCell(text, cellStyle), text, width, alignRight);
  }

  String _styleTableCell(String text, TerminalTableCellStyle cellStyle) {
    return switch (cellStyle) {
      TerminalTableCellStyle.normal => text,
      TerminalTableCellStyle.muted => style.muted(text),
      TerminalTableCellStyle.command => style.command(text),
      TerminalTableCellStyle.path => style.path(text),
      TerminalTableCellStyle.url => style.url(text),
      TerminalTableCellStyle.value => style.value(text),
      TerminalTableCellStyle.status => _statusCell(text),
    };
  }

  String _statusCell(String text) {
    final normalized = text.toLowerCase();
    final status = switch (normalized) {
      'installed' ||
      'ok' ||
      'passed' ||
      'ready' ||
      'current' => TerminalStatus.ok,
      'unknown' || 'missing' || 'warning' => TerminalStatus.warning,
      'failed' || 'error' => TerminalStatus.error,
      _ => null,
    };
    if (status != null) {
      return style.status(status, text);
    }
    if (normalized == 'remote' || normalized == 'skipped') {
      return style.muted(text);
    }
    return text;
  }

  String _pad(String styled, String raw, int width, bool alignRight) {
    final padding = ' ' * (width - raw.length);
    return alignRight ? '$padding$styled' : '$styled$padding';
  }

  void _writeMessage(
    void Function(String message) writer,
    TerminalMessageKind kind,
    String message,
  ) {
    if (!style.capabilities.decorated) {
      _writeWrapped(writer, message);
      return;
    }
    final marker = style.messageMarker(kind);
    _writeWrapped(writer, message, prefix: '$marker ', visiblePrefix: '  ');
  }

  void _writeWrapped(
    void Function(String message) writer,
    String message, {
    String prefix = '',
    String visiblePrefix = '',
  }) {
    final firstWidth = (lineLength - visiblePrefix.length).clamp(1, lineLength);
    final continuationPrefix = visiblePrefix.isEmpty
        ? ''
        : ' ' * visiblePrefix.length;
    final continuationWidth = (lineLength - continuationPrefix.length).clamp(
      1,
      lineLength,
    );
    final lines = wrapTerminalText(message, width: firstWidth.toInt());
    if (lines.isEmpty) {
      writer(prefix);
      return;
    }
    writer('$prefix${lines.first}');
    for (final line in lines.skip(1)) {
      for (final continuation in wrapTerminalText(
        line,
        width: continuationWidth.toInt(),
      )) {
        writer('$continuationPrefix$continuation');
      }
    }
  }
}

/// Wraps terminal text at [width] without breaking lines unnecessarily.
List<String> wrapTerminalText(String value, {required int width}) {
  final normalizedWidth = width < 1 ? 1 : width;
  final lines = <String>[];
  for (final rawLine in const LineSplitter().convert(value)) {
    if (rawLine.trim().isEmpty) {
      lines.add('');
      continue;
    }
    lines.addAll(_wrapTerminalLine(rawLine.trimRight(), normalizedWidth));
  }
  return lines;
}

List<String> _wrapTerminalLine(String line, int width) {
  if (line.length <= width) {
    return [line];
  }

  final result = <String>[];
  var remaining = line;
  while (remaining.length > width) {
    var split = _lastTerminalBreakBefore(remaining, width);
    if (split <= 0) {
      split = width;
    }
    result.add(remaining.substring(0, split).trimRight());
    remaining = remaining.substring(split).trimLeft();
  }
  if (remaining.isNotEmpty) {
    result.add(remaining);
  }
  return result.isEmpty ? [''] : result;
}

int _lastTerminalBreakBefore(String value, int width) {
  final searchLimit = width < value.length ? width : value.length;
  var bestSpace = -1;
  var bestSymbol = -1;
  for (var index = 0; index < searchLimit; index += 1) {
    final codeUnit = value.codeUnitAt(index);
    if (codeUnit == 0x20) {
      bestSpace = index + 1;
    } else if (codeUnit == 0x2f || codeUnit == 0x2d) {
      bestSymbol = index + 1;
    }
  }
  return bestSpace > 0 ? bestSpace : bestSymbol;
}

/// Column description for [TerminalOutput.table].
class TerminalTableColumn {
  /// Creates a terminal table column.
  const TerminalTableColumn(
    this.header, {
    this.style = TerminalTableCellStyle.normal,
    this.alignRight = false,
  });

  /// Header text displayed for this column.
  final String header;

  /// Cell style applied to values in this column.
  final TerminalTableCellStyle style;

  /// Whether cells in this column should be right-aligned.
  final bool alignRight;
}

/// Symbol set used for decorated terminal messages.
class TerminalSymbols {
  /// Creates a symbol set for terminal decoration.
  const TerminalSymbols({
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.step,
    required this.skipped,
    required this.bullet,
    required this.arrow,
  });

  /// Unicode symbols used when the terminal supports them.
  static const unicode = TerminalSymbols(
    success: '✓',
    warning: '!',
    error: '✗',
    info: 'i',
    step: '›',
    skipped: '-',
    bullet: '•',
    arrow: '→',
  );

  /// ASCII fallback symbols.
  static const ascii = TerminalSymbols(
    success: 'OK',
    warning: '!',
    error: 'x',
    info: 'i',
    step: '>',
    skipped: '-',
    bullet: '-',
    arrow: '->',
  );

  /// Success marker.
  final String success;

  /// Warning marker.
  final String warning;

  /// Error marker.
  final String error;

  /// Informational marker.
  final String info;

  /// Progress step marker.
  final String step;

  /// Skipped-action marker.
  final String skipped;

  /// Detail bullet marker.
  final String bullet;

  /// Next-step arrow marker.
  final String arrow;
}

bool _stdoutSupportsAnsi() {
  try {
    return io.stdout.supportsAnsiEscapes;
  } on Object {
    return false;
  }
}

bool _supportsUnicode(Map<String, String> environment) {
  if (io.Platform.isWindows) {
    return true;
  }

  final locale =
      environment['LC_ALL'] ?? environment['LC_CTYPE'] ?? environment['LANG'];
  if (locale == null || locale.isEmpty) {
    return false;
  }
  final normalized = locale.toLowerCase();
  return normalized.contains('utf-8') || normalized.contains('utf8');
}

bool _isTruthyForceColor(String? value) {
  if (value == null) {
    return false;
  }

  final normalized = value.trim().toLowerCase();
  return normalized == '1' ||
      normalized == '2' ||
      normalized == '3' ||
      normalized == 'true' ||
      normalized == 'yes' ||
      normalized == 'on';
}

String _colorCode(TerminalColor color) {
  return switch (color) {
    TerminalColor.red => '31',
    TerminalColor.green => '32',
    TerminalColor.yellow => '33',
    TerminalColor.blue => '34',
    TerminalColor.cyan => '36',
    TerminalColor.gray => '90',
  };
}
