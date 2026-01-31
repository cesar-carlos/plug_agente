import 'package:result_dart/result_dart.dart';

/// Gateway para execução de queries em streaming.
///
/// Permite processar queries grandes que retornam milhões de linhas
/// sem carregar tudo na memória de uma vez.
abstract class IStreamingDatabaseGateway {
  /// Executa query em streaming, processando em chunks.
  ///
  /// [onChunk] é chamado para cada lote de linhas processado.
  /// [fetchSize] é o número de linhas buscadas por vez.
  /// [chunkSizeBytes] é o tamanho aproximado em bytes de cada chunk.
  Future<Result<void>> executeQueryStream(
    String query,
    String connectionString,
    void Function(List<Map<String, dynamic>> chunk) onChunk, {
    int fetchSize,
    int chunkSizeBytes,
  });
}
