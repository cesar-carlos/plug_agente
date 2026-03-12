import 'dart:convert';
import 'dart:typed_data';

import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

/// Codec for encoding and decoding payloads.
///
/// Supports JSON encoding/decoding with future extensibility for other formats.
abstract class IPayloadCodec {
  /// Encodes data to bytes.
  Result<Uint8List> encode(dynamic data);

  /// Decodes bytes to data.
  Result<dynamic> decode(Uint8List bytes);

  /// Returns the encoding name.
  String get encoding;

  /// Returns the content type.
  String get contentType;
}

/// JSON payload codec.
class JsonPayloadCodec implements IPayloadCodec {
  const JsonPayloadCodec();

  @override
  String get encoding => 'json';

  @override
  String get contentType => 'application/json';

  @override
  Result<Uint8List> encode(dynamic data) {
    try {
      final jsonString = jsonEncode(data);
      final bytes = utf8.encode(jsonString);
      return Success(Uint8List.fromList(bytes));
    } on Exception catch (error) {
      return Failure(
        domain.CompressionFailure.withContext(
          message: 'Failed to encode JSON',
          cause: error,
          context: {'operation': 'encode', 'encoding': 'json'},
        ),
      );
    }
  }

  @override
  Result<dynamic> decode(Uint8List bytes) {
    try {
      final jsonString = utf8.decode(bytes);
      final decoded = jsonDecode(jsonString);
      return Success(decoded as Object);
    } on Exception catch (error) {
      return Failure(
        domain.CompressionFailure.withContext(
          message: 'Failed to decode JSON',
          cause: error,
          context: {'operation': 'decode', 'encoding': 'json'},
        ),
      );
    }
  }
}

/// Factory for creating payload codecs.
class PayloadCodecFactory {
  static IPayloadCodec getCodec(String encoding) {
    return switch (encoding) {
      'json' => const JsonPayloadCodec(),
      _ => throw ArgumentError('Unsupported encoding: $encoding'),
    };
  }
}
