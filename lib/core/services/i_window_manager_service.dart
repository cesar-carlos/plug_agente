import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:result_dart/result_dart.dart';

/// Native visibility, independent of Flutter's focus-based lifecycle events.
abstract interface class IWindowRenderActivity {
  ValueListenable<bool> get renderingEnabled;
}

abstract class IWindowManagerService {
  Future<void> show();
  Future<Result<Unit>> setMinimizeToTray({required bool value});
  Future<Result<Unit>> setCloseToTray({required bool value});
}

abstract interface class IDesktopWindowService implements IWindowManagerService {
  Future<void> initialize({
    ui.Size? size,
    ui.Size? minimumSize,
    bool center = true,
    String? title,
    bool startMinimized = false,
  });

  Future<void> close();
  Future<bool> isVisible();
}
