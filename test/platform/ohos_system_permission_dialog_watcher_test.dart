import 'dart:convert';

import 'package:fluoh/src/platform/ohos/system_permission_dialog_watcher.dart';
import 'package:test/test.dart';

void main() {
  group('parseOhosSystemPermissionDialogPolicy', () {
    test('defaults to disabled only when value is omitted', () {
      expect(
        parseOhosSystemPermissionDialogPolicy(null),
        OhosSystemPermissionDialogPolicy.disabled,
      );
      expect(
        () => parseOhosSystemPermissionDialogPolicy('deny'),
        throwsArgumentError,
      );
    });
  });

  group('detectOhosPermissionDialog', () {
    test('parses OHOS permission dialog title, reason, and allow bounds', () {
      final layout = jsonEncode({
        'attributes': <String, Object?>{},
        'children': [
          {
            'attributes': {
              'id': 'permission_dialog_body',
              'key': 'permission_dialog_body',
              'text': '允许“permission_handler_example”访问你的相机？',
            },
            'children': [
              {
                'attributes': {
                  'id': 'permission_dialog_title',
                  'key': 'permission_dialog_title',
                  'text': '允许“permission_handler_example”访问你的相机？',
                },
                'children': <Object?>[],
              },
              {
                'attributes': {
                  'id': 'permission_dialog_reason0',
                  'key': 'permission_dialog_reason0',
                  'text': 'permission_handler_example',
                },
                'children': <Object?>[],
              },
              {
                'attributes': {
                  'id': 'permission_dialog_allow_button',
                  'key': 'permission_dialog_allow_button',
                  'bounds': '[664,1582][1164,1717]',
                },
                'children': <Object?>[],
              },
            ],
          },
        ],
      });

      final dialog = detectOhosPermissionDialog(layout);

      expect(dialog, isNotNull);
      expect(dialog!.title, '允许“permission_handler_example”访问你的相机？');
      expect(dialog.reason, 'permission_handler_example');
      expect(dialog.allowBounds.centerX, 914);
      expect(dialog.allowBounds.centerY, 1649);
    });

    test('returns null when allow button is absent', () {
      final layout = jsonEncode({
        'attributes': {'id': 'permission_dialog_title', 'text': '允许访问？'},
        'children': <Object?>[],
      });

      expect(detectOhosPermissionDialog(layout), isNull);
    });
  });
}
