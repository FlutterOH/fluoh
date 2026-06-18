part of 'automation_scenario.dart';

/// Parsed Android UIAutomator node used by scenario actions.
class AndroidUiNode {
  /// Creates an Android UI node.
  const AndroidUiNode({
    required this.label,
    required this.bounds,
    this.resourceId,
  });

  /// Text, content description, resource id, or resource id suffix.
  final String label;

  /// Node bounds.
  final AndroidBounds bounds;

  /// Resource id, when exposed by UIAutomator.
  final String? resourceId;
}

/// Android UI node bounds.
class AndroidBounds {
  /// Creates Android UI bounds.
  const AndroidBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Left coordinate.
  final int left;

  /// Top coordinate.
  final int top;

  /// Right coordinate.
  final int right;

  /// Bottom coordinate.
  final int bottom;

  /// Horizontal center coordinate.
  int get centerX => ((left + right) / 2).round();

  /// Vertical center coordinate.
  int get centerY => ((top + bottom) / 2).round();

  /// Whether the node has a non-empty render area.
  bool get hasArea => right > left && bottom > top;

  /// Converts bounds to JSON.
  Map<String, Object?> toJson() {
    return {
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
      'centerX': centerX,
      'centerY': centerY,
    };
  }
}

/// Parses UIAutomator XML into text-addressable nodes.
List<AndroidUiNode> parseAndroidUiNodes(String xml) {
  final nodes = <AndroidUiNode>[];
  for (final match in RegExp(r'<node\b[^>]*>').allMatches(xml)) {
    final attrs = _xmlAttributes(match.group(0)!);
    final bounds = _parseAndroidBounds(attrs['bounds']);
    if (bounds == null) {
      continue;
    }
    final resourceId = _nonEmptyString(attrs['resource-id']);
    final labels = <String>{
      ?_nonEmptyString(attrs['text']),
      ?_nonEmptyString(attrs['content-desc']),
      if (resourceId != null && resourceId.contains('/'))
        resourceId.split('/').last,
      ?resourceId,
    };
    for (final label in labels) {
      nodes.add(
        AndroidUiNode(label: label, bounds: bounds, resourceId: resourceId),
      );
    }
  }
  return nodes;
}

AndroidUiNode? _findAndroidUiNode(
  List<AndroidUiNode> nodes,
  List<String> labels, {
  required String match,
}) {
  for (final label in labels) {
    for (final node in nodes) {
      if (_matches(node.label, label, match)) {
        return node;
      }
    }
  }
  return null;
}

Map<String, String> _xmlAttributes(String source) {
  return {
    for (final match in RegExp(
      r'([a-zA-Z0-9_-]+)="([^"]*)"',
    ).allMatches(source))
      match.group(1)!: _xmlUnescape(match.group(2)!),
  };
}

String _xmlUnescape(String value) {
  return value
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

AndroidBounds? _parseAndroidBounds(String? value) {
  if (value == null) {
    return null;
  }
  final match = RegExp(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]').firstMatch(value);
  if (match == null) {
    return null;
  }
  return AndroidBounds(
    left: int.parse(match.group(1)!),
    top: int.parse(match.group(2)!),
    right: int.parse(match.group(3)!),
    bottom: int.parse(match.group(4)!),
  );
}

/// OHOS UI node parsed from `uitest dumpLayout` JSON.
class OhosUiNode {
  /// Creates an OHOS UI node.
  const OhosUiNode({
    required this.label,
    required this.bounds,
    this.id,
    this.key,
  });

  /// Text, original text, description, id, or key.
  final String label;

  /// Node bounds.
  final OhosBounds bounds;

  /// Component id, when exposed.
  final String? id;

  /// Component key, when exposed.
  final String? key;
}

/// OHOS UI node bounds.
class OhosBounds {
  /// Creates OHOS UI bounds.
  const OhosBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Left coordinate.
  final int left;

  /// Top coordinate.
  final int top;

  /// Right coordinate.
  final int right;

  /// Bottom coordinate.
  final int bottom;

  /// Horizontal center coordinate.
  int get centerX => ((left + right) / 2).round();

  /// Vertical center coordinate.
  int get centerY => ((top + bottom) / 2).round();

  /// Whether the node has a non-empty render area.
  bool get hasArea => right > left && bottom > top;

  /// Converts bounds to JSON.
  Map<String, Object?> toJson() {
    return {
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
      'centerX': centerX,
      'centerY': centerY,
    };
  }
}

/// Parses OHOS `uitest dumpLayout` JSON into text-addressable nodes.
List<OhosUiNode> parseOhosUiNodes(String source) {
  final decoded = jsonDecode(source);
  final nodes = <OhosUiNode>[];

  void visit(Object? value, {bool ancestorVisible = true}) {
    if (value is! Map) {
      return;
    }
    var nodeVisible = ancestorVisible;
    final attributes = value['attributes'];
    if (attributes is Map) {
      final stringAttributes = <String, String>{
        for (final entry in attributes.entries)
          if (entry.key is String && entry.value != null)
            entry.key as String: entry.value.toString(),
      };
      nodeVisible =
          ancestorVisible && _ohosAttributesAreVisible(stringAttributes);
      final bounds = _parseOhosBounds(stringAttributes['bounds']);
      if (bounds != null && bounds.hasArea && nodeVisible) {
        final id = _nonEmptyString(stringAttributes['id']);
        final key = _nonEmptyString(stringAttributes['key']);
        final labels = <String>{
          ?_nonEmptyString(stringAttributes['text']),
          ?_nonEmptyString(stringAttributes['originalText']),
          ?_nonEmptyString(stringAttributes['description']),
          ?id,
          ?key,
        };
        for (final label in labels) {
          nodes.add(OhosUiNode(label: label, bounds: bounds, id: id, key: key));
        }
      }
    }
    final children = value['children'];
    if (children is List) {
      for (final child in children) {
        visit(child, ancestorVisible: nodeVisible);
      }
    }
  }

  visit(decoded);
  return nodes;
}

bool _ohosAttributesAreVisible(Map<String, String> attributes) {
  final visible = attributes['visible']?.trim().toLowerCase();
  if (visible == 'false') {
    return false;
  }
  return true;
}

OhosUiNode? _findOhosUiNode(
  List<OhosUiNode> nodes,
  List<String> labels, {
  required String match,
}) {
  for (final label in labels) {
    for (final node in nodes) {
      if (_matches(node.label, label, match)) {
        return node;
      }
    }
  }
  return null;
}

OhosBounds? _parseOhosBounds(String? value) {
  if (value == null) {
    return null;
  }
  final match = RegExp(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]').firstMatch(value);
  if (match == null) {
    return null;
  }
  return OhosBounds(
    left: int.parse(match.group(1)!),
    top: int.parse(match.group(2)!),
    right: int.parse(match.group(3)!),
    bottom: int.parse(match.group(4)!),
  );
}

String? _nonEmptyString(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
