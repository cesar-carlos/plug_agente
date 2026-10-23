import 'dart:io';

import 'package:plug_agente_elevated_runner/src/elevated_bundled_sqlite.dart';
import 'package:plug_agente_elevated_runner/src/elevated_runner_app.dart';

Future<void> main(List<String> arguments) async {
  try {
    loadPackagedSqlite();
  } on Object catch (error) {
    stderr.writeln('Unable to load the bundled elevated-helper SQLite: $error');
    exit(78);
  }
  final exitCode = await ElevatedRunnerApp().run(arguments);
  exit(exitCode);
}
