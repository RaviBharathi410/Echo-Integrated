import 'package:echo_hearing/app/theme/echo_components.dart';
import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: EchoTopBar(title: 'Profile & Settings'),
      body: Center(child: Text('Profile & Settings Workspace')),
    );
  }
}
