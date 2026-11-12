import 'package:echo_hearing/app/theme/echo_components.dart';
import 'package:flutter/material.dart';

class MonitorScreen extends StatelessWidget {
  const MonitorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: EchoTopBar(title: 'Sound Monitoring'),
      body: Center(child: Text('Sound Monitoring Workspace')),
    );
  }
}
