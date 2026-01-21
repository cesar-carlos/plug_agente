// import 'dart:core';
// import 'package:dart_odbc/dart_odbc.dart';

/// Enum que representa os tipos de dados SQL suportados.
///
/// **Compatibilidade entre bancos:**
/// - **SQL Server**: Suporta todos os tipos. `nvarchar` e `datetime2` são específicos do SQL Server.
/// - **Sybase Anywhere**: Suporta tipos similares ao SQL Server. `nvarchar` e `nchar` são suportados.
/// - **PostgreSQL**:
///   - Não possui `nvarchar` ou `nchar` nativamente (usa `varchar`/`char` com encoding UTF-8).
///   - Não possui `datetime2` (usa `timestamp` ou `timestamp with time zone`).
///   - Não possui `image` (usa `bytea` para dados binários grandes).
///   - `money` existe, mas recomendado usar `numeric` ou `decimal`.
///
/// **IMPORTANTE**: A partir do dart_odbc 6.0.0+, o `ColumnType` foi removido.
/// A detecção automática de tipos é usada agora. O método `toColumnType()` abaixo
/// está comentado apenas para referência histórica e não pode ser usado.
enum SqlDataType {
  varchar,
  nvarchar,
  char,
  nchar,
  datetime,
  datetime2,
  date,
  decimal,
  numeric,
  integer,
  bigint,
  bit,
  float,
  money,
  binary,
  varbinary,
  image,
  unknown;

  static SqlDataType fromString(String type) {
    switch (type.toLowerCase()) {
      case 'varchar':
        return SqlDataType.varchar;
      case 'nvarchar':
        return SqlDataType.nvarchar;
      case 'char':
        return SqlDataType.char;
      case 'nchar':
        return SqlDataType.nchar;
      case 'datetime':
        return SqlDataType.datetime;
      case 'datetime2':
        return SqlDataType.datetime2;
      case 'date':
        return SqlDataType.date;
      case 'decimal':
        return SqlDataType.decimal;
      case 'numeric':
        return SqlDataType.numeric;
      case 'int':
        return SqlDataType.integer;
      case 'bigint':
        return SqlDataType.bigint;
      case 'bit':
        return SqlDataType.bit;
      case 'float':
        return SqlDataType.float;
      case 'money':
        return SqlDataType.money;
      case 'binary':
        return SqlDataType.binary;
      case 'varbinary':
        return SqlDataType.varbinary;
      case 'image':
        return SqlDataType.image;
      default:
        return SqlDataType.unknown;
    }
  }

  // MÉTODO REMOVIDO - Referência histórica apenas
  // O ColumnType foi removido no dart_odbc 6.0.0+
  // A detecção automática de tipos é usada agora
  /*
  ColumnType toColumnType({
    required int maxLength,
    required int precision,
    required int scale,
  }) {
    switch (this) {
      case SqlDataType.varchar:
      case SqlDataType.char:
        int safeSize;
        if (maxLength == -1 || maxLength <= 0) {
          safeSize = 8000;
        } else {
          // Para SQL_C_CHAR, adiciona margem de segurança
          // Fórmula observada: (maxLength * 2) + 2 para campos com 60+ caracteres
          // Isso garante espaço para:
          // - Terminador null (\0)
          // - Codificação UTF-8 (alguns caracteres podem usar 2 bytes)
          // - Padding/overhead do ODBC
          final calculatedSize = (maxLength * 2) + 2;
          // Limita ao máximo de 8000 mas permite valores maiores se necessário para campos grandes
          safeSize = calculatedSize.clamp(1, 8000);
        }
        return ColumnType(
          type: SQL_C_CHAR,
          size: safeSize,
        );
      case SqlDataType.nvarchar:
      case SqlDataType.nchar:
        // Nota: PostgreSQL não possui nvarchar/nchar nativamente, mas o ODBC
        // traduz SQL_C_WCHAR para varchar/char com encoding apropriado
        int charSize;
        if (maxLength == -1 || maxLength <= 0) {
          charSize = 4000;
        } else {
          charSize = maxLength.clamp(1, 4000);
        }
        return ColumnType(
          type: SQL_C_WCHAR,
          size: charSize,
        );
      case SqlDataType.datetime:
      case SqlDataType.datetime2:
        // Nota: datetime2 é específico do SQL Server. PostgreSQL usa timestamp,
        // mas o ODBC traduz SQL_C_TYPE_TIMESTAMP adequadamente
        return ColumnType(
          type: SQL_C_TYPE_TIMESTAMP,
          size: 24,
        );
      case SqlDataType.date:
        return ColumnType(
          type: SQL_C_TYPE_DATE,
          size: 10,
        );
      case SqlDataType.decimal:
      case SqlDataType.numeric:
        return ColumnType(
          type: SQL_C_CHAR,
          size: precision + 2,
        );
      case SqlDataType.integer:
        return ColumnType(
          type: SQL_C_LONG,
          size: 10,
        );
      case SqlDataType.bigint:
        return ColumnType(
          type: SQL_C_UBIGINT,
          size: 19,
        );
      case SqlDataType.bit:
        return ColumnType(
          type: SQL_C_BIT,
          size: 1,
        );
      case SqlDataType.float:
        return ColumnType(
          type: SQL_C_DOUBLE,
          size: 53,
        );
      case SqlDataType.money:
        // Nota: PostgreSQL tem tipo money, mas é recomendado usar decimal/numeric
        // para maior portabilidade. O ODBC mapeia money como string.
        return ColumnType(
          type: SQL_C_CHAR,
          size: 19,
        );
      case SqlDataType.binary:
      case SqlDataType.varbinary:
      case SqlDataType.image:
        // Nota: image é específico do SQL Server. PostgreSQL usa bytea,
        // mas o ODBC traduz SQL_C_BINARY adequadamente para ambos
        int byteSize;
        if (maxLength == -1 || maxLength <= 0) {
          byteSize = 8000;
        } else {
          byteSize = maxLength.clamp(1, 2147483647);
        }
        return ColumnType(
          type: SQL_C_BINARY,
          size: byteSize,
        );
      case SqlDataType.unknown:
        return ColumnType(
          size: maxLength == -1 ? 8000 : maxLength,
        );
    }
  }
  */
}
