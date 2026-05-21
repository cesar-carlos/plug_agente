/// Limits and stable reasons for `AgentActionType.email` actions.
abstract final class AgentActionEmailConstants {
  static const int maxSmtpProfileIdLength = 128;

  static const int maxSubjectLength = 998;

  static const int maxBodyLength = 512 * 1024;

  static const int maxRecipientsPerList = 50;

  static const int maxAttachments = 10;

  static const int maxAttachmentBytesPerFile = 10 * 1024 * 1024;

  static const int maxTotalAttachmentBytes = 25 * 1024 * 1024;

  static const Set<String> allowedAttachmentExtensions = <String>{
    '.pdf',
    '.txt',
    '.csv',
    '.json',
    '.xml',
    '.zip',
    '.7z',
    '.log',
    '.html',
    '.htm',
  };

  static const String invalidEmailAddressReason = 'invalid_email_address';

  static const String invalidSmtpProfileReason = 'invalid_smtp_profile';

  static const String smtpProfileNotFoundReason = 'smtp_profile_not_found';

  static const String smtpSendFailedReason = 'smtp_send_failed';

  static const String unresolvedTemplateTokenReason = 'unresolved_template_token';

  static const String tooManyRecipientsReason = 'too_many_recipients';

  static const String tooManyAttachmentsReason = 'too_many_attachments';

  static const String attachmentTooLargeReason = 'attachment_too_large';

  static const String totalAttachmentsTooLargeReason = 'total_attachments_too_large';

  static const String subjectTooLongReason = 'subject_too_long';

  static const String bodyTooLongReason = 'body_too_long';
}
