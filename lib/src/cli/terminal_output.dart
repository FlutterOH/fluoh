import 'dart:async';
import 'dart:io' as io;

enum TerminalMessageKind { success, warning, error, info, step, skipped }

enum TerminalStatus { ok, warning, error }

enum TerminalColor { red, green, yellow, blue, cyan, gray }

enum TerminalTableCellStyle { normal, muted, command, path, url, value, status }

class TerminalCapabilities {
  const TerminalCapabilities({
    required this.ansi,
    required this.decorated,
    required this.unicode,
  });

  const TerminalCapabilities.plain()
    : ansi = false,
      decorated = false,
      unicode = true;

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

  final bool ansi;
  final bool decorated;
  final bool unicode;
}

class TerminalStyle {
  const TerminalStyle({this.capabilities = const TerminalCapabilities.plain()});

  final TerminalCapabilities capabilities;

  TerminalSymbols get symbols =>
      capabilities.unicode ? TerminalSymbols.unicode : TerminalSymbols.ascii;

  String header(String text) =>
      paint(text, color: TerminalColor.cyan, bold: true);

  String section(String text) => paint(text, bold: true);

  String label(String text) => paint(text, color: TerminalColor.blue);

  String value(String text) => text;

  String command(String text) => paint(text, color: TerminalColor.cyan);

  String path(String text) => text;

  String url(String text) => paint(text, color: TerminalColor.blue);

  String muted(String text) => paint(text, color: TerminalColor.gray);

  String code(String text) => capabilities.ansi ? command(text) : '`$text`';

  String status(TerminalStatus status, String text) {
    final color = switch (status) {
      TerminalStatus.ok => TerminalColor.green,
      TerminalStatus.warning => TerminalColor.yellow,
      TerminalStatus.error => TerminalColor.red,
    };
    return paint(text, color: color);
  }

  String message(TerminalMessageKind kind, String text) {
    if (!capabilities.decorated) {
      return text;
    }

    return '${_messageMarker(kind)} $text';
  }

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

  String _messageMarker(TerminalMessageKind kind) {
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
}

class TerminalOutput {
  const TerminalOutput({
    required void Function(String message) stdout,
    void Function(String message)? stderr,
    void Function(String text)? transient,
    this.style = const TerminalStyle(),
  }) : _stdout = stdout,
       _stderr = stderr ?? stdout,
       _transient = transient;

  final void Function(String message) _stdout;
  final void Function(String message) _stderr;
  final void Function(String text)? _transient;
  final TerminalStyle style;

  void write(String message) {
    _stdout(message);
  }

  void writeError(String message) {
    _stderr(message);
  }

  void blank() {
    _stdout('');
  }

  void heading(String text) {
    _stdout(style.header(text));
  }

  void section(String text) {
    _stdout(style.section(text));
  }

  void success(String message) {
    _stdout(style.message(TerminalMessageKind.success, message));
  }

  void warning(String message) {
    _stdout(style.message(TerminalMessageKind.warning, message));
  }

  void warningError(String message) {
    _stderr(style.message(TerminalMessageKind.warning, message));
  }

  void error(String message) {
    _stderr(style.message(TerminalMessageKind.error, message));
  }

  void failure(String message) {
    _stdout(style.message(TerminalMessageKind.error, message));
  }

  void info(String message) {
    _stdout(style.message(TerminalMessageKind.info, message));
  }

  void step(String message) {
    _stdout(style.message(TerminalMessageKind.step, message));
  }

  void skipped(String message) {
    _stdout(style.message(TerminalMessageKind.skipped, message));
  }

  void next(String message) {
    final prefix = style.capabilities.decorated
        ? '${style.paint(style.symbols.arrow, color: TerminalColor.cyan)} '
        : '';
    _stdout('$prefix$message');
  }

  void detail(String message) {
    final bullet = style.paint(style.symbols.bullet, color: TerminalColor.gray);
    _stdout('    $bullet $message');
  }

  void indented(String message, {int spaces = 2}) {
    _stdout('${' ' * spaces}$message');
  }

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
}

class TerminalTableColumn {
  const TerminalTableColumn(
    this.header, {
    this.style = TerminalTableCellStyle.normal,
    this.alignRight = false,
  });

  final String header;
  final TerminalTableCellStyle style;
  final bool alignRight;
}

class TerminalSymbols {
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

  final String success;
  final String warning;
  final String error;
  final String info;
  final String step;
  final String skipped;
  final String bullet;
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
