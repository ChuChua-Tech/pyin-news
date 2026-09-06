"""Context/framing is opt-in, portable, and isolated from ordinary summary caches."""
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock
from test_ranking import load_backend, isolate_backend, NOW


class ContextFramingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.backend = load_backend()
        isolate_backend(self.backend, self.tmp.name)
        self.backend.save_setup_profile(json.dumps(self.backend.default_setup_profile()))
        conn = self.backend.db()
        with conn:
            conn.execute('INSERT INTO articles(id,url,title,source,feed_summary,content,published_ts,fetched_ts) VALUES(?,?,?,?,?,?,?,?)',
                         ('story', 'https://example.invalid/story', 'Fictional council debate', 'Example',
                          'A short excerpt.', 'The mayor called the proposal "a reckless gamble". ' * 20, NOW, NOW))
        conn.close()

    def test_default_and_legacy_import_are_off_and_enabled_choice_round_trips(self):
        self.assertIs(self.backend.load_setup_profile()['ai']['context_framing'], False)
        legacy = self.backend.default_setup_profile()
        legacy['version'] = 8
        del legacy['ai']['context_framing']
        self.backend.validate_imported_profile(legacy)
        self.assertIs(self.backend.normalize_setup_profile(legacy)['ai']['context_framing'], False)
        self.backend.set_context_framing(True)
        destination = Path(self.tmp.name) / 'profile.json'
        self.backend.export_setup_profile(str(destination))
        self.backend.set_context_framing(False)
        self.backend.import_setup_profile(str(destination))
        self.assertIs(self.backend.load_setup_profile()['ai']['context_framing'], True)
        legacy_path = Path(self.tmp.name) / 'legacy.json'
        legacy_path.write_text(json.dumps(legacy))
        self.backend.import_setup_profile(str(legacy_path))
        self.assertIs(self.backend.load_setup_profile()['ai']['context_framing'], False)

    def test_invalid_context_setting_import_does_not_change_saved_preferences(self):
        profile = self.backend.load_setup_profile()
        invalid = json.loads(json.dumps(profile))
        invalid['ai']['context_framing'] = 'false'
        path = Path(self.tmp.name) / 'invalid.json'
        path.write_text(json.dumps(invalid))
        with self.assertRaises(ValueError):
            self.backend.import_setup_profile(str(path))
        self.assertEqual(self.backend.load_setup_profile(), profile)

    def test_prompt_adds_evidence_constraints_only_when_requested(self):
        row = self.backend.article_row('story')
        with mock.patch.object(self.backend, 'http_get', side_effect=AssertionError('no outside fetch')):
            ordinary = self.backend.summary_prompt(row, 'story')
            context = self.backend.summary_prompt(row, 'story', True)
        self.assertNotIn('CONTEXT & FRAMING', ordinary)
        for phrase in ('CONTEXT & FRAMING', 'Original quote', 'context not checked',
                       'not present in this excerpt', 'Do not invent', 'at most 12 words',
                       'not independent fact-checking'):
            self.assertIn(phrase, context)
        self.assertLess(context.index('Do not invent'), context.index('<article>\n'))
        self.assertIn('under 340 words', context)

    def test_nonstream_setting_changes_invalidate_local_summary_cache(self):
        with mock.patch.object(self.backend, 'run_ai', return_value=('Answer', 'Local fixture')) as model:
            first = self.backend.summarize('story', 'local', 'http://127.0.0.1:1234/v1', 'fixture', 'configured', False)
            self.assertFalse(first['context_framing'])
            self.assertTrue(self.backend.summarize('story', 'local', '', 'fixture', 'configured', False)['cached'])
            self.backend.set_context_framing(True)
            checked = self.backend.summarize('story', 'local', '', 'fixture', 'configured', False)
            self.assertFalse(checked['cached'])
            self.assertTrue(checked['context_framing'])
            self.assertIn('CONTEXT & FRAMING', model.call_args.args[0])
            self.assertEqual(model.call_count, 2)
            self.backend.set_context_framing(False)
            self.assertFalse(self.backend.summarize('story', 'local', '', 'fixture', 'configured', False)['cached'])
            self.assertNotIn('CONTEXT & FRAMING', model.call_args.args[0])

    def test_stream_and_replay_report_the_request_mode_without_extra_model_calls(self):
        self.backend.set_context_framing(True)
        def stream(prompt, provider, url, model, choice, receive):
            self.assertIn('Original quote', prompt)
            receive('Example answer')
            return 'Example answer', 'Local fixture'
        with mock.patch.object(self.backend, 'run_ai_stream', side_effect=stream) as model:
            for cached in (False, True):
                out = io.StringIO()
                with redirect_stdout(out):
                    self.backend.summarize_stream('story', 'local', '', 'fixture', 'configured', False)
                events = [json.loads(line) for line in out.getvalue().splitlines()]
                for event in (events[0], events[-1]):
                    self.assertTrue(event['context_framing'])
                    self.assertEqual(event['cached'], cached)
            self.assertEqual(model.call_count, 1)

    def test_no_ai_remains_no_ai_with_context_enabled(self):
        self.backend.set_context_framing(True)
        with mock.patch.object(self.backend, 'run_ai') as model:
            with self.assertRaisesRegex(RuntimeError, 'disabled'):
                self.backend.summarize('story', 'off', '', '', 'configured', False)
            model.assert_not_called()
