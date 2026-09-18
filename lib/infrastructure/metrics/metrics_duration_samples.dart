import 'dart:collection';
import 'dart:math' as math;

/// A bounded latency reservoir. Counts remain external and exact; this buffer
/// intentionally retains a representative bounded sample for percentile work.
final class MetricsDurationSamples extends IterableBase<Duration> {
  MetricsDurationSamples({required this.capacity, math.Random? random}) : _random = random ?? math.Random();

  final int capacity;
  final math.Random _random;
  final List<Duration> _samples = <Duration>[];
  int _observedCount = 0;

  int get observedCount => _observedCount;

  @override
  int get length => _samples.length;

  @override
  Iterator<Duration> get iterator => _samples.iterator;

  void add(Duration value) {
    _observedCount++;
    if (_samples.length < capacity) {
      _samples.add(value);
      return;
    }

    final replacementIndex = _random.nextInt(_observedCount);
    if (replacementIndex < capacity) {
      _samples[replacementIndex] = value;
    }
  }

  void clear() {
    _samples.clear();
    _observedCount = 0;
  }
}
