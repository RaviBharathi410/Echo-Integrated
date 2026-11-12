import 'package:echo_hearing/app/theme/echo_components.dart';
import 'package:flutter/material.dart';

class ScreeningShellScreen extends StatelessWidget {
  const ScreeningShellScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: EchoTopBar(title: 'Hearing Screening'),
      body: Center(child: Text('Hearing Screening Workspace')),
    );
  }
}
