import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/platform/download_file.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('native export passes authenticated bytes to document picker', () async {
    final bytes = Uint8List.fromList([37, 80, 68, 70]);
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'save');
      expect(call.arguments['fileName'], 'evidence.pdf');
      expect(call.arguments['bytes'], bytes);
      return 'content://documents/evidence.pdf';
    });
    expect(
      await downloadFile(bytes, 'evidence.pdf', 'application/pdf'),
      isTrue,
    );
  });

  test(
    'cancelling native save is not reported as a successful export',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      expect(
        await downloadFile(Uint8List(1), 'result.csv', 'text/csv'),
        isFalse,
      );
    },
  );

  test('native storage error reaches the screen error handler', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'save_failed',
        message: 'Storage unavailable',
      );
    });
    await expectLater(
      downloadFile(Uint8List(1), 'result.csv', 'text/csv'),
      throwsA(isA<PlatformException>()),
    );
  });
}
