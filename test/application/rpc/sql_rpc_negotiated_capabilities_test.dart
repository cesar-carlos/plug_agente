import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/sql_rpc_negotiated_capabilities.dart';

void main() {
  group('negotiatedPaginationModes', () {
    test('returns all modes when paginationModes is absent', () {
      expect(
        negotiatedPaginationModes(const {}),
        {'page-offset', 'cursor-keyset', 'cursor-offset'},
      );
    });

    test('returns configured modes when paginationModes is non-empty', () {
      expect(
        negotiatedPaginationModes({
          'paginationModes': ['cursor-keyset'],
        }),
        {'cursor-keyset'},
      );
    });
  });

  group('supportsPageOffsetPagination', () {
    test('is true when page-offset is negotiated', () {
      expect(
        supportsPageOffsetPagination({
          'paginationModes': ['page-offset'],
        }),
        isTrue,
      );
    });

    test('is false when page-offset is not negotiated', () {
      expect(
        supportsPageOffsetPagination({
          'paginationModes': ['cursor-keyset'],
        }),
        isFalse,
      );
    });
  });

  group('supportsCursorKeysetPagination', () {
    test('is true for cursor-keyset or cursor-offset', () {
      expect(
        supportsCursorKeysetPagination({
          'paginationModes': ['cursor-keyset'],
        }),
        isTrue,
      );
      expect(
        supportsCursorKeysetPagination({
          'paginationModes': ['cursor-offset'],
        }),
        isTrue,
      );
    });
  });

  group('supportsStreamingChunks', () {
    test('defaults to true when streamingResults is absent', () {
      expect(supportsStreamingChunks(const {}), isTrue);
    });

    test('reflects streamingResults boolean when present', () {
      expect(
        supportsStreamingChunks({'streamingResults': false}),
        isFalse,
      );
      expect(
        supportsStreamingChunks({'streamingResults': true}),
        isTrue,
      );
    });
  });
}
