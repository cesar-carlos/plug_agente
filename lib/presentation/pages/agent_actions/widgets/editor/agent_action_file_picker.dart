import 'package:file_picker/file_picker.dart';

/// Adapter exposing a single async file picker call. Lets the editor
/// avoid 12 near-identical `_pick*Path` methods that all wrap
/// `FilePicker.platform.pickFiles` in the same try/catch boilerplate,
/// and lets tests swap the picker without touching the platform plugin.
class AgentActionFilePicker {
  const AgentActionFilePicker();

  /// Returns the absolute path of the single file the user picked, or
  /// `null` when the dialog was cancelled. Throws when the platform
  /// surface fails (caller is expected to translate the exception into
  /// a user-friendly message).
  Future<String?> pickSingleFile({
    required String dialogTitle,
    required List<String> allowedExtensions,
  }) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      dialogTitle: dialogTitle,
    );
    return picked?.files.singleOrNull?.path;
  }
}
