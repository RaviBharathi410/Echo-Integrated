import 'dart:async';

import 'package:echo_hearing/app/router.dart';
import 'package:echo_hearing/app/theme/echo_theme.dart';
import 'package:echo_hearing/core/audio/audio_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EchoApp extends ConsumerStatefulWidget {
  const EchoApp({super.key});

  @override
  ConsumerState<EchoApp> createState() => _EchoAppState();
}

class _EchoAppState extends ConsumerState<EchoApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onPause: () => _releaseAudio('backgrounded'),
      onHide: () => _releaseAudio('backgrounded'),
      onDetach: () => _releaseAudio('detached'),
    );
  }

  void _releaseAudio(String reason) {
    unawaited(ref.read(audioCoordinatorProvider).releaseAll(reason: reason));
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'ECHO',
      debugShowCheckedModeBanner: false,
      theme: EchoTheme.light(),
      routerConfig: router,
    );
  }
}

