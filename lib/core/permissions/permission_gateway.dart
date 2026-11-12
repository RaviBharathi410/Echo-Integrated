import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Platform-neutral runtime permission gateway so widget tests can mock OS prompts.
abstract interface class PermissionGateway {
  Future<bool> isMicrophoneGranted();
  Future<bool> requestMicrophone();
  Future<bool> isNotificationsGranted();
  Future<bool> requestNotifications();
  Future<void> openSettings();
}

class PermissionHandlerGateway implements PermissionGateway {
  const PermissionHandlerGateway();

  @override
  Future<bool> isMicrophoneGranted() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return false;
    }
    return (await Permission.microphone.status).isGranted;
  }

  @override
  Future<bool> requestMicrophone() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return false;
    }
    return (await Permission.microphone.request()).isGranted;
  }

  @override
  Future<bool> isNotificationsGranted() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return true;
    }
    return (await Permission.notification.status).isGranted;
  }

  @override
  Future<bool> requestNotifications() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return true;
    }
    return (await Permission.notification.request()).isGranted;
  }

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }
}

class FakePermissionGateway implements PermissionGateway {
  FakePermissionGateway({
    this.micGranted = true,
    this.notificationsGranted = true,
  });

  bool micGranted;
  bool notificationsGranted;
  int micRequests = 0;
  int notificationRequests = 0;
  bool openedSettings = false;

  @override
  Future<bool> isMicrophoneGranted() async => micGranted;

  @override
  Future<bool> requestMicrophone() async {
    micRequests++;
    return micGranted;
  }

  @override
  Future<bool> isNotificationsGranted() async => notificationsGranted;

  @override
  Future<bool> requestNotifications() async {
    notificationRequests++;
    return notificationsGranted;
  }

  @override
  Future<void> openSettings() async {
    openedSettings = true;
  }
}

final permissionGatewayProvider = Provider<PermissionGateway>((ref) {
  return const PermissionHandlerGateway();
});
