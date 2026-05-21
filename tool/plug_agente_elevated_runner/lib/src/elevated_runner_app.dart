import 'dart:io';

import 'package:args/args.dart';
import 'package:plug_agente_elevated_runner/src/elevated_contract.dart';
import 'package:plug_agente_elevated_runner/src/elevated_request_processor.dart';

class ElevatedRunnerApp {
  Future<int> run(List<String> arguments) async {
    final parser = ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.')
      ..addOption(
        'watch-requests',
        help: 'Process pending elevated request files under the app data directory, then exit.',
      );

    late final ArgResults results;
    try {
      results = parser.parse(arguments);
    } on FormatException catch (error) {
      stderr.writeln(error.message);
      stderr.writeln(parser.usage);
      return 64;
    }

    if (results.flag('help')) {
      stdout.writeln('Plug Agente elevated action runner helper');
      stdout.writeln(parser.usage);
      return 0;
    }

    final appDirectoryPath = results.option('watch-requests')?.trim();
    if (appDirectoryPath == null || appDirectoryPath.isEmpty) {
      stderr.writeln('Missing required --watch-requests <appDataDirectory>.');
      stderr.writeln(parser.usage);
      return 64;
    }

    if (!Platform.isWindows) {
      stderr.writeln('Elevated runner helper is only supported on Windows.');
      return 1;
    }

    final processor = ElevatedRequestProcessor(appDirectoryPath: appDirectoryPath);
    final deadline = DateTime.now().add(ElevatedContract.idleWaitBeforeExit);

    while (true) {
      final processed = await processor.processPendingRequests();
      if (DateTime.now().isAfter(deadline) && processed == 0) {
        break;
      }
      await Future<void>.delayed(ElevatedContract.pollInterval);
    }

    return 0;
  }
}
