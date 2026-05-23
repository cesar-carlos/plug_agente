import 'package:odbc_fast/odbc_fast.dart';

const String odbcResultEncodingEnvKey = 'ODBC_RESULT_ENCODING';

ResultEncoding resolveOdbcResultEncodingValue(String? rawValue) {
  return resultEncodingFromString(rawValue) ?? ResultEncoding.rowMajor;
}

ResultEncoding? resultEncodingFromString(String? rawValue) {
  final normalized = rawValue?.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
  return switch (normalized) {
    null || '' || 'rowmajor' || 'row' || '0' => ResultEncoding.rowMajor,
    'columnar' || 'columnarv2' || '1' => ResultEncoding.columnar,
    'columnarcompressed' || 'columnarv2compressed' || 'compressedcolumnar' || '2' => ResultEncoding.columnarCompressed,
    _ => null,
  };
}

String resultEncodingConfigName(ResultEncoding encoding) {
  return switch (encoding) {
    ResultEncoding.rowMajor => 'rowMajor',
    ResultEncoding.columnar => 'columnar',
    ResultEncoding.columnarCompressed => 'columnarCompressed',
  };
}
