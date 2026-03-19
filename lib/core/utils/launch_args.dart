import 'package:plug_agente/core/constants/app_strings.dart';

/// Returns true if [args] contain the autostart flag (launch from Windows startup).
bool isAutostartLaunch(List<String> args) => args.contains(AppStrings.singleInstanceArgAutostart);
