import 'dart:io';

import 'package:fluoh/src/platform/ohos/build_profile_signing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'injects temporary signing config and restores original content',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'fluoh_build_profile_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final ohos = Directory('${temp.path}/ohos');
      await ohos.create(recursive: true);
      final buildProfile = File('${ohos.path}/build-profile.json5');
      const original = '''
{
  "app": {
    "signingConfigs": [],
    "products": [
      {
        "name": "default",
        "signingConfig": "default",
        "compatibleSdkVersion": "5.1.0(18)",
      }
    ]
  }
}
''';
      await buildProfile.writeAsString(original);

      final session = await applyTemporaryOhosSigning(
        ohosDirectory: ohos,
        config: const OhosDebugSigningConfig(
          storeFile: '/tmp/app-keypair.p12',
          storePassword: 'fluoh-debug-signing-password-00001',
          keyAlias: 'fluoh_debug',
          keyPassword: 'fluoh-debug-signing-password-00001',
          signAlg: 'SHA256withECDSA',
          profile: '/tmp/debug-profile.p7b',
          certpath: '/tmp/app-cert-chain.cer',
        ),
      );

      final patched = await buildProfile.readAsString();
      expect(patched, contains('"signingConfigs": ['));
      expect(patched, contains('"storeFile": "/tmp/app-keypair.p12"'));
      expect(patched, contains('"profile": "/tmp/debug-profile.p7b"'));
      expect(patched, contains('"certpath": "/tmp/app-cert-chain.cer"'));

      await session.restore();
      expect(await buildProfile.readAsString(), original);
      await session.restore();
      expect(await buildProfile.readAsString(), original);
    },
  );

  test(
    'adds default product signingConfig when generated project omits it',
    () {
      const original = '''
{
  "app": {
    "signingConfigs": [],
    "products": [
      {
        "name": "default",
        "compatibleSdkVersion": "5.1.0(18)",
      }
    ]
  }
}
''';

      final patched = buildProfileWithTemporaryOhosSigning(
        original,
        const OhosDebugSigningConfig(
          storeFile: '/tmp/app-keypair.p12',
          storePassword: 'fluoh-debug-signing-password-00001',
          keyAlias: 'fluoh_debug',
          keyPassword: 'fluoh-debug-signing-password-00001',
          signAlg: 'SHA256withECDSA',
          profile: '/tmp/debug-profile.p7b',
          certpath: '/tmp/app-cert-chain.cer',
        ),
      );

      expect(patched, contains('"signingConfig": "default"'));
    },
  );

  test('rewrites product signingConfig references to generated config', () {
    const original = '''
{
  "app": {
    "signingConfigs": [
      {
        "name": "release",
        "type": "HarmonyOS"
      }
    ],
    "products": [
      {
        "name": "default",
        "signingConfig": "release",
        "compatibleSdkVersion": "5.1.0(18)",
      },
      {
        "name": "demo",
        "signingConfig": "demo",
        "compatibleSdkVersion": "5.1.0(18)",
      }
    ]
  }
}
''';

    final patched = buildProfileWithTemporaryOhosSigning(
      original,
      const OhosDebugSigningConfig(
        storeFile: '/tmp/app-keypair.p12',
        storePassword: 'fluoh-debug-signing-password-00001',
        keyAlias: 'fluoh_debug',
        keyPassword: 'fluoh-debug-signing-password-00001',
        signAlg: 'SHA256withECDSA',
        profile: '/tmp/debug-profile.p7b',
        certpath: '/tmp/app-cert-chain.cer',
      ),
    );

    expect(
      RegExp(r'"signingConfig"\s*:\s*"default"').allMatches(patched),
      hasLength(2),
    );
    expect(patched, isNot(contains('"signingConfig": "release"')));
    expect(patched, isNot(contains('"signingConfig": "demo"')));
  });
}
