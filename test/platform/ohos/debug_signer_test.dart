import 'package:fluoh/src/platform/ohos/debug_signer.dart';
import 'package:test/test.dart';

void main() {
  test('password material generator matches Hvigor root key derivation', () {
    expect(
      debugSigningPasswordMaterialScriptForTesting,
      contains(
        'const rootMaterialText = Buffer.from(rootMaterial).toString();',
      ),
    );
    expect(
      debugSigningPasswordMaterialScriptForTesting,
      isNot(contains('new Int8Array(rootMaterial.buffer')),
    );
  });
}
