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
    final json = jsonDecode(decoded);
    if (json is! Map<String, dynamic>) throw const FormatException('Invalid cursor object');
    final version = json['v'] ?? 1;
    final page = json['page'];
    final pageSize = json['page_size'];
    final offset = json['offset'];
    final queryHash = json['query_hash'];
    if (version is! int || (version != 1 && version != 2)) {
      throw const FormatException('Unsupported cursor version');
    }
    if (page is! int ||
        pageSize is! int ||
        (offset != null && offset is! int) ||
        (queryHash != null && queryHash is! String)) {
      throw const FormatException('Invalid cursor field types');
    }
    if (!QueryPaginationRequest.hasValidBounds(page, pageSize, offset: offset as int?)) {
      throw const FormatException('Invalid cursor pagination bounds');
    }
    final orderBy = <QueryPaginationOrderTerm>[];
    final lastRowValues = <dynamic>[];
    if (version == 2) {
      final terms = json['order_by'];
      final values = json['last_row_values'];
      if (queryHash is! String ||
          queryHash.isEmpty ||
          terms is! List ||
          terms.isEmpty ||
          values is! List ||
          values.length != terms.length) {
        throw const FormatException('Invalid stable cursor');
      }
      for (final term in terms) {
        if (term is! Map<String, dynamic> ||
            term['expression'] is! String ||
            term['lookup_key'] is! String ||
            (term['descending'] != null && term['descending'] is! bool)) {
          throw const FormatException('Invalid cursor ordering');
        }
        final order = QueryPaginationOrderTerm.fromJson(term);
        if (order.expression.isEmpty || order.lookupKey.isEmpty) {
          throw const FormatException('Invalid cursor ordering');
        }
        orderBy.add(order);
      }
      for (final value in values) {
        if (!(value is String || value is bool || (value is num && value.isFinite))) {
          throw const FormatException('Invalid cursor key value');
        }
        lastRowValues.add(value);
      }
    }
    return QueryPaginationCursor(
      page: page,
      pageSize: pageSize,
      offset: offset,
      queryHash: queryHash as String?,
      orderBy: orderBy,
      lastRowValues: lastRowValues,
    );
  }

  final int page;
  final int pageSize;
  final int? offset;
  final String? queryHash;
  final List<QueryPaginationOrderTerm> orderBy;
  final List<dynamic> lastRowValues;

  bool get isLegacyOffsetCursor => offset != null && queryHash == null;
  bool get isStableCursor => queryHash != null && orderBy.isNotEmpty && lastRowValues.length == orderBy.length;

  String toToken() {
    final encoded = jsonEncode({
      'v': isStableCursor ? 2 : 1,
      if (offset != null) 'offset': offset,
      'page': page,
      'page_size': pageSize,
      if (queryHash != null) 'query_hash': queryHash,
      if (orderBy.isNotEmpty) 'order_by': orderBy.map((term) => term.toJson()).toList(),
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

  // Leave room for look-ahead, end offsets and the next page on native Dart.
  static const int _maxNativeInteger = 0x7fffffffffffffff;

  static bool hasValidBounds(int page, int pageSize, {int? offset}) {
    if (page < 1 || page >= _maxNativeInteger || pageSize < 1 || pageSize >= _maxNativeInteger) return false;
    final maxOffset = _maxNativeInteger - pageSize - 1;
    if (offset != null) return offset >= 0 && offset <= maxOffset;
    return page - 1 <= maxOffset ~/ pageSize;
  }

  final int page;
  final int pageSize;
  final String? cursor;
  final String? queryHash;
  final List<QueryPaginationOrderTerm> orderBy;
  final List<dynamic> lastRowValues;
  final int? _offset;

  bool get isCursorMode => cursor != null;
  bool get usesStableCursor =>
      isCursorMode && queryHash != null && orderBy.isNotEmpty && lastRowValues.length == orderBy.length;

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
