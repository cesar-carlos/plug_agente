import 'package:plug_agente/core/constants/app_strings.dart';

/// Returns true if [args] contain the autostart flag (launch from Windows startup).
bool isAutostartLaunch(List<String> args) => args.contains(AppStrings.singleInstanceArgAutostart);

/// Returns true when [commandLine] contains the autostart flag as a standalone
/// Windows command-line token.
bool containsAutostartLaunchToken(String commandLine) {
  final token = RegExp.escape(AppStrings.singleInstanceArgAutostart);
  return RegExp('(?:^|\\s)(?:"$token"|$token)(?=\\s|\$)').hasMatch(commandLine);
}
