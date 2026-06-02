import 'dart:io' as io;

import 'package:args/command_runner.dart';

/// Resolved OpenHarmony toolchain paths from DevEco Studio.
class OhosToolchain {
  /// Creates an OHOS toolchain descriptor.
  const OhosToolchain({
    required this.devEcoStudio,
    required this.openHarmonySdk,
    required this.hapSignTool,
    required this.openHarmonyKeyStore,
    required this.openHarmonyProfileDebug,
    required this.java,
    required this.keytool,
    required this.node,
    required this.hdc,
    required this.emulator,
  });

  /// DevEco Studio application directory.
  final io.Directory devEcoStudio;

  /// OpenHarmony SDK directory.
  final io.Directory openHarmonySdk;

  /// HAP signing tool JAR.
  final io.File hapSignTool;

  /// OpenHarmony root keystore.
  final io.File openHarmonyKeyStore;

  /// Debug profile signing certificate.
  final io.File openHarmonyProfileDebug;

  /// Java executable bundled with DevEco Studio.
  final io.File java;

  /// Keytool executable bundled with DevEco Studio.
  final io.File keytool;

  /// Node executable bundled with DevEco Studio.
  final io.File node;

  /// hdc executable.
  final io.File hdc;

  /// OpenHarmony emulator executable.
  final io.File emulator;
}

/// Locates the OpenHarmony SDK toolchain from environment or standard paths.
Future<OhosToolchain> locateOhosToolchain({
  required Map<String, String> environment,
  String usage = '',
}) async {
  final configured = environment['FLUOH_DEVECO_STUDIO']?.trim();
  final candidates = configured != null && configured.isNotEmpty
      ? [configured]
      : [if (io.Platform.isMacOS) '/Applications/DevEco-Studio.app'];

  for (final candidate in candidates) {
    final devEco = io.Directory(candidate);
    final openHarmonySdk = io.Directory(
      '${devEco.path}/Contents/sdk/default/openharmony',
    );
    final toolchains = io.Directory('${openHarmonySdk.path}/toolchains');
    final lib = io.Directory('${toolchains.path}/lib');
    final jbr = io.Directory('${devEco.path}/Contents/jbr/Contents/Home/bin');
    final toolchain = OhosToolchain(
      devEcoStudio: devEco,
      openHarmonySdk: openHarmonySdk,
      hapSignTool: io.File('${lib.path}/hap-sign-tool.jar'),
      openHarmonyKeyStore: io.File('${lib.path}/OpenHarmony.p12'),
      openHarmonyProfileDebug: io.File(
        '${lib.path}/OpenHarmonyProfileDebug.pem',
      ),
      java: io.File('${jbr.path}/java'),
      keytool: io.File('${jbr.path}/keytool'),
      node: io.File('${devEco.path}/Contents/tools/node/bin/node'),
      hdc: io.File('${toolchains.path}/hdc'),
      emulator: io.File('${devEco.path}/Contents/tools/emulator/Emulator'),
    );
    if (await _isComplete(toolchain)) {
      return toolchain;
    }
  }

  throw UsageException(
    'Could not locate the OpenHarmony SDK toolchain. '
    'Install DevEco Studio or set FLUOH_DEVECO_STUDIO to its .app path.',
    usage,
  );
}

Future<bool> _isComplete(OhosToolchain toolchain) async {
  return toolchain.devEcoStudio.existsSync() &&
      await toolchain.openHarmonySdk.exists() &&
      await toolchain.hapSignTool.exists() &&
      await toolchain.openHarmonyKeyStore.exists() &&
      await toolchain.openHarmonyProfileDebug.exists() &&
      await toolchain.java.exists() &&
      await toolchain.keytool.exists() &&
      await toolchain.node.exists() &&
      await toolchain.hdc.exists();
}
