import copy
import unittest

from tool.benchmarks.run_streaming_tuning import control_stable, select_configuration


def workload(rows, fetch=1000, buffer=1048576, throughput=1000):
    return {'rows': rows, 'fetch_size': fetch, 'buffer_bytes': buffer,
            'samples': [{'rows_per_second': throughput, 'first_chunk_us': 100,
                         'rss_peak_bytes': 1000} for _ in range(9)]}


class StreamingTuningTests(unittest.TestCase):
    def test_gain_requires_all_workloads_and_latency_and_memory_limits(self):
        base = [workload(n) for n in (1000, 8000, 50000)]
        candidate = [workload(n, 2000, 65536, 1200) for n in (1000, 8000, 50000)]
        self.assertEqual(select_configuration(base + candidate)['recommendation'],
                         {'fetch_size': 2000, 'buffer_bytes': 65536})
        for metric, value in [('first_chunk_us', 106), ('rss_peak_bytes', 1101), ('rows_per_second', 849)]:
            invalid = copy.deepcopy(candidate)
            for sample in invalid[0]['samples']:
                sample[metric] = value
            self.assertIsNone(select_configuration(base + invalid)['recommendation'])
        self.assertIsNone(select_configuration(base + candidate[:2])['recommendation'])

    def test_ties_choose_smaller_fetch_and_buffer(self):
        reports = [workload(n) for n in (1000, 8000, 50000)]
        reports += [workload(n, f, b, 1200) for n in (1000, 8000, 50000)
                    for f, b in [(4000, 65536), (2000, 262144), (2000, 65536)]]
        self.assertEqual(select_configuration(reports)['recommendation'],
                         {'fetch_size': 2000, 'buffer_bytes': 65536})

    def test_unstable_identical_control_is_not_approved(self):
        a, b = workload(1000), workload(1000)
        self.assertTrue(control_stable(a, b))
        b['samples'][0]['first_chunk_us'] = 106
        self.assertFalse(control_stable(a, b))


if __name__ == '__main__':
    unittest.main()
