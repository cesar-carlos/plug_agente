import 'package:flutter/widgets.dart';

class WindowConstraints {
  const WindowConstraints._();

  static const double messageModalWidth = 600.0;

  static const double destinationDialogMinWidth = 600.0;
  static const double destinationDialogMaxWidth = 600.0;
  static const double destinationDialogMaxHeight = 800.0;

  static const double scheduleDialogMinWidth = 550.0;
  static const double scheduleDialogMaxWidth = 650.0;
  static const double scheduleDialogContentMaxHeight = 700.0;
  static const double scheduleDialogMaxHeight = 750.0;

  static const double sqlServerConfigMinWidth = 600.0;
  static const double sqlServerConfigMaxWidth = 600.0;
  static const double sqlServerConfigMaxHeight = 800.0;

  static const double sybaseConfigMinWidth = 600.0;
  static const double sybaseConfigMaxWidth = 600.0;
  static const double sybaseConfigMaxHeight = 800.0;

  static const double mainWindowMinWidth = 900.0;
  static const double mainWindowMinHeight = 650.0;

  static BoxConstraints getDestinationDialogConstraints() {
    return BoxConstraints(
      minWidth: destinationDialogMinWidth,
      maxWidth: destinationDialogMaxWidth,
      maxHeight: destinationDialogMaxHeight,
    );
  }

  static BoxConstraints getScheduleDialogConstraints() {
    return BoxConstraints(
      minWidth: scheduleDialogMinWidth,
      maxWidth: scheduleDialogMaxWidth,
      maxHeight: scheduleDialogMaxHeight,
    );
  }

  static BoxConstraints getSqlServerConfigConstraints() {
    return BoxConstraints(
      minWidth: sqlServerConfigMinWidth,
      maxWidth: sqlServerConfigMaxWidth,
      maxHeight: sqlServerConfigMaxHeight,
    );
  }

  static BoxConstraints getSybaseConfigConstraints() {
    return BoxConstraints(
      minWidth: sybaseConfigMinWidth,
      maxWidth: sybaseConfigMaxWidth,
      maxHeight: sybaseConfigMaxHeight,
    );
  }

  static Size getMainWindowMinSize() {
    return const Size(mainWindowMinWidth, mainWindowMinHeight);
  }
}

