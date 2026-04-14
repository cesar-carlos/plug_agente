import 'package:plug_agente/application/validation/query_validation_messages.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

/// Localized strings for `PlaygroundProvider` (no `BuildContext`).
class PlaygroundUiStrings {
  const PlaygroundUiStrings({
    required this.queryValidationEmpty,
    required this.queryValidationConnectionStringEmpty,
    required this.queryConnectionTesting,
    required this.queryConnectionSuccess,
    required this.queryConnectionFailure,
    required this.queryCancelledByUser,
    required this.queryStreamingErrorPrefix,
    required this.queryExecuteUnexpectedError,
    required this.queryPlaygroundHintLastRunPreserve,
    required this.queryPlaygroundHintLastRunManagedPagination,
    required this.queryPlaygroundHintLastRunManaged,
    required this.queryPlaygroundHintLastRunStreaming,
    required this.streamingRowCapHint,
  });

  factory PlaygroundUiStrings.fromL10n(AppLocalizations l) {
    return PlaygroundUiStrings(
      queryValidationEmpty: l.queryValidationEmpty,
      queryValidationConnectionStringEmpty: l.queryValidationConnectionStringEmpty,
      queryConnectionTesting: l.queryConnectionTesting,
      queryConnectionSuccess: l.queryConnectionSuccess,
      queryConnectionFailure: l.queryConnectionFailure,
      queryCancelledByUser: l.queryCancelledByUser,
      queryStreamingErrorPrefix: l.queryStreamingErrorPrefix,
      queryExecuteUnexpectedError: l.queryExecuteUnexpectedError,
      queryPlaygroundHintLastRunPreserve: l.queryPlaygroundHintLastRunPreserve,
      queryPlaygroundHintLastRunManagedPagination: l.queryPlaygroundHintLastRunManagedPagination,
      queryPlaygroundHintLastRunManaged: l.queryPlaygroundHintLastRunManaged,
      queryPlaygroundHintLastRunStreaming: l.queryPlaygroundHintLastRunStreaming,
      streamingRowCapHint: l.queryPlaygroundStreamingRowCapHint,
    );
  }

  final String queryValidationEmpty;
  final String queryValidationConnectionStringEmpty;
  final String queryConnectionTesting;
  final String queryConnectionSuccess;
  final String queryConnectionFailure;
  final String queryCancelledByUser;
  final String queryStreamingErrorPrefix;
  final String queryExecuteUnexpectedError;
  final String queryPlaygroundHintLastRunPreserve;
  final String queryPlaygroundHintLastRunManagedPagination;
  final String queryPlaygroundHintLastRunManaged;
  final String queryPlaygroundHintLastRunStreaming;
  final String Function(int max) streamingRowCapHint;

  /// Default for tests; matches English ARB and `QueryValidationMessages`.
  static final PlaygroundUiStrings english = PlaygroundUiStrings(
    queryValidationEmpty: QueryValidationMessages.queryCannotBeEmpty,
    queryValidationConnectionStringEmpty: QueryValidationMessages.connectionStringCannotBeEmpty,
    queryConnectionTesting: 'Testing connection...',
    queryConnectionSuccess: 'Connection established successfully',
    queryConnectionFailure: 'Connection failed',
    queryCancelledByUser: 'Query cancelled by user',
    queryStreamingErrorPrefix: 'Streaming error',
    queryExecuteUnexpectedError: 'Failed to execute the query',
    queryPlaygroundHintLastRunPreserve: 'Last run: SQL preserved (no pagination rewrite by the agent).',
    queryPlaygroundHintLastRunManagedPagination:
        'Last run: managed pagination — SQL may have been rewritten for your database dialect.',
    queryPlaygroundHintLastRunManaged: 'Last run: managed mode — agent limits and adjustments may apply to the SQL.',
    queryPlaygroundHintLastRunStreaming: 'Last run: streaming mode — results received as a continuous stream.',
    streamingRowCapHint: (int max) =>
        'Display limited to $max rows in streaming (memory). The server query was stopped when this limit was reached.',
  );
}
