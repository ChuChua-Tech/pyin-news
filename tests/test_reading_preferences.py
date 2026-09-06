"""Reading size is portable and independent of density and saved reader choices."""
import json
from pathlib import Path
import tempfile
import unittest
from test_ranking import load_backend, isolate_backend


class ReadingPreferenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.backend = load_backend()
        isolate_backend(self.backend, self.tmp.name)

    def test_legacy_profile_keeps_regular_size_and_existing_choices(self):
        legacy = self.backend.default_setup_profile()
        legacy['version'] = 10
        del legacy['appearance']['reading_size']
        legacy['appearance'].update(density='compact', article_images=True)
        self.backend.validate_imported_profile(legacy)
        profile = self.backend.normalize_setup_profile(legacy)
        self.assertEqual(profile['appearance']['reading_size'], 'regular')
        self.assertEqual(profile['appearance']['density'], 'compact')
        self.assertTrue(profile['appearance']['article_images'])

    def test_size_round_trip_and_invalid_import_leave_preferences_intact(self):
        profile = self.backend.default_setup_profile()
        profile['appearance'].update(density='classic', article_images=True)
        self.backend.save_setup_profile(json.dumps(profile))
        self.backend.set_reading_size('extra-large')
        export = Path(self.tmp.name) / 'profile.json'
        self.backend.export_setup_profile(str(export))
        self.backend.set_reading_size('regular')
        self.backend.import_setup_profile(str(export))
        saved = self.backend.load_setup_profile()
        self.assertEqual(saved['appearance']['reading_size'], 'extra-large')
        self.assertEqual(saved['appearance']['density'], 'classic')
        self.assertTrue(saved['appearance']['article_images'])
        invalid = dict(saved, appearance=dict(saved['appearance'], reading_size='huge'))
        export.write_text(json.dumps(invalid))
        with self.assertRaises(ValueError):
            self.backend.import_setup_profile(str(export))
        self.assertEqual(self.backend.load_setup_profile(), saved)
        with self.assertRaises(ValueError):
            self.backend.set_reading_size('huge')
        self.assertEqual(self.backend.load_setup_profile(), saved)

    def test_size_change_cannot_complete_an_unfinished_setup(self):
        with self.assertRaisesRegex(ValueError, 'finish setup'):
            self.backend.set_reading_size('large')
        self.assertFalse(self.backend.load_setup_profile()['complete'])
