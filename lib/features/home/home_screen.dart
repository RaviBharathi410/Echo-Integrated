import 'package:echo_hearing/app/theme/echo_components.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: EchoTopBar(title: 'ECHO'),
      body: Center(child: Text('Home Overview')),
    );
  }
}
