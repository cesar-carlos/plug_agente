import copy
import unittest

from tool.benchmarks.compare_transport_repetitions import compare
from tool.benchmarks.run_transport_comparison import qualify


def report():
    scenarios = [
        {'case': case, 'requested_compression': mode, 'signed': signed,
         'summary': {'error_count': 0}, 'iterations': 100, 'send_sample_count': 100, 'receive_sample_count': 100, 'original_bytes': 100,
         'wire_bytes': 100, 'effective_compression': 'none',
         'send_p95_us': 100, 'receive_p95_us': 100}
        for case in ('small_sql_repetitive', 'large_sql_low_compressibility', 'large_incompressible_blob')
        for mode in ('none', 'auto', 'gzip') for signed in (False, True)
    ]
    return {'harness_version': 2, 'dart_version': 'test', 'platform': 'test',
            'config': {'iterations': 100, 'warmup_iterations': 10, 'repeats': 9},
            'repetitions': [copy.deepcopy(scenarios) for _ in range(9)],
            'elapsed_us': [1000] * 9, 'rss_peak_bytes': 1000, 'heap_growth_bytes': 100}


class TransportComparisonTests(unittest.TestCase):
    def test_complete_identical_reports_pass(self):
        self.assertEqual(compare(report(), report())['status'], 'pass')

    def test_missing_heap_is_inconclusive(self):
        candidate = report()
        del candidate['heap_growth_bytes']
        self.assertEqual(compare(report(), candidate)['status'], 'inconclusive')

    def test_measured_zero_heap_growth_obeys_the_existing_limit(self):
        base, candidate = report(), report()
        base['heap_growth_bytes'] = candidate['heap_growth_bytes'] = 0
        self.assertEqual(compare(base, candidate)['status'], 'pass')
        candidate['heap_growth_bytes'] = 1
        self.assertEqual(compare(base, candidate)['status'], 'fail')

    def test_each_existing_limit_is_preserved(self):
        for field in ('latency', 'throughput', 'heap'):
            with self.subTest(field=field):
                candidate = report()
                if field == 'latency':
                    for rows in candidate['repetitions']:
                        rows[0]['receive_p95_us'] = 106
                elif field == 'throughput':
                    candidate['elapsed_us'] = [1200] * 9
                else:
                    candidate['heap_growth_bytes'] = 111
                self.assertEqual(compare(report(), candidate)['status'], 'fail')

    def test_missing_scenario_or_nonfinite_measurement_is_rejected(self):
        for invalid in ('missing', 'nan', 'samples'):
            candidate = report()
            if invalid == 'missing':
                candidate['repetitions'][0].pop()
            elif invalid == 'nan':
                candidate['repetitions'][0][0]['send_p95_us'] = float('nan')
            else:
                candidate['config']['iterations'] = 20
            with self.assertRaises(ValueError):
                compare(report(), candidate)

    def test_noisy_identical_code_control_prevents_a_regression_claim(self):
        valid = compare(report(), report())
        control = {**valid, 'failures': ['latency noise']}
        self.assertEqual(qualify(control, valid, valid)['status'], 'inconclusive')

    def test_either_order_failing_is_not_approved(self):
        valid = compare(report(), report())
        failed = {**valid, 'failures': ['regression']}
        self.assertEqual(qualify(valid, valid, failed)['status'], 'fail')


if __name__ == '__main__':
    unittest.main()
