import 'package:echo_hearing/app/theme/echo_components.dart';
import 'package:flutter/material.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: EchoTopBar(title: 'Listening Reports'),
      body: Center(child: Text('Listening Reports Workspace')),
    );
  }
}
