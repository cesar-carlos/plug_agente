/// Limits and stable reasons for `AgentActionType.comObject` actions.
abstract final class AgentActionComObjectConstants {
  static const int maxProgIdLength = 128;

  static const int maxMemberNameLength = 128;

  static const int maxArgumentEntries = 32;

  static const int maxArgumentKeyLength = 128;

  static const int maxStringArgumentLength = 8192;

  static const String invalidProgIdReason = 'invalid_prog_id';

  static const String invalidMemberNameReason = 'invalid_member_name';

  static const String invocationNotRegisteredReason = 'com_object_invocation_not_registered';

  static const String invalidArgumentsReason = 'invalid_com_object_arguments';

  static const String unsupportedPlatformReason = 'com_object_unsupported_platform';

  static const String invocationFailedReason = 'com_object_invocation_failed';
}
