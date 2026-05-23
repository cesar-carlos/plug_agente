/// Stable `failure.context['reason']` for path and context file validation in `ActionPathValidator`.
abstract final class AgentActionPathContextConstants {
  static const String invalidPathReason = 'invalid_path';

  static const String directoryNotFoundReason = 'directory_not_found';

  static const String workingDirectoryNotAllowedReason = 'working_directory_not_allowed';

  static const String contextExtensionNotAllowedReason = 'context_extension_not_allowed';

  static const String contextFileNotFoundReason = 'context_file_not_found';

  static const String contextFileNotAllowedReason = 'context_file_not_allowed';

  static const String contextFileTooLargeReason = 'context_file_too_large';

  static const String invalidContextJsonReason = 'invalid_context_json';

  static const String invalidContextJsonSchemaReason = 'invalid_context_json_schema';

  static const String pathChangedAfterSaveReason = 'path_changed_after_save';

  static const String pathContentChangedAfterSaveReason = 'path_content_changed_after_save';

  static const String fileNotFoundReason = 'file_not_found';

  static const String fileExtensionNotAllowedReason = 'file_extension_not_allowed';

  static const String fileNotAllowedReason = 'file_not_allowed';

  static const String pathPermissionDeniedReason = 'path_permission_denied';

  static const String pathExecutePermissionDeniedReason = 'path_execute_permission_denied';

  static const String pathLaunchProbeFailedReason = 'path_launch_probe_failed';

  static const String productionPathAllowlistRequiredReason = 'production_path_allowlist_required';
}
