import 'package:result_dart/result_dart.dart';

/// Gateway para execução de queries em streaming.
///
/// Permite processar queries grandes que retornam milhões de linhas
/// sem carregar tudo na memória de uma vez.
abstract class IStreamingDatabaseGateway {
  /// Whether there is an active streaming execution that can be cancelled.
  bool get hasActiveStream;

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

  /// Cancela o streaming ativo no runtime ODBC.
  ///
  /// Deve interromper a operação em andamento e liberar recursos.
  Future<Result<void>> cancelActiveStream();
}
