import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_parsers.dart';
import 'package:test/test.dart';

void main() {
  group('AgentActionDraftParsers.positiveInt', () {
    test('should return the value when input is a positive integer', () {
      expect(AgentActionDraftParsers.positiveInt(' 42 '), 42);
    });

    test('should return null when input is zero, negative or not a number', () {
      expect(AgentActionDraftParsers.positiveInt('0'), isNull);
      expect(AgentActionDraftParsers.positiveInt('-3'), isNull);
      expect(AgentActionDraftParsers.positiveInt('abc'), isNull);
      expect(AgentActionDraftParsers.positiveInt(''), isNull);
    });
  });

  group('AgentActionDraftParsers.commaSeparatedTokens', () {
    test('should split, trim and drop empty tokens', () {
      expect(
        AgentActionDraftParsers.commaSeparatedTokens(' a , b ,, c '),
        <String>{'a', 'b', 'c'},
      );
    });

    test('should return an empty set when input is blank', () {
      expect(AgentActionDraftParsers.commaSeparatedTokens('   '), isEmpty);
    });
  });

  group('AgentActionDraftParsers.environmentVariables', () {
    test('should parse NAME=value lines and ignore blanks and comments', () {
      final result = AgentActionDraftParsers.environmentVariables(
        'FOO=bar\n# comment\n\nBAZ=qux=extra',
      );
      expect(result, <String, String>{'FOO': 'bar', 'BAZ': 'qux=extra'});
    });

    test('should throw FormatException when a line has no valid name', () {
      expect(
        () => AgentActionDraftParsers.environmentVariables('=value'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => AgentActionDraftParsers.environmentVariables('novalue'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('AgentActionDraftParsers.formatEnvironmentVariables', () {
    test('should render sorted NAME=value lines', () {
      expect(
        AgentActionDraftParsers.formatEnvironmentVariables({'B': '2', 'A': '1'}),
        'A=1\nB=2',
      );
    });

    test('should return empty string for empty map', () {
      expect(AgentActionDraftParsers.formatEnvironmentVariables({}), '');
    });
  });

  group('AgentActionDraftParsers.acceptedExitCodes', () {
    test('should default to {0} when input is blank', () {
      expect(AgentActionDraftParsers.acceptedExitCodes('  '), <int>{0});
    });

    test('should parse a comma-separated list of codes', () {
      expect(AgentActionDraftParsers.acceptedExitCodes('0, 1 ,2'), <int>{0, 1, 2});
    });

    test('should return null when any token is not an integer', () {
      expect(AgentActionDraftParsers.acceptedExitCodes('0,x'), isNull);
    });
  });

  group('AgentActionDraftParsers.comObjectArguments', () {
    test('should return empty map for blank input', () {
      expect(
        AgentActionDraftParsers.comObjectArguments(''),
        const <String, Object?>{},
      );
    });

    test('should decode a JSON object', () {
      expect(
        AgentActionDraftParsers.comObjectArguments('{"a":1,"b":"x"}'),
        <String, Object?>{'a': 1, 'b': 'x'},
      );
    });

    test('should return null for invalid JSON or non-object JSON', () {
      expect(AgentActionDraftParsers.comObjectArguments('[1,2]'), isNull);
      expect(AgentActionDraftParsers.comObjectArguments('not json'), isNull);
    });
  });

  group('AgentActionDraftParsers.structuredArguments', () {
    test('should split lines, trim and drop empties', () {
      expect(
        AgentActionDraftParsers.structuredArguments('  --a \n\n --b \r\n--c'),
        <String>['--a', '--b', '--c'],
      );
    });
  });

  group('AgentActionDraftParsers path helpers', () {
    test('normalizePathForComparison should lowercase and unify separators', () {
      expect(
        AgentActionDraftParsers.normalizePathForComparison(' C:/Foo/Bar.EXE '),
        r'c:\foo\bar.exe',
      );
    });

    test('endsWithFileName should match suffix or full equality', () {
      expect(
        AgentActionDraftParsers.endsWithFileName(r'c:\app\executor.exe', 'executor.exe'),
        isTrue,
      );
      expect(
        AgentActionDraftParsers.endsWithFileName('executor.exe', 'executor.exe'),
        isTrue,
      );
      expect(
        AgentActionDraftParsers.endsWithFileName(r'c:\app\other.exe', 'executor.exe'),
        isFalse,
      );
    });
  });
}
