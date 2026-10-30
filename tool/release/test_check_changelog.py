import unittest
from tool.release.check_changelog import validate

VALID = '## Unreleased\n\n## 1.8.9 - 2026-10-26\nStatus: prepared\nBuild: 1.8.9+1\n- Fix queues.\n'


class ChangelogTests(unittest.TestCase):
    def test_prepared_release(self):
        validate(VALID, '1.8.9+1', release=True)

    def test_local_history_is_not_publication(self):
        text = VALID.replace('prepared', 'local')
        validate(text, '1.8.9+1')
        with self.assertRaises(ValueError):
            validate(text, '1.8.9+1', release=True)

    def test_rejects_missing_entry_wrong_build_duplicates_bad_dates_and_empty_notes(self):
        cases = [VALID.replace('1.8.9', '1.8.8'), VALID.replace('+1', '+2'),
                 VALID + VALID.split('## Unreleased\n')[1],
                 VALID.replace('2026-10-26', '2026-02-30'),
                 VALID.replace('- Fix queues.', ''), VALID + '## Unreleased\n']
        for text in cases:
            with self.subTest(text=text), self.assertRaises(ValueError):
                validate(text, '1.8.9+1')

    def test_pending_prose_or_bullets_block_release(self):
        for pending in ['- New feature.', 'Unassigned changes.']:
            with self.subTest(pending=pending), self.assertRaises(ValueError):
                validate(VALID.replace('## Unreleased\n', '## Unreleased\n' + pending), '1.8.9+1', release=True)
