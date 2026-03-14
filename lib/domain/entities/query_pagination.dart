import 'dart:convert';

class QueryPaginationOrderTerm {
  const QueryPaginationOrderTerm({
    required this.expression,
    required this.lookupKey,
    this.descending = false,
  });

  factory QueryPaginationOrderTerm.fromJson(Map<String, dynamic> json) {
    return QueryPaginationOrderTerm(
      expression: json['expression'] as String,
      lookupKey: json['lookup_key'] as String,
      descending: json['descending'] as bool? ?? false,
    );
  }

  final String expression;
  final String lookupKey;
  final bool descending;

  Map<String, dynamic> toJson() {
    return {
      'expression': expression,
      'lookup_key': lookupKey,
      'descending': descending,
    };
  }
}

class QueryPaginationCursor {
  const QueryPaginationCursor({
    required this.page,
    required this.pageSize,
    this.offset,
    this.queryHash,
    this.orderBy = const [],
    this.lastRowValues = const [],
  });

  factory QueryPaginationCursor.fromToken(String token) {
    final normalized = base64.normalize(token);
    final decoded = utf8.decode(base64Url.decode(normalized));
    final json = jsonDecode(decoded) as Map<String, dynamic>;
    final version = json['v'] as int? ?? 1;
    return QueryPaginationCursor(
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
      offset: json['offset'] as int?,
      queryHash: json['query_hash'] as String?,
      orderBy: version >= 2
          ? (json['order_by'] as List<dynamic>? ?? const [])
                .map(
                  (term) => QueryPaginationOrderTerm.fromJson(
                    term as Map<String, dynamic>,
                  ),
                )
                .toList()
          : const [],
      lastRowValues: version >= 2
          ? (json['last_row_values'] as List<dynamic>? ?? const []).toList()
          : const [],
    );
  }

  final int page;
  final int pageSize;
  final int? offset;
  final String? queryHash;
  final List<QueryPaginationOrderTerm> orderBy;
  final List<dynamic> lastRowValues;

  bool get isLegacyOffsetCursor => offset != null && queryHash == null;
  bool get isStableCursor =>
      queryHash != null &&
      orderBy.isNotEmpty &&
      lastRowValues.length == orderBy.length;

  String toToken() {
    final encoded = jsonEncode({
      'v': isStableCursor ? 2 : 1,
      if (offset != null) 'offset': offset,
      'page': page,
      'page_size': pageSize,
      if (queryHash != null) 'query_hash': queryHash,
      if (orderBy.isNotEmpty)
        'order_by': orderBy.map((term) => term.toJson()).toList(),
      if (lastRowValues.isNotEmpty) 'last_row_values': lastRowValues,
    });
    return base64Url.encode(utf8.encode(encoded)).replaceAll('=', '');
  }
}

class QueryPaginationRequest {
  const QueryPaginationRequest({
    required this.page,
    required this.pageSize,
    this.cursor,
    this.queryHash,
    this.orderBy = const [],
    this.lastRowValues = const [],
    int? offset,
  }) : assert(page >= 1, 'page must be >= 1'),
       assert(pageSize >= 1, 'pageSize must be >= 1'),
       _offset = offset;

  final int page;
  final int pageSize;
  final String? cursor;
  final String? queryHash;
  final List<QueryPaginationOrderTerm> orderBy;
  final List<dynamic> lastRowValues;
  final int? _offset;

  bool get isCursorMode => cursor != null;
  bool get usesStableCursor =>
      isCursorMode &&
      queryHash != null &&
      orderBy.isNotEmpty &&
      lastRowValues.length == orderBy.length;

  int get offset => _offset ?? (page - 1) * pageSize;

  int get fetchSizeWithLookAhead => pageSize + 1;
}

class QueryPaginationInfo {
  const QueryPaginationInfo({
    required this.page,
    required this.pageSize,
    required this.returnedRows,
    required this.hasNextPage,
    required this.hasPreviousPage,
    this.currentCursor,
    this.nextCursor,
  }) : assert(page >= 1, 'page must be >= 1'),
       assert(pageSize >= 1, 'pageSize must be >= 1'),
       assert(returnedRows >= 0, 'returnedRows must be >= 0');

  final int page;
  final int pageSize;
  final int returnedRows;
  final bool hasNextPage;
  final bool hasPreviousPage;
  final String? currentCursor;
  final String? nextCursor;
}
