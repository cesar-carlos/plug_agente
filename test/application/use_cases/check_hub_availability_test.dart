import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/check_hub_availability.dart';
import 'package:plug_agente/domain/repositories/i_hub_availability_probe.dart';

class _MockHubAvailabilityProbe extends Mock implements IHubAvailabilityProbe {}

void main() {
  late _MockHubAvailabilityProbe probe;
  late CheckHubAvailability useCase;

  setUp(() {
    probe = _MockHubAvailabilityProbe();
    useCase = CheckHubAvailability(probe);
  });

  test('returns true when probe reports reachable server', () async {
    when(() => probe.isServerReachable('https://hub.test')).thenAnswer((_) async => true);

    final result = await useCase('https://hub.test');

    expect(result, isTrue);
  });

  test('returns false when probe reports unreachable server', () async {
    when(() => probe.isServerReachable('https://hub.test')).thenAnswer((_) async => false);

    final result = await useCase('https://hub.test');

    expect(result, isFalse);
  });
}
