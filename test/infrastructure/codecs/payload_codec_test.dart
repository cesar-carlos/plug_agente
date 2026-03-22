import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/infrastructure/codecs/payload_codec.dart';

void main() {
  group('JsonPayloadCodec', () {
    late JsonPayloadCodec codec;

    setUp(() {
      codec = const JsonPayloadCodec();
    });

    test('should encode data to JSON bytes', () {
      final data = {'name': 'John', 'age': 30};

      final result = codec.encode(data);

      expect(result.isSuccess(), isTrue);
      final bytes = result.getOrThrow();
      expect(bytes, isA<Uint8List>());

      final decoded = jsonDecode(utf8.decode(bytes));
      expect(decoded, equals(data));
    });

    test('should decode JSON bytes to data', () {
      final data = {'name': 'John', 'age': 30};
      final jsonString = jsonEncode(data);
      final bytes = Uint8List.fromList(utf8.encode(jsonString));

      final result = codec.decode(bytes);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), equals(data));
    });

    test('should encode and decode complex nested data', () {
      final data = {
        'users': [
          {
            'id': 1,
            'name': 'John',
            'nested': {'deep': 'value'},
          },
          {'id': 2, 'name': 'Jane'},
        ],
      };

      final encodeResult = codec.encode(data);
      expect(encodeResult.isSuccess(), isTrue);

      final decodeResult = codec.decode(encodeResult.getOrThrow());
      expect(decodeResult.isSuccess(), isTrue);
      expect(decodeResult.getOrThrow(), equals(data));
    });

    test('should return failure when decoding invalid JSON', () {
      final invalidBytes = Uint8List.fromList(utf8.encode('{invalid json}'));

      final result = codec.decode(invalidBytes);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<PayloadEncodingFailure>());
    });

    test('should have correct encoding and content type', () {
      expect(codec.encoding, equals('json'));
      expect(codec.contentType, equals('application/json'));
    });
  });

  group('PayloadCodecFactory', () {
    test('should return JsonPayloadCodec for json encoding', () {
      final codec = PayloadCodecFactory.getCodec('json');

      expect(codec, isA<JsonPayloadCodec>());
    });

    test('should throw ArgumentError for unsupported encoding', () {
      expect(
        () => PayloadCodecFactory.getCodec('invalid'),
        throwsArgumentError,
      );
    });
  });
}
