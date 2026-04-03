import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/validation/trace_context_validator.dart';

void main() {
  group('TraceContextValidator', () {
    group('isValidTraceParent', () {
      test('should accept valid traceparent (lowercase)', () {
        expect(
          TraceContextValidator.isValidTraceParent(
            '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01',
          ),
          isTrue,
        );
      });

      test('should accept valid traceparent (uppercase hex)', () {
        expect(
          TraceContextValidator.isValidTraceParent(
            '00-0AF7651916CD43DD8448EB211C80319C-B7AD6B7169203331-01',
          ),
          isTrue,
        );
      });

      test('should reject invalid traceparent', () {
        expect(TraceContextValidator.isValidTraceParent(''), isFalse);
        expect(TraceContextValidator.isValidTraceParent('not-a-trace'), isFalse);
        expect(
          TraceContextValidator.isValidTraceParent(
            '00-short-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01',
          ),
          isFalse,
        );
      });
    });

    group('isValidTraceState', () {
      test('should reject empty or oversized string', () {
        expect(TraceContextValidator.isValidTraceState(''), isFalse);
        expect(TraceContextValidator.isValidTraceState('a' * 513), isFalse);
      });

      test('should reject too many list members', () {
        final members = List.generate(33, (i) => 'k$i=v').join(',');
        expect(TraceContextValidator.isValidTraceState(members), isFalse);
      });

      test('should reject malformed key=value pairs', () {
        expect(TraceContextValidator.isValidTraceState('=value'), isFalse);
        expect(TraceContextValidator.isValidTraceState('key='), isFalse);
        expect(TraceContextValidator.isValidTraceState('noequals'), isFalse);
      });

      test('should reject invalid value characters', () {
        expect(TraceContextValidator.isValidTraceState('k=v,v'), isFalse);
        expect(TraceContextValidator.isValidTraceState('k=v\x01'), isFalse);
      });

      test('should accept valid tracestate', () {
        expect(
          TraceContextValidator.isValidTraceState('vendor@nr=12345'),
          isTrue,
        );
        expect(
          TraceContextValidator.isValidTraceState('k1=v1,k2=v2'),
          isTrue,
        );
      });
    });
  });
}
