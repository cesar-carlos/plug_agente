"""Regression tests for the CI configuration preflight."""

from __future__ import annotations

import unittest

from tool.ci import validate_ci_configuration


class ValidateCiConfigurationTests(unittest.TestCase):
    def test_collect_unittest_modules_handles_line_continuations(self) -> None:
        source = """
        run: |
          python3 -m unittest \\
            tool.tests.test_first \\
            tool.tests.test_second \\
            -v
        """

        modules = validate_ci_configuration.collect_unittest_modules(source)

        self.assertEqual(modules, ["tool.tests.test_first", "tool.tests.test_second"])

    def test_collect_unittest_modules_handles_shell_command_substitution(self) -> None:
        source = 'output="$(python3 -m unittest tool.tests.test_configuration -v 2>&1)"'

        modules = validate_ci_configuration.collect_unittest_modules(source)

        self.assertEqual(modules, ["tool.tests.test_configuration"])

    def test_validate_analysis_options_rejects_deprecated_plugins(self) -> None:
        errors = validate_ci_configuration.validate_analysis_options(
            "analyzer:\n  plugins:\n    - drift_dev\n",
        )

        self.assertEqual(len(errors), 1)
        self.assertIn("deprecated analyzer plugins", errors[0])

    def test_validate_analysis_options_accepts_current_configuration(self) -> None:
        errors = validate_ci_configuration.validate_analysis_options(
            "analyzer:\n  errors:\n    missing_return: error\n",
        )

        self.assertEqual(errors, [])
