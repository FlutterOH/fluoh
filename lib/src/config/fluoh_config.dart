import 'dart:convert';
import 'dart:io';

import '../context/fluoh_environment.dart';
import '../schema/schema.dart';

export '../schema/schema.dart'
    show
        SourceConfig,
        ToolConfig,
        defaultSourceName,
        defaultSourcePriority,
        defaultSourceUrl,
        defaultSourceUrlEnvironmentKey,
        sourceNameValidationError;

typedef FluohConfig = ToolConfig;

class FluohConfigStore {
  const FluohConfigStore(this.environment);

  final FluohEnvironment environment;

  Future<FluohConfig> load() async {
    final file = environment.configFile;
    if (!await file.exists()) {
      final config = _defaultConfig(environment);
      await save(config);
      return config;
    }

    return _readConfigFile(file);
  }

  Future<FluohConfig?> loadIfExists() async {
    final file = environment.configFile;
    if (!await file.exists()) {
      return null;
    }
    return _readConfigFile(file);
  }

  Future<void> save(FluohConfig config) async {
    await environment.homeDirectory.create(recursive: true);
    await environment.configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
  }

  Future<FluohConfig> _readConfigFile(File file) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException catch (error) {
      throw FormatException('fluoh config could not be read: ${error.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('fluoh config must be a JSON object.');
    }
    return ToolConfig.fromJson(decoded);
  }
}

FluohConfig _defaultConfig(FluohEnvironment environment) {
  return ToolConfig(
    sources: {
      defaultSourceName: SourceConfig(
        path: '${environment.homeDirectory.path}/sources/flutteroh',
        url:
            environment.processEnvironment[defaultSourceUrlEnvironmentKey] ??
            defaultSourceUrl,
        priority: officialSourcePriority,
      ),
    },
  );
}
