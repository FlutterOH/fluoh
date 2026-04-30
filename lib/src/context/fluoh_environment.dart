import 'dart:io';

class FluohEnvironment {
  const FluohEnvironment({
    required this.homeDirectory,
    required this.workingDirectory,
    this.processEnvironment = const <String, String>{},
  });

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

  final Directory homeDirectory;
  final Directory workingDirectory;
  final Map<String, String> processEnvironment;

  Directory get sdksDirectory => Directory('${homeDirectory.path}/sdks');

  File get configFile => File('${homeDirectory.path}/config.json');

  File get currentSdkFile => File('${homeDirectory.path}/current-sdk');
}
