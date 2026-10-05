import unittest

from tool.updater.validate_windows_installation import matches_os


class WindowsValidationIdentityTests(unittest.TestCase):
    def test_server_and_client_with_the_same_build_are_not_interchangeable(self):
        self.assertTrue(matches_os("server2019", 17763, True))
        self.assertFalse(matches_os("server2019", 17763, False))
        self.assertTrue(matches_os("windows10", 17763, False))
        self.assertFalse(matches_os("windows10", 17763, True))

    def test_each_server_target_requires_its_actual_build(self):
        for name, build in (("server2016", 14393), ("server2019", 17763),
                            ("server2022", 20348), ("server2025", 26100)):
            with self.subTest(name=name):
                self.assertTrue(matches_os(name, build, True))
                self.assertFalse(matches_os(name, 19045, True))

    def test_client_versions_are_separated_at_windows_11(self):
        self.assertTrue(matches_os("windows10", 19045, False))
        self.assertFalse(matches_os("windows10", 22000, False))
        self.assertTrue(matches_os("windows11", 22000, False))
        self.assertFalse(matches_os("windows11", 19045, False))
        self.assertFalse(matches_os("windows10", 9600, False))
