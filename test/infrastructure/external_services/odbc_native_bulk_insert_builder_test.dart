import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_native_bulk_insert_builder.dart';

void main() {
  test('uses columnar path for whole-number doubles in i32 columns', () {
    const request = BulkInsertRequest(
      table: 't',
      columns: [
        BulkInsertColumn(name: 'id', type: BulkInsertColumnType.i32),
      ],
      rows: [
        [1.0],
        [2.0],
      ],
    );

    final builder = OdbcNativeBulkInsertBuilder.fromRequest(request);

    expect(builder, isNotNull);
  });
}
