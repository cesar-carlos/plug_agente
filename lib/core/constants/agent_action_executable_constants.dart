/// Limits and allowlists for `AgentActionType.executable` actions.
abstract final class AgentActionExecutableConstants {
  static const Set<String> allowedExecutableExtensions = <String>{
    '.exe',
    '.bat',
    '.cmd',
  };

  static const int maxArguments = 64;

  static const int maxArgumentLength = 8192;

  static const String invalidArgumentsReason = 'invalid_arguments';

  static const String argumentTooLongReason = 'argument_too_long';

  static const String tooManyArgumentsReason = 'too_many_arguments';

  static const String invalidArgumentCharactersReason = 'invalid_argument_characters';
}
