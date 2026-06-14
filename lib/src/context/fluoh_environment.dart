import 'dart:io';

/// Runtime directories and environment variables used by a `fluoh` invocation.
///
/// Commands receive this object instead of reading global process state
/// directly. Tests can therefore point the tool at temporary homes,
/// repositories, and mocked process environments without touching a real
/// `$HOME/.fluoh` installation.
class FluohEnvironment {
  /// Creates an environment rooted at explicit directories.
  const FluohEnvironment({
    required this.homeDirectory,
    required this.workingDirectory,
    this.processEnvironment = const <String, String>{},
  });

  /// Creates an environment from [Platform.environment] and [Directory.current].
  ///
  /// `FLUOH_HOME` overrides the default state directory. When it is not
  /// set, `fluoh` stores runtime state under `$HOME/.fluoh`.
  factory FluohEnvironment.current({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final home = env['FLUOH_HOME'];
    final userHome = env['HOME'];

    return FluohEnvironment(
      homeDirectory: Directory(
        home ??
            (userHome == null || userHome.isEmpty
                ? '.fluoh'
                : '$userHome/.fluoh'),
      ),
      workingDirectory: Directory.current,
      processEnvironment: env,
    );
  }

  /// Directory for persistent fluoh state such as SDKs, source snapshots, and
  /// the user config file.
  final Directory homeDirectory;

  /// Directory where the command was invoked.
  final Directory workingDirectory;

  /// Process environment visible to commands and child processes.
  final Map<String, String> processEnvironment;

  /// Directory containing cached FlutterOH SDK installations.
  Directory get sdksDirectory => Directory('${homeDirectory.path}/sdks');

  /// Directory containing project-local fluoh state.
  Directory get projectFluohDirectory =>
      Directory('${workingDirectory.path}/.fluoh');

  /// Directory containing project-local cleanable runtime artifacts.
  Directory get projectCacheDirectory =>
      Directory('${projectFluohDirectory.path}/cache');

  /// Directory containing generated OHOS debug signing material.
  Directory get ohosSigningDirectory =>
      Directory('${projectCacheDirectory.path}/ohos-signing');

  /// Directory containing run-smoke output logs.
  Directory get packageRunsDirectory =>
      Directory('${projectCacheDirectory.path}/package-runs');

  /// User-level fluoh configuration file.
  File get configFile => File('${homeDirectory.path}/config.json');

  /// Merged, validated Source lock used by dependency and SDK commands.
  File get sourcesLockFile => File('${homeDirectory.path}/sources.lock.json');
}
