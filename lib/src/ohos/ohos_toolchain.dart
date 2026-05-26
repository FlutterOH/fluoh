import 'dart:io' as io;

import 'package:args/command_runner.dart';

class OhosToolchain {
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

  final io.Directory devEcoStudio;
  final io.Directory openHarmonySdk;
  final io.File hapSignTool;
  final io.File openHarmonyKeyStore;
  final io.File openHarmonyProfileDebug;
  final io.File java;
  final io.File keytool;
  final io.File node;
  final io.File hdc;
  final io.File emulator;
}

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
    'Could not locate DevEco Studio OpenHarmony signing tools. '
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
