part of 'platform_environment.dart';

/// Parses `adb devices -l` output.
List<PlatformTarget> parseAdbDevices(String output) {
  final targets = <PlatformTarget>[];
  for (final rawLine in const LineSplitter().convert(output)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('List of devices')) {
      continue;
    }
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 2) {
      continue;
    }
    final id = parts.first;
    final state = parts[1];
    targets.add(
      PlatformTarget(
        platform: FluohPlatform.android,
        id: id,
        name: _androidDeviceName(parts.skip(2).toList(), id),
        kind: id.startsWith('emulator-') ? 'emulator' : 'device',
        state: state,
        details: {'raw': line},
      ),
    );
  }
  return targets;
}

/// Parses `xcrun simctl list devices --json` output.
List<PlatformTarget> parseSimctlDevices(
  String output, {
  bool onlyBooted = false,
}) {
  final decoded = jsonDecode(output);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Expected simctl JSON object.');
  }
  final devices = decoded['devices'];
  if (devices is! Map) {
    return const [];
  }
  final targets = <PlatformTarget>[];
  for (final entry in devices.entries) {
    final runtime = entry.key.toString();
    final list = entry.value;
    if (list is! List) {
      continue;
    }
    for (final item in list) {
      if (item is! Map) {
        continue;
      }
      final id = item['udid']?.toString() ?? '';
      final name = item['name']?.toString() ?? id;
      if (id.isEmpty) {
        continue;
      }
      final state = item['state']?.toString();
      if (onlyBooted && state != 'Booted') {
        continue;
      }
      targets.add(
        PlatformTarget(
          platform: FluohPlatform.ios,
          id: id,
          name: name,
          kind: 'emulator',
          state: state,
          details: {
            'runtime': runtime,
            if (item.containsKey('isAvailable'))
              'isAvailable': item['isAvailable'],
          },
        ),
      );
    }
  }
  targets.sort((left, right) => left.name.compareTo(right.name));
  return targets;
}

/// Parses `xcrun devicectl list devices` JSON output.
List<PlatformTarget> parseDevicectlDevices(String output) {
  final decoded = jsonDecode(output);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Expected devicectl JSON object.');
  }
  final result = decoded['result'];
  final devicesObject = result is Map ? result['devices'] : decoded['devices'];
  if (devicesObject is! List) {
    return const [];
  }
  final targets = <PlatformTarget>[];
  for (final device in devicesObject) {
    if (device is! Map) {
      continue;
    }
    final hardware = _objectMap(device['hardwareProperties']);
    final properties = _objectMap(device['deviceProperties']);
    final connection = _objectMap(device['connectionProperties']);
    final platform = _stringValue(hardware['platform'])?.toLowerCase();
    if (platform != null &&
        !platform.contains('ios') &&
        !platform.contains('ipados')) {
      continue;
    }
    final identifier = _stringValue(device['identifier']);
    final udid = _stringValue(hardware['udid']);
    final id = udid ?? identifier ?? '';
    if (id.isEmpty) {
      continue;
    }
    final name =
        _stringValue(properties['name']) ??
        _stringValue(hardware['marketingName']) ??
        id;
    targets.add(
      PlatformTarget(
        platform: FluohPlatform.ios,
        id: id,
        name: name,
        kind: 'device',
        details: {
          'source': 'devicectl',
          if (_stringValue(hardware['platform']) != null)
            'platform': _stringValue(hardware['platform']),
          'devicectlIdentifier': ?identifier,
          'udid': ?udid,
          'aliases': _uniqueNonEmptyStrings([identifier, udid]),
          if (_stringValue(properties['osVersionNumber']) != null)
            'osVersion': _stringValue(properties['osVersionNumber']),
          if (_stringValue(hardware['marketingName']) != null)
            'model': _stringValue(hardware['marketingName']),
          if (_stringValue(connection['transportType']) != null)
            'transport': _stringValue(connection['transportType']),
          if (_stringValue(connection['pairingState']) != null)
            'pairingState': _stringValue(connection['pairingState']),
          if (_stringValue(connection['tunnelState']) != null)
            'tunnelState': _stringValue(connection['tunnelState']),
        },
      ),
    );
  }
  targets.sort((left, right) => left.name.compareTo(right.name));
  return targets;
}

/// Parses `xcrun xcdevice list --timeout` JSON output.
List<PlatformTarget> parseXcdeviceDevices(String output) {
  final decoded = _decodeJsonOutput(output);
  final devicesObject = switch (decoded) {
    List<Object?> list => list,
    Map<Object?, Object?> map when map['devices'] is List => map['devices'],
    _ => const <Object?>[],
  };
  if (devicesObject is! List) {
    return const [];
  }

  final targets = <PlatformTarget>[];
  for (final device in devicesObject) {
    if (device is! Map) {
      continue;
    }
    if (_isTruthy(device['simulator']) || _isTruthy(device['ignored'])) {
      continue;
    }
    if (_isFalsey(device['available'])) {
      continue;
    }
    final platformName = _stringValue(device['platform']);
    final platform = platformName?.toLowerCase();
    if (platform != null &&
        (platform.contains('simulator') || !_isIosDevicePlatform(platform))) {
      continue;
    }

    final identifier = _stringValue(device['identifier']);
    final udid = _stringValue(device['udid']);
    final id = udid ?? identifier ?? '';
    if (id.isEmpty) {
      continue;
    }
    final name =
        _stringValue(device['name']) ?? _stringValue(device['modelName']) ?? id;
    final osVersion =
        _stringValue(device['operatingSystemVersion']) ??
        _stringValue(device['osVersion']);
    final model = _stringValue(device['modelName']);
    final transport =
        _stringValue(device['interface']) ??
        _stringValue(device['transport']) ??
        _stringValue(device['connectionType']);
    targets.add(
      PlatformTarget(
        platform: FluohPlatform.ios,
        id: id,
        name: name,
        kind: 'device',
        details: {
          'source': 'xcdevice',
          'platform': ?platformName,
          'identifier': ?identifier,
          'udid': ?udid,
          'aliases': _uniqueNonEmptyStrings([identifier, udid]),
          'osVersion': ?osVersion,
          'model': ?model,
          'transport': ?transport,
        },
      ),
    );
  }
  targets.sort((left, right) => left.name.compareTo(right.name));
  return targets;
}

/// Parses `xcrun xctrace list devices` text output.
List<PlatformTarget> parseXctraceDevices(String output) {
  final targets = <PlatformTarget>[];
  var inDevicesSection = false;
  for (final rawLine in const LineSplitter().convert(output)) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.startsWith('==')) {
      inDevicesSection = line == '== Devices ==';
      continue;
    }
    if (!inDevicesSection) {
      continue;
    }
    final match = RegExp(r'^(.+?) \(([^()]+)\) \(([^()]+)\)$').firstMatch(line);
    if (match == null) {
      continue;
    }
    final version = match.group(2) ?? '';
    if (!RegExp(r'^\d+(?:\.\d+)*$').hasMatch(version)) {
      continue;
    }
    final id = match.group(3) ?? '';
    if (id.isEmpty) {
      continue;
    }
    targets.add(
      PlatformTarget(
        platform: FluohPlatform.ios,
        id: id,
        name: match.group(1) ?? id,
        kind: 'device',
        details: {'source': 'xctrace', 'osVersion': version},
      ),
    );
  }
  targets.sort((left, right) => left.name.compareTo(right.name));
  return targets;
}

void _addUniqueTargets(
  List<PlatformTarget> targets,
  Iterable<PlatformTarget> additions,
) {
  final ids = {
    for (final target in targets) '${target.platform.cliName}:${target.id}',
  };
  for (final target in additions) {
    final duplicateIndex = targets.indexWhere(
      (existing) => _samePhysicalIosDevice(existing, target),
    );
    if (duplicateIndex != -1) {
      final duplicate = targets[duplicateIndex];
      final merged = _mergePhysicalIosDevice(duplicate, target);
      if (merged.id != duplicate.id) {
        ids.remove('${duplicate.platform.cliName}:${duplicate.id}');
        ids.add('${merged.platform.cliName}:${merged.id}');
      }
      targets[duplicateIndex] = merged;
      continue;
    }
    if (ids.add('${target.platform.cliName}:${target.id}')) {
      targets.add(target);
    }
  }
}

bool _samePhysicalIosDevice(PlatformTarget left, PlatformTarget right) {
  if (left.platform != FluohPlatform.ios ||
      right.platform != FluohPlatform.ios ||
      left.kind != 'device' ||
      right.kind != 'device') {
    return false;
  }
  if (left.name.trim().toLowerCase() != right.name.trim().toLowerCase()) {
    return false;
  }
  final leftVersion = left.details['osVersion']?.toString();
  final rightVersion = right.details['osVersion']?.toString();
  if (_nonEmpty(leftVersion) &&
      _nonEmpty(rightVersion) &&
      _comparableOsVersion(leftVersion!) !=
          _comparableOsVersion(rightVersion!)) {
    return false;
  }
  final leftModel = left.details['model']?.toString();
  final rightModel = right.details['model']?.toString();
  if (_nonEmpty(leftModel) &&
      _nonEmpty(rightModel) &&
      leftModel != rightModel) {
    return false;
  }
  return true;
}

bool _hasConnectionDetails(PlatformTarget target) {
  return target.details.containsKey('transport') ||
      target.details.containsKey('pairingState') ||
      target.details.containsKey('tunnelState');
}

PlatformTarget _mergePhysicalIosDevice(
  PlatformTarget existing,
  PlatformTarget incoming,
) {
  final base =
      _hasConnectionDetails(incoming) && !_hasConnectionDetails(existing)
      ? incoming
      : existing;
  final secondary = identical(base, incoming) ? existing : incoming;
  final details = <String, Object?>{...secondary.details, ...base.details};
  final aliases = _uniqueNonEmptyStrings([
    ..._stringList(secondary.details['aliases']),
    ..._stringList(base.details['aliases']),
    existing.id,
    incoming.id,
  ]);
  if (aliases.isNotEmpty) {
    details['aliases'] = aliases;
  }
  final osVersion = _richerOsVersion(
    existing.details['osVersion']?.toString(),
    incoming.details['osVersion']?.toString(),
  );
  if (osVersion != null) {
    details['osVersion'] = osVersion;
  }
  return PlatformTarget(
    platform: base.platform,
    id: base.id,
    name: base.name,
    kind: base.kind,
    state: base.state ?? secondary.state,
    details: details,
  );
}

List<String> _stringList(Object? value) {
  if (value is Iterable) {
    return [
      for (final item in value)
        if (_nonEmpty(item?.toString())) item.toString().trim(),
    ];
  }
  return const [];
}

List<String> _uniqueNonEmptyStrings(Iterable<String?> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty || !seen.add(trimmed)) {
      continue;
    }
    result.add(trimmed);
  }
  return result;
}

String? _richerOsVersion(String? left, String? right) {
  if (!_nonEmpty(left)) {
    return _nonEmpty(right) ? right!.trim() : null;
  }
  if (!_nonEmpty(right)) {
    return left!.trim();
  }
  final leftValue = left!.trim();
  final rightValue = right!.trim();
  final leftHasBuild = RegExp(
    r'\([^)]*\)|\s+[A-Za-z0-9]{4,}$',
  ).hasMatch(leftValue);
  final rightHasBuild = RegExp(
    r'\([^)]*\)|\s+[A-Za-z0-9]{4,}$',
  ).hasMatch(rightValue);
  if (rightHasBuild && !leftHasBuild) {
    return rightValue;
  }
  return leftValue;
}

String _comparableOsVersion(String value) {
  return value
      .replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '')
      .trim()
      .toLowerCase();
}
