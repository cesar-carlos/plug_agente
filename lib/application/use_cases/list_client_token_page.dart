import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_page.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:result_dart/result_dart.dart';

class ListClientTokenPage {
  ListClientTokenPage(this._repository);

  final IClientTokenRepository _repository;

  Future<Result<ClientTokenPage>> call({required ClientTokenListQuery query}) {
    final page = query.page ?? 1;
    final pageSize = query.pageSize ?? ClientTokenListQuery.defaultPageSize;
    if (page < 1 || !ClientTokenListQuery.supportedPageSizes.contains(pageSize)) {
      return Future.value(Failure(domain.ValidationFailure('Invalid client token page')));
    }
    return _repository.listTokenPage(
      query: query.copyWith(page: page, pageSize: pageSize),
    );
  }
}
