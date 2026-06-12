part of 'device_runner_test.dart';

void _registerOhosDeviceRunnerLogTests() {
  test('classifies fatal OHOS runtime log lines', () {
    expect(
      classifyOhosRuntimeLog('''
I normal line
E CppCrash Process crashed with SIGSEGV
E app FATAL EXCEPTION: main
'''),
      [
        'E CppCrash Process crashed with SIGSEGV',
        'E app FATAL EXCEPTION: main',
      ],
    );
  });

  test('classifies Flutter plugin channel implementation failures', () {
    expect(
      classifyOhosRuntimeLog('''
W A000ff/Flutter: MethodChannel# --> method not implemented
E flutter: MissingPluginException(No implementation found for method getTemporaryDirectory on channel plugins.flutter.io/path_provider)
'''),
      [
        'W A000ff/Flutter: MethodChannel# --> method not implemented',
        'E flutter: MissingPluginException(No implementation found for method getTemporaryDirectory on channel plugins.flutter.io/path_provider)',
      ],
    );
  });

  test('ignores non-fatal FlutterOH method channel startup noise', () {
    expect(
      classifyOhosRuntimeLog(
        'DartMessenger --> Uncaught exception in binary message listener',
      ),
      isEmpty,
    );
    expect(
      classifyOhosRuntimeLog('''
D A000ff/Flutter: PlatformMethodCallback --> Received 'System.initializationComplete' message.
W A000ff/Flutter: MethodChannel# --> method not implemented
'''),
      isEmpty,
    );
  });
}
