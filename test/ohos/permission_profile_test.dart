import 'dart:io';

import 'package:fluoh/src/ohos/permission_profile.dart';
import 'package:test/test.dart';

void main() {
  test(
    'reads bundle name and restricted permission APL from OHOS project',
    () async {
      final temp = await Directory.systemTemp.createTemp('fluoh_permission_');
      addTearDown(() => temp.delete(recursive: true));
      final ohos = Directory('${temp.path}/ohos');
      final sdk = Directory('${temp.path}/sdk');
      await Directory('${ohos.path}/AppScope').create(recursive: true);
      await Directory('${ohos.path}/entry/src/main').create(recursive: true);
      await Directory(
        '${sdk.path}/previewer/common/resources',
      ).create(recursive: true);
      await File('${ohos.path}/AppScope/app.json5').writeAsString('''
{
  "app": {
    "bundleName": "com.example.camera"
  }
}
''');
      await File('${ohos.path}/entry/src/main/module.json5').writeAsString('''
{
  "module": {
    "requestPermissions": [
      {"name": "ohos.permission.INTERNET"},
      {"name": "ohos.permission.READ_IMAGEVIDEO"},
      {"name": "ohos.permission.WRITE_IMAGEVIDEO"}
    ]
  }
}
''');
      await File(
        '${sdk.path}/previewer/common/resources/module.json',
      ).writeAsString('''
{
  "definePermissions": [
    {
      "name": "ohos.permission.INTERNET",
      "availableLevel": "normal",
      "provisionEnable": false
    },
    {
      "name": "ohos.permission.READ_IMAGEVIDEO",
      "availableLevel": "system_basic",
      "provisionEnable": true
    },
    {
      "name": "ohos.permission.WRITE_IMAGEVIDEO",
      "availableLevel": "system_basic",
      "provisionEnable": true
    }
  ]
}
''');

      final profile = await readOhosPermissionProfile(
        ohosDirectory: ohos,
        openHarmonySdk: sdk,
      );

      expect(profile.bundleName, 'com.example.camera');
      expect(profile.requestedPermissions, [
        'ohos.permission.INTERNET',
        'ohos.permission.READ_IMAGEVIDEO',
        'ohos.permission.WRITE_IMAGEVIDEO',
      ]);
      expect(profile.restrictedPermissions, [
        'ohos.permission.READ_IMAGEVIDEO',
        'ohos.permission.WRITE_IMAGEVIDEO',
      ]);
      expect(profile.apl, 'system_basic');
    },
  );

  test('ignores ohosTest module permissions', () async {
    final temp = await Directory.systemTemp.createTemp('fluoh_permission_');
    addTearDown(() => temp.delete(recursive: true));
    final ohos = Directory('${temp.path}/ohos');
    await Directory('${ohos.path}/entry/src/main').create(recursive: true);
    await Directory('${ohos.path}/ohosTest/src/main').create(recursive: true);
    await File('${ohos.path}/entry/src/main/module.json5').writeAsString('''
{
  "module": {
    "requestPermissions": [
      {"name": "ohos.permission.INTERNET"}
    ]
  }
}
''');
    await File('${ohos.path}/ohosTest/src/main/module.json5').writeAsString('''
{
  "module": {
    "requestPermissions": [
      {"name": "ohos.permission.TEST_ONLY"}
    ]
  }
}
''');

    final permissions = await readRequestedOhosPermissions(ohos);

    expect(permissions, ['ohos.permission.INTERNET']);
  });

  test('only reads permissions from requestPermissions arrays', () async {
    final temp = await Directory.systemTemp.createTemp('fluoh_permission_');
    addTearDown(() => temp.delete(recursive: true));
    final ohos = Directory('${temp.path}/ohos');
    await Directory('${ohos.path}/entry/src/main').create(recursive: true);
    await File('${ohos.path}/entry/src/main/module.json5').writeAsString('''
{
  "module": {
    "name": "entry",
    "metadata": [
      {"name": "ohos.permission.NOT_REQUESTED"}
    ],
    "requestPermissions": [
      {"name": "ohos.permission.INTERNET"}
    ]
  }
}
''');

    final permissions = await readRequestedOhosPermissions(ohos);

    expect(permissions, ['ohos.permission.INTERNET']);
  });
}
