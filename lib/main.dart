import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const EchoBootstrapApp());
}

class EchoBootstrapApp extends StatelessWidget {
  const EchoBootstrapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ECHO',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      home: const _NativeEngineProbeScreen(),
    );
  }
}

class _NativeEngineProbeScreen extends StatefulWidget {
  const _NativeEngineProbeScreen();

  @override
  State<_NativeEngineProbeScreen> createState() =>
      _NativeEngineProbeScreenState();
}

class _NativeEngineProbeScreenState extends State<_NativeEngineProbeScreen> {
  static const _control = MethodChannel('com.echo.hearing/audio_control');
  String _status = 'Checking native Oboe audio engine...';

  @override
  void initState() {
    super.initState();
    _probeNativeEngine();
  }

  Future<void> _probeNativeEngine() async {
    try {
      final info = await _control.invokeMethod<String>('getMonitorStreamInfo');
      if (!mounted) return;
      setState(() {
        _status = info ?? 'Audio stream stopped';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Native probe error: ${e.message}';
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        _status = 'Native audio plugin unavailable on this platform.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ECHO Hearing',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(_status, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
