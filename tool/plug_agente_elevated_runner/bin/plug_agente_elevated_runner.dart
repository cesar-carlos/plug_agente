import 'dart:io';

import 'package:plug_agente_elevated_runner/src/elevated_runner_app.dart';

Future<void> main(List<String> arguments) async {
  final exitCode = await ElevatedRunnerApp().run(arguments);
  exit(exitCode);
}
