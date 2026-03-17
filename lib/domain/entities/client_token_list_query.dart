enum ClientTokenStatusFilter {
  all,
  active,
  revoked,
}

enum ClientTokenSortOption {
  newest,
  oldest,
  clientAsc,
  clientDesc,
}

class ClientTokenListQuery {
  const ClientTokenListQuery({
    this.clientIdContains = '',
    this.status = ClientTokenStatusFilter.all,
    this.sort = ClientTokenSortOption.newest,
    this.page,
    this.pageSize,
  });

  final String clientIdContains;
  final ClientTokenStatusFilter status;
  final ClientTokenSortOption sort;
  final int? page;
  final int? pageSize;

  bool get hasPagination =>
      page != null && pageSize != null && page! > 0 && pageSize! > 0;

  int get offset => hasPagination ? (page! - 1) * pageSize! : 0;
}
