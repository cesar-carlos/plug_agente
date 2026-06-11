import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class WindowConstraints {
  const WindowConstraints._();

  static const double messageModalMinWidth = 520;
  static const double messageModalWidth = 600;
  static const double messageModalMaxHeight = 520;
  static const double messageModalMaxHeightFraction = 0.7;
  static const double messageModalResponsiveBreakpoint = 640;
  static const double messageModalMinViewportWidth = 360;

  static const double destinationDialogMinWidth = 600;
  static const double destinationDialogMaxWidth = 600;
  static const double destinationDialogMaxHeight = 800;

  static const double scheduleDialogMinWidth = 550;
  static const double scheduleDialogMaxWidth = 650;
  static const double scheduleDialogContentMaxHeight = 700;
  static const double scheduleDialogMaxHeight = 750;

  static const double sqlServerConfigMinWidth = 600;
  static const double sqlServerConfigMaxWidth = 600;
  static const double sqlServerConfigMaxHeight = 800;

  static const double sybaseConfigMinWidth = 600;
  static const double sybaseConfigMaxWidth = 600;
  static const double sybaseConfigMaxHeight = 800;

  static const double mainWindowMinWidth = 900;
  static const double mainWindowMinHeight = 650;

  static BoxConstraints getMessageModalConstraints() {
    return const BoxConstraints(
      minWidth: messageModalMinWidth,
      maxWidth: messageModalWidth,
      maxHeight: messageModalMaxHeight,
    );
  }

  static BoxConstraints resolveMessageModalConstraints(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final resolvedMaxWidth = size.width > messageModalResponsiveBreakpoint ? messageModalWidth : size.width * 0.92;
    final maxWidth = math.max(
      messageModalMinViewportWidth,
      math.min(messageModalWidth, resolvedMaxWidth),
    );
    final minWidth = math.min(messageModalMinWidth, maxWidth);
    final maxHeight = math.min(
      messageModalMaxHeight,
      size.height * messageModalMaxHeightFraction,
    );

    return BoxConstraints(
      minWidth: minWidth,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  }

  static BoxConstraints getDestinationDialogConstraints() {
    return const BoxConstraints(
      minWidth: destinationDialogMinWidth,
      maxWidth: destinationDialogMaxWidth,
      maxHeight: destinationDialogMaxHeight,
    );
  }

  static BoxConstraints getScheduleDialogConstraints() {
    return const BoxConstraints(
      minWidth: scheduleDialogMinWidth,
      maxWidth: scheduleDialogMaxWidth,
      maxHeight: scheduleDialogMaxHeight,
    );
  }

  static BoxConstraints getSqlServerConfigConstraints() {
    return const BoxConstraints(
      minWidth: sqlServerConfigMinWidth,
      maxWidth: sqlServerConfigMaxWidth,
      maxHeight: sqlServerConfigMaxHeight,
    );
  }

  static BoxConstraints getSybaseConfigConstraints() {
    return const BoxConstraints(
      minWidth: sybaseConfigMinWidth,
      maxWidth: sybaseConfigMaxWidth,
      maxHeight: sybaseConfigMaxHeight,
    );
  }

  static Size getMainWindowMinSize() {
    return const Size(mainWindowMinWidth, mainWindowMinHeight);
  }
}
