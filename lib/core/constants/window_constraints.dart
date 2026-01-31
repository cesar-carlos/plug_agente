import 'package:flutter/widgets.dart';

class WindowConstraints {
  const WindowConstraints._();

  static const double messageModalWidth = 600;

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
