"""Exercise Claude's real subprocess boundary without contacting an AI service."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

from test_ranking import load_backend, isolate_backend, ROOT


FAKE_CLAUDE = r'''
import json, os, sys, time
from pathlib import Path
base = Path(os.environ['PYIN_CLAUDE_FIXTURE'])
mode = os.environ.get('PYIN_CLAUDE_MODE', '')
(base/'pid').write_text(str(os.getpid()))
(base/'argv.json').write_text(json.dumps(sys.argv[1:]))
def send(message):
    print(json.dumps(message), flush=True)
def receive():
    line=sys.stdin.readline()
    with (base/'requests.jsonl').open('a') as log: log.write(line)
    return json.loads(line)
request=receive()
if mode=='timeout': time.sleep(60)
if mode=='eof': sys.exit(1)
if mode=='oversized':
    print('x' * (1024*1024+1), flush=True)
    time.sleep(60)
send({'type':'control_response','response':{'subtype':'success','request_id':request['request_id'],
      'response':{'models':[
        {'value':'future[2m]','displayName':'Future model','supportedEffortLevels':['deeper','deeper','bad effort']},
        {'value':'small','displayName':'Small model'},
        {'value':'future[2m]'}, {'value':'--bad'}, {'value':'bad;command'}],
        'account': {'private':'must not be returned or cached'}}}})
request=receive()
if mode=='hang-summary': time.sleep(60)
if mode=='permission':
    send({'type':'control_request','request_id':'tool','request':{'subtype':'can_use_tool','tool_name':'Bash'}})
    response=receive()
    assert response['response']['response']['behavior']=='deny'
send({'type':'system','subtype':'init','model':'resolved-model'})
send({'type':'stream_event','event':['unexpected']})
send({'type':'assistant','message':['unexpected']})
def event(value, parent=None):
    send({'type':'stream_event','event':value,'parent_tool_use_id':parent})
event({'type':'message_start','message':{'model':'resolved-model'}})
event({'type':'content_block_start','index':0,'content_block':{'type':'thinking'}})
event({'type':'content_block_delta','index':0,'delta':{'type':'thinking_delta','thinking':'private reasoning'}})
event({'type':'content_block_delta','index':0,'delta':{'type':'text_delta','text':'wrong block'}})
event({'type':'content_block_start','index':1,'content_block':{'type':'text'}})
event({'type':'content_block_delta','index':1,'delta':{'type':'text_delta','text':'subagent text'}}, 'child')
if mode!='no-deltas':
    event({'type':'content_block_delta','index':1,'delta':{'type':'text_delta','text':'Source-bound summary.'}})
send({'type':'assistant','message':{'model':'resolved-model','content':[
    {'type':'thinking','thinking':'private reasoning'}, {'type':'text','text':'Source-bound summary.'}]}})
send({'type':'result','subtype':'success','is_error':mode=='error',
      'result':'Sign in to Claude Code.' if mode=='error' else 'Source-bound summary.'})
time.sleep(60)
'''


class ClaudeProviderTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.backend = load_backend()
        boundary = mock.patch.object(self.backend.news_ai, 'prepare_native',
            side_effect=lambda agent, command, directory, environment=None:
                (command, {**os.environ, **(environment or {})}))
        boundary.start()
        self.addCleanup(boundary.stop)
        isolate_backend(self.backend, temporary.name)
        self.backend.AGENT_PATH = self.base / 'agent'
        self.backend.AGENT_PATH.write_text('claude')
        self.executable = self.base / 'claude'
        self.executable.write_text('#!' + sys.executable + '\n' + FAKE_CLAUDE)
        self.executable.chmod(0o700)
        path = mock.patch.object(self.backend, 'claude_path', return_value=str(self.executable))
        self.claude_path = path.start()
        self.addCleanup(path.stop)
        env = mock.patch.dict(os.environ, {'PYIN_CLAUDE_FIXTURE': str(self.base), 'PYIN_CLAUDE_MODE': ''})
        env.start()
        self.addCleanup(env.stop)

    def requests(self):
        return [json.loads(line) for line in (self.base / 'requests.jsonl').read_text().splitlines()]

    def check_stopped(self):
        pid = int((self.base / 'pid').read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)
        self.assertEqual(list(self.backend.STATE_DIR.glob('claude-*')), [])

    def test_availability_does_not_launch_and_missing_executable_is_clear(self):
        with mock.patch.object(self.backend.subprocess, 'Popen') as launch:
            self.assertTrue(self.backend.system_ai_status()['available'])
            self.assertTrue(self.backend.doctor()['system_ai_ready'])
            self.claude_path.return_value = ''
            status = self.backend.system_ai_status()
            self.assertEqual(status['status'], 'missing')
            self.assertFalse(self.backend.doctor()['system_ai_ready'])
            self.assertIn('Claude Code', status['message'])
            launch.assert_not_called()

    def test_discovery_never_sends_prompt_and_uses_advertised_models_and_effort(self):
        result = self.backend.ai_models()
        self.assertEqual([row['value'] for row in result['models']], ['future[2m]', 'small'])
        self.assertEqual([row['value'] for row in result['models'][0]['efforts']], ['deeper'])
        self.assertEqual(result['agent'], 'claude')
        self.assertEqual(len(self.requests()), 1)
        self.assertEqual(self.requests()[0]['request']['subtype'], 'initialize')
        self.assertNotIn('private', (self.backend.STATE_DIR / 'ai-models.json').read_text())
        self.assertTrue(self.backend.ai_models()['cached'])
        self.assertEqual(len(self.requests()), 1)
        self.check_stopped()

    def test_default_summary_preserves_model_settings_and_disables_tools(self):
        deltas = []
        previous = signal.getsignal(signal.SIGTERM)
        answer, label = self.backend.run_system_ai_stream('Article text', {'model':'', 'effort':''}, deltas.append)
        self.assertEqual(deltas, ['Source-bound summary.'])
        self.assertEqual(answer, deltas[0])
        self.assertEqual(label, 'System AI · Claude Code · resolved-model')
        args = json.loads((self.base / 'argv.json').read_text())
        for flag in ('--safe-mode', '--no-session-persistence', '--disable-slash-commands', '--strict-mcp-config'):
            self.assertIn(flag, args)
        self.assertEqual(args[args.index('--tools') + 1], '')
        self.assertEqual(args[args.index('--permission-mode') + 1], 'dontAsk')
        self.assertNotIn('--model', args)
        self.assertNotIn('--effort', args)
        self.assertNotIn('--fallback-model', args)
        self.assertEqual(self.requests()[1]['message']['content'], 'Article text')
        self.assertIs(signal.getsignal(signal.SIGTERM), previous)
        self.check_stopped()

    def test_explicit_model_reasoning_and_nonstreaming_use_claude(self):
        choice = {'model':'future[2m]', 'effort':'deeper'}
        answer, label = self.backend.run_system_ai('Article text', choice)
        args = json.loads((self.base / 'argv.json').read_text())
        self.assertEqual(args[args.index('--model') + 1], 'future[2m]')
        self.assertEqual(args[args.index('--effort') + 1], 'deeper')
        self.assertEqual(answer, 'Source-bound summary.')
        self.assertTrue(label.endswith('resolved-model · deeper'))
        self.assertFalse(self.backend.summary_cache_allowed('system', 'balanced'))
        self.check_stopped()

    def test_permission_requests_are_denied(self):
        with mock.patch.dict(os.environ, {'PYIN_CLAUDE_MODE':'permission'}):
            self.backend.run_system_ai('Article', {'model':'', 'effort':''})
        response = self.requests()[2]
        self.assertEqual(response['response']['response']['behavior'], 'deny')
        self.check_stopped()

    def test_completed_answer_without_deltas_is_emitted_once(self):
        deltas = []
        with mock.patch.dict(os.environ, {'PYIN_CLAUDE_MODE':'no-deltas'}):
            self.backend.run_system_ai_stream('Article', 'configured', deltas.append)
        self.assertEqual(deltas, ['Source-bound summary.'])

    def test_error_after_partial_text_is_not_success(self):
        deltas = []
        with mock.patch.dict(os.environ, {'PYIN_CLAUDE_MODE':'error'}):
            with self.assertRaisesRegex(RuntimeError, 'Sign in'):
                self.backend.run_system_ai_stream('Article', 'configured', deltas.append)
        self.assertEqual(deltas, ['Source-bound summary.'])
        self.check_stopped()

    def test_timeout_eof_and_oversized_output_stop_process(self):
        for mode, error in [('timeout','timed out'), ('eof','stopped'), ('oversized','oversized')]:
            with self.subTest(mode=mode), mock.patch.dict(os.environ, {'PYIN_CLAUDE_MODE':mode}), \
                 mock.patch.object(self.backend, 'CLAUDE_DISCOVERY_TIMEOUT_SECONDS', 1):
                with self.assertRaisesRegex(RuntimeError, error):
                    self.backend.discover_claude_models()
                self.check_stopped()

    def test_catalog_config_and_agent_changes_do_not_reuse_wrong_catalog(self):
        self.backend.ai_models()
        with mock.patch.dict(os.environ, {'ANTHROPIC_BASE_URL':'https://new-provider.example'}):
            self.assertFalse(self.backend.ai_models()['cached'])
        self.backend.AGENT_PATH.write_text('codex')
        with mock.patch.object(self.backend.subprocess, 'Popen') as launch, \
             mock.patch.object(self.backend, 'discover_codex_models', return_value=[]):
            result = self.backend.ai_models()
            self.assertEqual(result['agent'], 'codex')
            self.assertEqual(result['models'], [])
            self.assertTrue(result['ok'])
            launch.assert_not_called()

    def test_bracketed_model_round_trips_but_invalid_input_does_not_save(self):
        self.backend.save_setup_profile(json.dumps(self.backend.default_setup_profile()))
        self.backend.set_system_ai_model(json.dumps({'model':'future[2m]', 'effort':'deeper'}))
        destination = self.base / 'export.json'
        self.backend.export_setup_profile(str(destination))
        self.backend.import_setup_profile(str(destination))
        self.assertEqual(self.backend.load_setup_profile()['ai']['system_model'], 'future[2m]')
        for invalid in ['model[]', 'model[1m];x', 'model[[1m]]', 'x' * 200 + '[1m]']:
            with self.assertRaises(ValueError):
                self.backend.set_system_ai_model(json.dumps({'model':invalid}))

    def test_parent_cancellation_terminates_cli(self):
        runner = self.base / 'runner.py'
        runner.write_text('''from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path
import sys, os
loader=SourceFileLoader('backend',sys.argv[1]);b=module_from_spec(spec_from_loader(loader.name,loader));loader.exec_module(b)
b.STATE_DIR=Path(sys.argv[2])/'state';b.CONFIG_DIR=Path(sys.argv[2])/'config'
b.claude_path=lambda:sys.argv[3]
b.news_ai.prepare_native=lambda agent, command, directory, environment=None: (command, {**os.environ, **(environment or {})})
b.claude_exchange('Article',{'model':'','effort':''},lambda delta:None)
''')
        process = subprocess.Popen([sys.executable, '-B', str(runner), str(ROOT / 'bin/chuchua-news'), str(self.base), str(self.executable)],
                                   env={**os.environ, 'PYIN_CLAUDE_MODE':'hang-summary'}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                if (self.base / 'requests.jsonl').exists() and len(self.requests()) == 2:
                    break
                time.sleep(0.02)
            self.assertEqual(len(self.requests()), 2)
            process.terminate()
            self.assertEqual(process.wait(timeout=5), 143)
            self.check_stopped()
        finally:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)


if __name__ == '__main__':
    unittest.main()
