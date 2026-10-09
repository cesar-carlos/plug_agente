import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/count_active_client_tokens.dart';
import 'package:plug_agente/application/use_cases/list_client_token_page.dart';
import 'package:plug_agente/application/use_cases/list_client_tokens.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_page.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:result_dart/result_dart.dart';

class _UnusedTokenRepository extends Mock implements IClientTokenRepository {}

class ClientTokenTestPageLoader extends ListClientTokenPage {
  ClientTokenTestPageLoader(this.loader) : super(_UnusedTokenRepository());
  final ListClientTokens loader;

  @override
  Future<Result<ClientTokenPage>> call({required ClientTokenListQuery query}) async {
    return (await loader(query: query)).map(
      (items) => ClientTokenPage(
        items: items.skip(query.offset).take(query.pageSize ?? ClientTokenListQuery.defaultPageSize).toList(),
        page: query.page ?? 1,
        pageSize: query.pageSize ?? ClientTokenListQuery.defaultPageSize,
        totalCount: items.length,
      ),
    );
  }
}

class FixedClientTokenTestCounter extends CountActiveClientTokens {
  FixedClientTokenTestCounter([this.count = 0]) : super(_UnusedTokenRepository());
  final int count;
  @override
  Future<Result<int>> call() async => Success(count);
}
