part of 'device_runner.dart';

/// Starts a local OpenHarmony emulator.
Future<OhosEmulatorStartResult> startOhosEmulator({
  required FluohEnvironment environment,
  required OhosToolchain toolchain,
  String? emulatorName,
}) async {
  if (!await toolchain.emulator.exists()) {
    throw OhosDeviceException(
      'Could not locate DevEco emulator at ${toolchain.emulator.path}',
    );
  }
  final emulators = await discoverOhosLocalEmulators(environment: environment);
  if (emulators.isEmpty) {
    throw const OhosDeviceException(
      'No local DevEco emulator is deployed. Create one in DevEco Studio '
      'Device Manager first.',
    );
  }
  final requested = emulatorName?.trim();
  final emulator = requested == null || requested.isEmpty
      ? _defaultOhosEmulator(emulators)
      : emulators.where((candidate) => candidate.name == requested).firstOrNull;
  if (emulator == null) {
    throw OhosDeviceException(
      'Local DevEco emulator $requested was not found. Available emulators: '
      '${emulators.map((item) => item.name).join(', ')}',
    );
  }

  final traceName = 'trace_${DateTime.now().millisecondsSinceEpoch}_fluoh';
  final command = [
    toolchain.emulator.path,
    '-hvd',
    emulator.name,
    '-path',
    emulator.deployedRoot.path,
    '-t',
    traceName,
    '-imageRoot',
    emulator.imageRoot.path,
  ];
  await _throwIfOhosEmulatorStorageLow(
    emulator: emulator,
    environment: environment.processEnvironment,
  );
  await io.Process.start(
    command.first,
    command.skip(1).toList(),
    workingDirectory: toolchain.emulator.parent.path,
    mode: io.ProcessStartMode.detached,
  );
  await _throwIfOhosEmulatorStartupFailed(
    emulator: emulator,
    traceName: traceName,
  );
  return OhosEmulatorStartResult(emulator: emulator, command: command);
}

/// Discovers locally deployed OpenHarmony emulators.
Future<List<OhosLocalEmulator>> discoverOhosLocalEmulators({
  required FluohEnvironment environment,
}) async {
  final processEnvironment = environment.processEnvironment;
  final deployedRoot = io.Directory(
    processEnvironment['FLUOH_OHOS_EMULATOR_DEPLOYED']?.trim().isNotEmpty ??
            false
        ? processEnvironment['FLUOH_OHOS_EMULATOR_DEPLOYED']!.trim()
        : '${_userHome(processEnvironment)}/.Huawei/Emulator/deployed',
  );
  final imageRoot = io.Directory(
    processEnvironment['FLUOH_HARMONYOS_SDK_ROOT']?.trim().isNotEmpty ?? false
        ? processEnvironment['FLUOH_HARMONYOS_SDK_ROOT']!.trim()
        : '${_userHome(processEnvironment)}/Library/Huawei/Sdk',
  );
  final listFile = io.File('${deployedRoot.path}/lists.json');
  if (await listFile.exists()) {
    final decoded = jsonDecode(await listFile.readAsString());
    if (decoded is List) {
      final emulators = <OhosLocalEmulator>[];
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final name = item['name']?.toString().trim();
        if (name == null || name.isEmpty) {
          continue;
        }
        final emulatorDirectory = _emulatorDirectoryFromListItem(
          deployedRoot: deployedRoot,
          name: name,
          item: item,
        );
        emulators.add(
          OhosLocalEmulator(
            name: name,
            directory: emulatorDirectory,
            deployedRoot: deployedRoot,
            imageRoot: imageRoot,
            apiVersion:
                _apiVersionFromMap(item) ??
                await _apiVersionFromConfig(emulatorDirectory) ??
                _apiVersionFromName(name),
          ),
        );
      }
      if (emulators.isNotEmpty) {
        return emulators;
      }
    }
  }

  if (!await deployedRoot.exists()) {
    return const [];
  }
  final emulators = <OhosLocalEmulator>[];
  await for (final entity in deployedRoot.list()) {
    if (entity is io.Directory &&
        await io.File('${entity.path}/config.ini').exists()) {
      emulators.add(
        OhosLocalEmulator(
          name: _fileName(entity.path),
          directory: entity,
          deployedRoot: deployedRoot,
          imageRoot: imageRoot,
          apiVersion:
              await _apiVersionFromConfig(entity) ??
              _apiVersionFromName(_fileName(entity.path)),
        ),
      );
    }
  }
  emulators.sort((left, right) => left.name.compareTo(right.name));
  return emulators;
}

Future<void> _throwIfOhosEmulatorStorageLow({
  required OhosLocalEmulator emulator,
  required Map<String, String> environment,
}) async {
  final minimumFreeKb = _ohosEmulatorMinimumFreeKilobytes(environment);
  if (minimumFreeKb <= 0) {
    return;
  }
  final freeKb = await _availableDiskKilobytes(emulator.deployedRoot);
  if (freeKb == null || freeKb >= minimumFreeKb) {
    return;
  }
  throw OhosDeviceException(
    'OHOS emulator could not start because ${emulator.deployedRoot.path} '
    'has only ${_formatKilobytes(freeKb)} free. DevEco requires at least '
    '${_formatKilobytes(minimumFreeKb)} free for this emulator path. Clear '
    'disk space or move the DevEco emulator path, then rerun fluoh run ohos '
    '--emulator <name> --json.',
    code: 'ohos.emulator_start_failed',
    details: {
      'emulator': emulator.name,
      'path': emulator.deployedRoot.path,
      'freeKilobytes': freeKb,
      'minimumFreeKilobytes': minimumFreeKb,
    },
  );
}

int _ohosEmulatorMinimumFreeKilobytes(Map<String, String> environment) {
  final configuredRaw = environment['FLUOH_OHOS_EMULATOR_MIN_FREE_KB']?.trim();
  if (configuredRaw != null && configuredRaw.isNotEmpty) {
    return int.tryParse(configuredRaw) ?? 0;
  }
  final devEco = environment['FLUOH_DEVECO_STUDIO']?.trim();
  if (devEco != null &&
      (devEco.startsWith('/tmp/') || devEco.startsWith('/private/tmp/'))) {
    return 0;
  }
  return 20 * 1024 * 1024;
}

Future<int?> _availableDiskKilobytes(io.Directory directory) async {
  if (io.Platform.isWindows) {
    return null;
  }
  try {
    final result = await io.Process.run('/bin/df', [
      '-Pk',
      directory.path,
    ]).timeout(const Duration(seconds: 2));
    if (result.exitCode != 0) {
      return null;
    }
    final lines = const LineSplitter()
        .convert(result.stdout.toString())
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) {
      return null;
    }
    final parts = lines.last.trim().split(RegExp(r'\s+'));
    if (parts.length < 4) {
      return null;
    }
    return int.tryParse(parts[3]);
  } on Object {
    return null;
  }
}

String _formatKilobytes(int kilobytes) {
  final gibibytes = kilobytes / 1024 / 1024;
  return '${gibibytes.toStringAsFixed(1)} GiB';
}

Future<void> _throwIfOhosEmulatorStartupFailed({
  required OhosLocalEmulator emulator,
  required String traceName,
}) async {
  final log = io.File('${emulator.directory.path}/Log/Emulator.log');
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  String? relevantLog;
  while (!DateTime.now().isAfter(deadline)) {
    if (await log.exists()) {
      final content = await log.readAsString().catchError((_) => '');
      final traceIndex = content.lastIndexOf(traceName);
      if (traceIndex != -1) {
        relevantLog = content.substring(traceIndex);
        final failure = _ohosEmulatorStartupFailure(relevantLog);
        if (failure != null) {
          throw OhosDeviceException(
            failure,
            code: 'ohos.emulator_start_failed',
            details: {
              'emulator': emulator.name,
              'logFile': log.path,
              'trace': traceName,
            },
          );
        }
        if (relevantLog.contains('ShowBootAnimation') ||
            relevantLog.contains('Guest OS Boot Completed')) {
          return;
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  if (relevantLog != null) {
    final failure = _ohosEmulatorStartupFailure(relevantLog);
    if (failure != null) {
      throw OhosDeviceException(
        failure,
        code: 'ohos.emulator_start_failed',
        details: {
          'emulator': emulator.name,
          'logFile': log.path,
          'trace': traceName,
        },
      );
    }
  }
}

String? _ohosEmulatorStartupFailure(String log) {
  if (log.contains('No enough space to start Emulator') ||
      log.contains('请修改模拟器路径或者清理磁盘')) {
    return 'OHOS emulator could not start because the emulator storage path '
        'does not have enough free space. Clear disk space or move the DevEco '
        'emulator path, then rerun fluoh run ohos --emulator <name> --json.';
  }
  return null;
}

Future<Map<String, Object?>> _ohosTargetRecommendationDetails({
  required FluohEnvironment environment,
  required List<OhosDeviceTarget> connectedTargets,
}) async {
  final devices = [
    for (final target in connectedTargets)
      {
        'id': target.id,
        if (target.details != null) 'details': target.details,
        'runArguments': '--device-id ${target.id}',
      },
  ];
  List<OhosLocalEmulator> emulators;
  try {
    emulators = await discoverOhosLocalEmulators(environment: environment);
  } on Object catch (error) {
    return {
      'targetSelection': {
        'policy': 'emulator-first',
        'recommendation':
            'Prefer a local DevEco emulator for repeatable automation. '
            'Emulator discovery failed; run fluoh emulators --platform ohos '
            '--json for details, then fall back to a connected device if '
            'needed.',
        if (devices.isNotEmpty) 'devices': devices,
        'emulatorDiscoveryError': error.toString(),
      },
    };
  }

  if (emulators.isEmpty) {
    return {
      'targetSelection': {
        'policy': 'emulator-first',
        'recommendation': devices.isNotEmpty
            ? 'No local DevEco emulator is available. Use a connected OHOS '
                  'device as a fallback, or create a DevEco emulator and '
                  'rerun with --auto-emulator.'
            : 'No local DevEco emulator or connected OHOS device is available. '
                  'Create a DevEco emulator and rerun with --auto-emulator.',
        'emulators': const [],
        if (devices.isNotEmpty) 'devices': devices,
      },
    };
  }

  final suggested = _suggestedOhosEmulators(emulators);
  return {
    'targetSelection': {
      'policy': 'emulator-first',
      'recommendation': suggested.length > 1
          ? 'Prefer repeatable local DevEco emulator coverage. Run both the '
                'lowest and highest API version emulators for compatibility; '
                'use connected real devices only when no emulator is available.'
          : 'Prefer the available local DevEco emulator for repeatable '
                'automation; use connected real devices only when no emulator '
                'is available.',
      'emulators': emulators.map(_emulatorSuggestionJson).toList(),
      'suggestedEmulators': suggested.map(_emulatorSuggestionJson).toList(),
      'suggestedRunArguments': [
        '--auto-emulator',
        for (final emulator in suggested) '--emulator ${emulator.name}',
      ],
      if (devices.isNotEmpty) 'devices': devices,
    },
  };
}

List<OhosLocalEmulator> _suggestedOhosEmulators(
  List<OhosLocalEmulator> emulators,
) {
  if (emulators.length <= 1) {
    return emulators;
  }
  final withApi =
      [
        for (final emulator in emulators)
          if (emulator.apiVersion != null) emulator,
      ]..sort((left, right) {
        final apiCompare = left.apiVersion!.compareTo(right.apiVersion!);
        return apiCompare != 0 ? apiCompare : left.name.compareTo(right.name);
      });
  if (withApi.length >= 2 &&
      withApi.first.apiVersion != withApi.last.apiVersion) {
    return [withApi.first, withApi.last];
  }
  final sorted = [...emulators]
    ..sort((left, right) => left.name.compareTo(right.name));
  return [sorted.first, sorted.last];
}

OhosLocalEmulator _defaultOhosEmulator(List<OhosLocalEmulator> emulators) {
  final withApi =
      [
        for (final emulator in emulators)
          if (emulator.apiVersion != null) emulator,
      ]..sort((left, right) {
        final apiCompare = right.apiVersion!.compareTo(left.apiVersion!);
        return apiCompare != 0 ? apiCompare : left.name.compareTo(right.name);
      });
  if (withApi.isNotEmpty) {
    return withApi.first;
  }
  final sorted = [...emulators]
    ..sort((left, right) => left.name.compareTo(right.name));
  return sorted.first;
}

Map<String, Object?> _emulatorSuggestionJson(OhosLocalEmulator emulator) {
  return {
    'name': emulator.name,
    if (emulator.apiVersion != null) 'apiVersion': emulator.apiVersion,
    'runArguments': '--emulator ${emulator.name}',
  };
}

io.Directory _emulatorDirectoryFromListItem({
  required io.Directory deployedRoot,
  required String name,
  required Map<Object?, Object?> item,
}) {
  final rawPath = item['path']?.toString().trim();
  if (rawPath != null && rawPath.isNotEmpty) {
    final path = rawPath.startsWith('/')
        ? rawPath
        : '${deployedRoot.path}/$rawPath';
    return io.Directory(path);
  }
  return io.Directory('${deployedRoot.path}/$name');
}

int? _apiVersionFromMap(Map<Object?, Object?> item) {
  for (final key in const [
    'apiVersion',
    'apiLevel',
    'api',
    'sdkApiVersion',
    'sdkVersion',
    'systemApiVersion',
    'systemVersion',
    'version',
  ]) {
    final version = _firstInteger(item[key]);
    if (version != null) {
      return version;
    }
  }
  return null;
}

Future<int?> _apiVersionFromConfig(io.Directory emulatorDirectory) async {
  final config = io.File('${emulatorDirectory.path}/config.ini');
  if (!await config.exists()) {
    return null;
  }
  try {
    final content = await config.readAsString();
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || !line.contains('=')) {
        continue;
      }
      final separator = line.indexOf('=');
      final key = line.substring(0, separator).trim().toLowerCase();
      if (!const {
        'apiversion',
        'apilevel',
        'api',
        'sdkapiversion',
        'sdkversion',
        'systemapiversion',
        'systemversion',
        'version',
      }.contains(key)) {
        continue;
      }
      final version = _firstInteger(line.substring(separator + 1));
      if (version != null) {
        return version;
      }
    }
  } on Object {
    return null;
  }
  return null;
}

int? _apiVersionFromName(String name) {
  final match = RegExp(
    r'(?:api|openharmony|harmonyos)[-_ ]*(\d+)',
    caseSensitive: false,
  ).firstMatch(name);
  return match == null ? null : int.tryParse(match.group(1)!);
}

int? _firstInteger(Object? value) {
  final text = value?.toString();
  if (text == null || text.trim().isEmpty) {
    return null;
  }
  final match = RegExp(r'\d+').firstMatch(text);
  return match == null ? null : int.tryParse(match.group(0)!);
}
