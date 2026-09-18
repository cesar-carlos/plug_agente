/// Bounds for the Windows `cmd.exe /C` command-line action.
abstract final class AgentActionCommandLineConstants {
  /// `cmd.exe` accepts at most 8,191 characters, including its command line.
  static const int maxCommandCharacters = 8191;

  static const String invalidCommandCharactersReason = 'invalid_command_characters';

  static const String commandTooLongReason = 'command_too_long';

  static const String contextPathPlaceholder = r'${context_path}';
  static const String contextPlaceholderRequiredReason = 'command_context_placeholder_required';
  static const String contextPlaceholderInvalidReason = 'command_context_placeholder_invalid';
  static const String secretPlaceholderForbiddenReason = 'command_secret_placeholder_forbidden';
  static const String localOnlyReason = 'command_line_local_only';
  static const String processTreeAttachFailedReason = 'process_tree_attach_failed';
}
