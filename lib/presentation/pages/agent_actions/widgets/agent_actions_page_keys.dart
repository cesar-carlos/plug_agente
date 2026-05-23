import 'package:flutter/widgets.dart';

abstract final class AgentActionsPageKeys {
  static const ValueKey<String> detailScroll = ValueKey<String>('agent_actions_detail_scroll');
  static const ValueKey<String> testPreview = ValueKey<String>('agent_actions_test_preview');
  static const ValueKey<String> remoteReapprovalInfoBar = ValueKey<String>('agent_actions_remote_reapproval_info_bar');
  static const ValueKey<String> developerConnectionMissingInfoBar = ValueKey<String>(
    'agent_actions_developer_connection_missing_info_bar',
  );
  static const ValueKey<String> developerConnectionUnknownInfoBar = ValueKey<String>(
    'agent_actions_developer_connection_unknown_info_bar',
  );
  static const ValueKey<String> developerConnectionChangedInfoBar = ValueKey<String>(
    'agent_actions_developer_connection_changed_info_bar',
  );

  static ValueKey<String> executionSupportCopyButton(String executionId) {
    return ValueKey<String>('execution_support_copy_button_$executionId');
  }
}
