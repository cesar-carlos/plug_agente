import 'package:plug_agente/domain/repositories/i_action_io_input_pipe.dart';
import 'package:result_dart/result_dart.dart';

/// A suspended, protected process owned until actual native cleanup completes.
abstract interface class IActionIoProcess {
  int get pid;
  IActionIoInputPipe get input;
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<Result<int>> get exitCode;
  Result<Unit> resume();
  Future<Result<Unit>> terminate();

  /// Drain/finalize capture before normal close; this operation terminates the tree.
  Future<Result<Unit>> close();
}
