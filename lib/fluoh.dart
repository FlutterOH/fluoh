/// Public entry points for embedding or testing the `fluoh` command runner.
///
/// Most users interact with `fluoh` through the executable in `bin/fluoh.dart`.
/// The exported API is intentionally small so tests, tools, and package
/// maintainers can run commands with an isolated [FluohEnvironment] and inspect
/// Source or SDK data models without depending on private implementation files.
library;

export 'src/cli/fluoh_command_runner.dart';
export 'src/context/fluoh_environment.dart';
export 'src/sdk/sdk_release.dart';
export 'src/source/source_index.dart';
export 'src/version.dart';
