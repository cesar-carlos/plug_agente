import 'package:plug_agente/domain/entities/client_token_summary.dart';

class ClientTokenPage {
  const ClientTokenPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalCount,
  });

  final List<ClientTokenSummary> items;
  final int page;
  final int pageSize;
  final int totalCount;

  int get totalPages => totalCount == 0 ? 1 : (totalCount / pageSize).ceil();
  bool get hasPreviousPage => page > 1;
  bool get hasNextPage => page < totalPages;
}
