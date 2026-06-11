import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/presentation/mappers/playground_ui_strings.dart';

final class PlaygroundQuerySession {
  PlaygroundQuerySession({PlaygroundUiStrings? uiStrings}) : _ui = uiStrings ?? PlaygroundUiStrings.english;

  PlaygroundUiStrings _ui;

  static const List<int> pageSizeOptions = [25, 50, 100, 250];

  int _currentPage = 1;
  int _pageSize = 50;
  bool _hasNextPage = false;
  bool _hasExecutedQuery = false;
  bool _paginationAvailable = false;
  int _selectedResultSetIndex = 0;

  int get currentPage => _currentPage;
  int get pageSize => _pageSize;
  bool get hasNextPage => _hasNextPage;
  bool get hasPreviousPage => _currentPage > 1;
  bool get hasExecutedQuery => _hasExecutedQuery;
  bool get paginationAvailable => _paginationAvailable;
  int get selectedResultSetIndex => _selectedResultSetIndex;

  bool hasPagination({required bool isStreaming, required String? error}) {
    return _paginationAvailable && _hasExecutedQuery && !isStreaming && error == null;
  }

  void resetPaginationForQueryChange() {
    _currentPage = 1;
    _hasNextPage = false;
  }

  void resetForClear() {
    _currentPage = 1;
    _hasNextPage = false;
    _hasExecutedQuery = false;
    _paginationAvailable = false;
    _selectedResultSetIndex = 0;
  }

  void markExecuted() {
    _hasExecutedQuery = true;
    _paginationAvailable = true;
  }

  void disablePagination() {
    _paginationAvailable = false;
    _hasNextPage = false;
  }

  void syncFromResponse(QueryPaginationInfo? pagination) {
    if (pagination == null) {
      _hasNextPage = false;
      _paginationAvailable = false;
      return;
    }

    _currentPage = pagination.page;
    _pageSize = pagination.pageSize;
    _hasNextPage = pagination.hasNextPage;
    _paginationAvailable = true;
  }

  void setPageSize(int pageSize) {
    _pageSize = pageSize;
    _currentPage = 1;
    _hasNextPage = false;
  }

  int? advancePage() {
    if (!_hasNextPage) {
      return null;
    }
    return ++_currentPage;
  }

  int? retreatPage() {
    if (_currentPage <= 1) {
      return null;
    }
    return --_currentPage;
  }

  void resetPageForStreaming() {
    _currentPage = 1;
    _hasNextPage = false;
    _paginationAvailable = false;
  }

  bool setSelectedResultSetIndex(int index, int resultSetCount) {
    if (index < 0 || index >= resultSetCount) {
      return false;
    }
    _selectedResultSetIndex = index;
    return true;
  }

  String buildLastExecutionHint({
    required SqlHandlingMode sqlHandlingMode,
    QueryPaginationInfo? pagination,
  }) {
    if (sqlHandlingMode == SqlHandlingMode.preserve) {
      return _ui.queryPlaygroundHintLastRunPreserve;
    }
    if (pagination != null) {
      return _ui.queryPlaygroundHintLastRunManagedPagination;
    }
    return _ui.queryPlaygroundHintLastRunManaged;
  }

  String buildStreamingExecutionHint({required SqlHandlingMode sqlHandlingMode}) {
    if (sqlHandlingMode == SqlHandlingMode.preserve) {
      return _ui.queryPlaygroundHintLastRunPreserve;
    }
    return _ui.queryPlaygroundHintLastRunStreaming;
  }

  void bindUiStrings(PlaygroundUiStrings strings) {
    _ui = strings;
  }
}
