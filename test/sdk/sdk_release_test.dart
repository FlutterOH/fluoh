import 'package:fluoh/fluoh.dart';
import 'package:test/test.dart';

void main() {
  test('derives an SDK line from an ohos SDK tag', () {
    expect(sdkLineFromTag('3.35.8-ohos-0.0.3'), '3.35');
  });

  test('rejects tags that do not follow the ohos SDK format', () {
    expect(() => sdkLineFromTag('3.35.8'), throwsFormatException);
  });
}
