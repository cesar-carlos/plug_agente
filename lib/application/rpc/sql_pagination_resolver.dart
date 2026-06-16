import 'dart:developer' as developer;

import 'package:plug_agente/application/rpc/sql_rpc_negotiated_capabilities.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/utils/json_primitive_coercion.dart';
import 'package:plug_agente/domain/validation/sql_validator.dart';

class ResolvedPagination {
  const ResolvedPagination({
    this.pagination,
    this.errorMessage,
  });

  final QueryPaginationRequest? pagination;
  final String? errorMessage;

  bool get hasError => errorMessage != null;
}

ResolvedPagination resolvePagination(
  Map<String, dynamic> params,
  String sql,
  int negotiatedMaxRows,
  Map<String, dynamic> negotiatedExtensions,
) {
  final options = params['options'] as Map<String, dynamic>?;
  final page = jsonPositiveInt(options?['page']);
  final pageSize = jsonPositiveInt(options?['page_size']);
  final cursor = options?['cursor'] as String?;
  if (page == null && pageSize == null && cursor == null) {
    return const ResolvedPagination();
  }

  if (SqlValidator.queryDeclaresServerSideRowLimit(sql)) {
    return const ResolvedPagination(
      errorMessage:
          'Paginated requests cannot include TOP/LIMIT/OFFSET/FETCH in SQL; '
          'use options.page/page_size or options.cursor',
    );
  }

  final paginationPlanResult = SqlValidator.validatePaginationQuery(sql);
  SqlPaginationPlan? plan;
  if (paginationPlanResult.isSuccess()) {
    plan = paginationPlanResult.getOrNull();
  } else {
    final failure = paginationPlanResult.exceptionOrNull()! as domain.Failure;
    final isMissingOrderBy = failure.message == 'Paginated queries must declare an explicit ORDER BY clause';
    if (cursor != null || !isMissingOrderBy) {
      return ResolvedPagination(errorMessage: failure.message);
    }
  }

  if (cursor != null) {
    final stablePlan = plan;
    if (stablePlan == null) {
      return const ResolvedPagination(
        errorMessage: 'Cursor pagination requires an explicit ORDER BY clause',
      );
    }
    if (page != null || pageSize != null) {
      return const ResolvedPagination(
        errorMessage: 'cursor cannot be combined with page or page_size',
      );
    }
    if (!supportsCursorKeysetPagination(negotiatedExtensions)) {
      return const ResolvedPagination(
        errorMessage: 'Negotiated protocol does not allow cursor pagination',
      );
    }

    try {
      final decodedCursor = QueryPaginationCursor.fromToken(cursor);
      if (decodedCursor.pageSize > negotiatedMaxRows) {
        return ResolvedPagination(
          errorMessage:
              'cursor page_size exceeds negotiated limit: '
              '${decodedCursor.pageSize} > $negotiatedMaxRows',
        );
      }
      if (decodedCursor.isStableCursor) {
        if (decodedCursor.queryHash != stablePlan.queryFingerprint) {
          return const ResolvedPagination(
            errorMessage: 'cursor does not match the SQL query fingerprint',
          );
        }
        if (!orderByMatchesPlan(decodedCursor.orderBy, stablePlan.orderBy)) {
          return const ResolvedPagination(
            errorMessage: 'cursor ordering does not match the SQL ORDER BY',
          );
        }
      }

      return ResolvedPagination(
        pagination: QueryPaginationRequest(
          page: decodedCursor.page,
          pageSize: decodedCursor.pageSize,
          cursor: cursor,
          offset: decodedCursor.offset,
          queryHash: decodedCursor.queryHash ?? stablePlan.queryFingerprint,
          orderBy: stablePlan.orderBy,
          lastRowValues: decodedCursor.lastRowValues,
        ),
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Pagination cursor parsing failed (invalid or malformed)',
        name: 'rpc_method_dispatcher',
        error: e,
        stackTrace: stackTrace,
      );
      return const ResolvedPagination(
        errorMessage: 'cursor is invalid or malformed',
      );
    }
  }

  if (page == null || pageSize == null || page < 1 || pageSize < 1) {
    return const ResolvedPagination(
      errorMessage: 'page and page_size must be provided together and be >= 1',
    );
  }
  if (!supportsPageOffsetPagination(negotiatedExtensions)) {
    return const ResolvedPagination(
      errorMessage: 'Negotiated protocol does not allow page-offset pagination',
    );
  }
  if (pageSize > negotiatedMaxRows) {
    return ResolvedPagination(
      errorMessage:
          'page_size exceeds negotiated limit: '
          '$pageSize > $negotiatedMaxRows',
    );
  }

  return ResolvedPagination(
    pagination: QueryPaginationRequest(
      page: page,
      pageSize: pageSize,
      queryHash: plan?.queryFingerprint,
      orderBy: plan?.orderBy ?? const [],
    ),
  );
}

Map<String, dynamic> buildPaginationResult(QueryPaginationInfo pagination) {
  return {
    'page': pagination.page,
    'page_size': pagination.pageSize,
    'returned_rows': pagination.returnedRows,
    'has_next_page': pagination.hasNextPage,
    'has_previous_page': pagination.hasPreviousPage,
    if (pagination.currentCursor != null) 'current_cursor': pagination.currentCursor,
    if (pagination.nextCursor != null) 'next_cursor': pagination.nextCursor,
  };
}

bool orderByMatchesPlan(
  List<QueryPaginationOrderTerm> cursorOrderBy,
  List<QueryPaginationOrderTerm> planOrderBy,
) {
  if (cursorOrderBy.length != planOrderBy.length) {
    return false;
  }

  for (var i = 0; i < cursorOrderBy.length; i++) {
    final left = cursorOrderBy[i];
    final right = planOrderBy[i];
    if (left.expression != right.expression ||
        left.lookupKey != right.lookupKey ||
        left.descending != right.descending) {
      return false;
    }
  }
  return true;
}
