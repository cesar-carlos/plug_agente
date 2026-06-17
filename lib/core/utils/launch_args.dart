import 'package:plug_agente/core/constants/launch_args_constants.dart';

/// Returns true if [args] contain the autostart flag (launch from Windows startup).
bool isAutostartLaunch(List<String> args) => args.contains(LaunchArgsConstants.autostartArg);

/// Returns true when [commandLine] contains the autostart flag as a standalone
/// Windows command-line token.
bool containsAutostartLaunchToken(String commandLine) {
  final token = RegExp.escape(LaunchArgsConstants.autostartArg);
  return RegExp('(?:^|\\s)(?:"$token"|$token)(?=\\s|\$)').hasMatch(commandLine);
}
