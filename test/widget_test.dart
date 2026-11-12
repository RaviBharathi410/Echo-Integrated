import 'package:echo_hearing/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Scaffold probe invokes native audio engine channel', (
    tester,
  ) async {
    const channel = MethodChannel('com.echo.hearing/audio_control');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getMonitorStreamInfo') {
            return 'Audio stream stopped';
          }
          return null;
        });

    await tester.pumpWidget(const EchoBootstrapApp());
    await tester.pumpAndSettle();

    expect(find.text('ECHO Hearing'), findsOneWidget);
    expect(find.text('Audio stream stopped'), findsOneWidget);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
