from __future__ import annotations

import subprocess
import unittest
from unittest.mock import patch

from tool.agent_actions.homologate_hub_agent_actions import main, run_manifest_tests


class ManifestRunnerTests(unittest.TestCase):
    def test_checklist_uses_platform_command_resolution(self) -> None:
        module = 'tool.agent_actions.homologate_hub_agent_actions'
        with (
            patch('sys.argv', ['homologate', '--run-contract-tests']),
            patch(f'{module}.run', return_value=subprocess.CompletedProcess([], 0)) as run,
            patch(f'{module}.run_manifest_tests', return_value=0),
            patch(f'{module}.read_manifest_test_paths', return_value=['test/example.dart']),
            patch(f'{module}.subprocess.run', side_effect=FileNotFoundError('dart batch file')),
        ):
            self.assertEqual(main(), 0)
        self.assertEqual(run.call_args.args[0], [
            'dart', 'run', 'tool/agent_actions/agent_action_security_gate_checklist.dart',
        ])

    def test_long_manifest_preserves_all_paths_in_bounded_commands(self) -> None:
        paths = [f'test/folder with spaces/{index:04d}_test.dart' for index in range(300)]
        with patch('tool.agent_actions.homologate_hub_agent_actions.run_streaming', return_value=0) as run:
            self.assertEqual(run_manifest_tests(paths), 0)
        commands = [call.args[0] for call in run.call_args_list]
        self.assertGreater(len(commands), 1)
        self.assertEqual([path for command in commands for path in command[2:]], paths)
        self.assertTrue(all(len(subprocess.list2cmdline(command)) <= 6000 for command in commands))

    def test_failure_stops_remaining_batches(self) -> None:
        paths = [f'test/{index:04d}_' + 'x' * 180 + '.dart' for index in range(100)]
        with patch('tool.agent_actions.homologate_hub_agent_actions.run_streaming', return_value=7) as run:
            self.assertEqual(run_manifest_tests(paths), 7)
        self.assertEqual(run.call_count, 1)

    def test_empty_or_untransportable_manifest_is_refused(self) -> None:
        for paths in ([], ['x' * 6000]):
            with self.subTest(paths_length=len(paths)), self.assertRaises(ValueError):
                run_manifest_tests(paths)
