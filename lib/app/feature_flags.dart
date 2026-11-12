import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Controls visibility of illustrative/sample data banners and the DEV SIM drawer.
///
/// In release builds ([kReleaseMode]), demo data is strictly disabled so users
/// always see genuine empty states instead of placeholder charts or records.
class DemoDataNotifier extends Notifier<bool> {
  @override
  bool build() => kDebugMode && !kReleaseMode;

  void setEnabled(bool value) {
    if (kReleaseMode) {
      state = false;
      return;
    }
    state = value;
  }

  void toggle() => setEnabled(!state);
}

final demoDataEnabledProvider = NotifierProvider<DemoDataNotifier, bool>(
  DemoDataNotifier.new,
);
