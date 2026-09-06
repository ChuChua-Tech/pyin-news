"""Gemini/Grok wire, isolation, and failure tests; no inference services used."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import tomllib
import unittest
from unittest import mock

from test_ranking import load_backend, isolate_backend, ROOT


FAKE_ACP = r'''
import json, os, sys, time
from pathlib import Path
base=Path(os.environ['PYIN_ACP_FIXTURE'])
mode=os.environ.get('PYIN_ACP_MODE','')
(base/'pid').write_text(str(os.getpid()))
(base/'argv.json').write_text(json.dumps(sys.argv[1:]))
def send(data): print(json.dumps({'jsonrpc':'2.0', **data}),flush=True)
def receive():
    line=sys.stdin.readline()
    if not line: sys.exit(0)
    with (base/'requests.jsonl').open('a') as f: f.write(line)
    return json.loads(line)
catalog={'currentModelId':'future', 'availableModels':[
 {'modelId':'future','name':'Future model','_meta':{'reasoningEfforts':[
   {'id':'marketing-name','value':'deeper','label':'More thought'},
   {'value':'deeper'},{'value':'bad value'}]}},
 {'modelId':'other/vendor[2m]'}, {'modelId':'future'}, {'modelId':'--bad'}, None],
 'account':'PRIVATE ACCOUNT'}
if '--prompt-file' in sys.argv:
    path=Path(sys.argv[sys.argv.index('--prompt-file')+1])
    blocks=json.loads(path.read_text())
    assert blocks[0]['type']=='resource'
    (base/'prompt.json').write_text(json.dumps({'text':blocks[0]['resource']['text'],'mode':path.stat().st_mode & 0o777}))
    if mode in ('timeout','hang-summary'): time.sleep(60)
    if mode=='eof': sys.exit(1)
    if mode=='oversized': print('x'*(1024*1024+1),flush=True); time.sleep(60)
    def frame(data): print(json.dumps(data),flush=True)
    frame({'type':'system','subtype':'init','model':'future','tools':['Bash'] if mode=='tools' else [],'mcp_servers':[]})
    if mode not in ('empty','auth-error','model-error'):
        frame({'type':'stream_event','event':{'type':'content_block_start','index':0,'content_block':{'type':'text'}}})
        for text in ('A concise ', 'summary.'):
            frame({'type':'stream_event','event':{'type':'content_block_delta','index':0,'delta':{'type':'text_delta','text':text}}})
        frame({'type':'stream_event','event':{'type':'content_block_delta','index':1,'delta':{'type':'thinking_delta','thinking':'PRIVATE REASONING'}}})
    error=mode in ('error','auth-error','model-error')
    frame({'type':'result','subtype':'error' if error else 'success','is_error':error,
           'stop_reason':'max_tokens' if mode=='incomplete' else 'end_turn',
           'result':'' if mode=='empty' else 'A concise summary.'})
    sys.exit(0)
while True:
    req=receive(); method=req.get('method'); result={}
    if mode=='timeout': time.sleep(60)
    if mode=='eof': sys.exit(1)
    if mode=='oversized': print('x'*(1024*1024+1),flush=True); time.sleep(60)
    if method=='initialize':
        result={'protocolVersion':2 if mode=='version' else 1,
                'authMethods':[{'id':'cached_token'},{'id':'xai.api_key'}]}
    elif method=='_x.ai/models/list': result={'result':catalog}
    elif method=='authenticate' and mode=='auth-error':
        send({'id':req['id'],'error':{'code':-32000,'message':'Sign-in required'}}); continue
    elif method=='session/new' and mode=='auth-error':
        send({'id':req['id'],'error':{'code':-32000,'message':'Sign-in required'}}); continue
    elif method=='session/new': result={'sessionId':'test-session','models':catalog}
    elif method=='session/set_model' and mode=='model-error':
        send({'id':req['id'],'error':{'code':-32602,'message':'Model unavailable'}}); continue
    elif method=='session/prompt':
        if mode=='hang-summary': time.sleep(60)
        if mode=='permission':
            send({'id':'permission','method':'session/request_permission','params':{}})
            assert receive()['result']['outcome']['outcome']=='cancelled'
            send({'id':'file','method':'fs/read_text_file','params':{'path':'secret'}})
            assert receive()['error']['code']==-32601
        def chunk(kind,text,session='test-session'):
            send({'method':'session/update','params':{'sessionId':session,
                  'update':{'sessionUpdate':kind,'content':{'type':'text','text':text}}}})
        send({'method':'session/update','params':[]})
        send({'method':'session/update','params':{'sessionId':'test-session','update':[]}})
        chunk('agent_thought_chunk','PRIVATE REASONING')
        chunk('agent_message_chunk','WRONG SESSION','another-session')
        if mode!='empty':
            chunk('agent_message_chunk','A concise ')
            chunk('agent_message_chunk','summary.')
        if mode=='error':
            send({'id':req['id'],'error':{'code':-32000,'message':'Request failed'}}); continue
        result={'stopReason': 'max_tokens' if mode=='incomplete' else 'end_turn'}
    send({'id':req['id'],'result':result})
'''


class AcpProvidersTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.backend = load_backend()
        isolate_backend(self.backend, self.base)
        self.backend.AGENT_PATH = self.base / 'agent'
        self.backend.AGENT_PATH.write_text('gemini')
        self.fake = self.base / 'fake-agent'
        self.fake.write_text('#!' + sys.executable + '\n' + FAKE_ACP)
        self.fake.chmod(0o700)
        self.environment = mock.patch.dict(os.environ, {
            'PYIN_ACP_FIXTURE': str(self.base), 'PYIN_ACP_MODE': '',
            'GROK_HOME': str(self.base / 'original-grok'),
            'GEMINI_CLI_HOME': str(self.base / 'original-gemini'),
            'GEMINI_CLI_SYSTEM_SETTINGS_PATH': str(self.base / 'original-gemini.json')})
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.path_mock = mock.patch.object(self.backend, 'system_agent_path', return_value=str(self.fake))
        self.path_mock.start()
        self.addCleanup(self.path_mock.stop)

    def requests(self):
        path = self.base / 'requests.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def summary(self, agent, choice=None, mode=''):
        self.backend.AGENT_PATH.write_text(agent)
        deltas = []
        with mock.patch.dict(os.environ, {'PYIN_ACP_MODE': mode}):
            answer, label = self.backend.run_system_ai_stream(
                'Article text', choice or {'model': '', 'effort': ''}, deltas.append)
        return answer, label, deltas

    def assert_cleaned(self):
        pid = int((self.base / 'pid').read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)
        self.assertFalse(list(self.backend.STATE_DIR.glob('gemini-*')))
        self.assertFalse(list(self.backend.STATE_DIR.glob('grok-*')))

    def test_catalog_is_dynamic_deduplicated_cached_and_never_sends_a_prompt(self):
        for agent in ('gemini', 'grok'):
            with self.subTest(agent=agent):
                self.backend.AGENT_PATH.write_text(agent)
                result = self.backend.ai_models(refresh=True)
                self.assertTrue(result['ok'], result)
                self.assertEqual([m['value'] for m in result['models']], ['future', 'other/vendor[2m]'])
                efforts = result['models'][0]['efforts']
                self.assertEqual([e['value'] for e in efforts], ['deeper'] if agent == 'grok' else [])
                self.assertTrue(self.backend.ai_models()['cached'])
                self.assertNotIn('PRIVATE', (self.backend.STATE_DIR / 'ai-models.json').read_text())
                self.assertNotIn('session/prompt', [r.get('method') for r in self.requests()])
                self.assert_cleaned()

    def test_defaults_stream_only_answer_text_and_leave_model_unset(self):
        for agent in ('gemini', 'grok'):
            with self.subTest(agent=agent):
                answer, label, deltas = self.summary(agent)
                self.assertEqual(answer, 'A concise summary.')
                self.assertEqual(deltas, ['A concise ', 'summary.'])
                self.assertIn(agent.capitalize(), label)
                self.assertNotIn('session/set_model', [r.get('method') for r in self.requests()])
                self.assertFalse(self.backend.summary_cache_allowed('system', 'balanced'))
                self.assert_cleaned()

    def test_explicit_model_and_grok_advertised_wire_effort(self):
        self.summary('grok', {'model': 'future', 'effort': 'deeper'})
        argv = json.loads((self.base / 'argv.json').read_text())
        self.assertEqual(argv[argv.index('--model') + 1], 'future')
        self.assertEqual(argv[argv.index('--reasoning-effort') + 1], 'deeper')
        self.assertEqual(json.loads((self.base / 'prompt.json').read_text()), {'text': 'Article text', 'mode': 0o600})
        self.assertEqual(argv[argv.index('--tools') + 1], 'Read')
        self.assertEqual(argv[argv.index('--disallowed-tools') + 1], 'read_file,search_tool,use_tool')
        self.assertEqual(argv[argv.index('--deny') + 1], '*')
        self.assertIn('dontAsk', argv)
        self.assertIn('--no-subagents', argv)

    def test_gemini_override_and_nonstream_dispatch(self):
        self.backend.AGENT_PATH.write_text('gemini')
        answer, label = self.backend.run_system_ai('Article text', {'model': 'other/vendor[2m]', 'effort': ''})
        self.assertEqual(answer, 'A concise summary.')
        self.assertIn('other/vendor[2m]', label)
        chosen = next(r for r in self.requests() if r.get('method') == 'session/set_model')
        self.assertNotIn('_meta', chosen['params'])

    def test_gemini_rejects_old_reasoning_override_before_launch(self):
        with mock.patch.object(self.backend.subprocess, 'Popen') as launch:
            with self.assertRaisesRegex(ValueError, 'Clear the reasoning override'):
                self.summary('gemini', {'model': 'future', 'effort': 'deeper'})
        launch.assert_not_called()

    def test_permission_and_filesystem_requests_are_denied(self):
        self.summary('gemini', mode='permission')
        responses = {r.get('id'): r for r in self.requests() if 'method' not in r}
        self.assertEqual(responses['permission']['result']['outcome']['outcome'], 'cancelled')
        self.assertIn('error', responses['file'])

    def test_auth_and_model_fail_before_prompt(self):
        for mode in ('auth-error', 'model-error'):
            (self.base / 'requests.jsonl').unlink(missing_ok=True)
            with self.assertRaises(RuntimeError):
                self.summary('gemini', {'model': 'future', 'effort': ''}, mode)
            self.assertNotIn('session/prompt', [r.get('method') for r in self.requests()])
            self.assert_cleaned()

    def test_partial_error_empty_and_incomplete_results_are_not_success(self):
        for mode in ('error', 'empty', 'incomplete', 'version'):
            with self.subTest(mode=mode), self.assertRaises(RuntimeError):
                self.summary('gemini', mode=mode)
            self.assert_cleaned()

    def test_grok_rejects_incomplete_errors_empty_and_tools_enabled(self):
        for mode in ('error', 'auth-error', 'model-error', 'empty', 'incomplete', 'tools'):
            with self.subTest(mode=mode), self.assertRaises(RuntimeError):
                self.summary('grok', mode=mode)
            self.assert_cleaned()

    def test_timeout_eof_and_oversized_output_stop_process(self):
        self.backend.ACP_SUMMARY_TIMEOUT_SECONDS = 0.2
        for mode in ('timeout', 'eof', 'oversized'):
            with self.subTest(mode=mode), self.assertRaises(RuntimeError):
                self.summary('grok', mode=mode)
            self.assert_cleaned()

    def test_session_configuration_is_private_and_preserves_auth_and_models(self):
        original = self.base / 'original-grok'
        original.mkdir()
        (original / 'managed_config.toml').write_text('[model.future]\nbase_url="http://localhost:9000"\n')
        text = '[models]\ndefault="future"\ndefault_reasoning_effort="deeper"\n[model.future]\nmodel="future-v2"\napi_key="PRIVATE"\n[plugins]\npaths=["/unwanted"]\n'
        (original / 'config.toml').write_text(text)
        directory = self.base / 'grok-session'
        directory.mkdir()
        env = self.backend.acp_environment('grok', directory)
        config_path = Path(env['GROK_HOME']) / 'config.toml'
        config = tomllib.loads(config_path.read_text())
        self.assertEqual(config['models']['default'], 'future')
        self.assertEqual(config['model']['future']['api_key'], 'PRIVATE')
        self.assertEqual(config['model']['future']['base_url'], 'http://localhost:9000')
        self.assertEqual(env['GROK_AUTH_PATH'], str(original / 'auth.json'))
        self.assertEqual(env['GROK_TURN_SUMMARY'], '0')
        self.assertEqual(env['GROK_TITLE_REFRESH'], '0')
        self.assertFalse(config['compat']['claude']['hooks'])
        self.assertFalse(config['managed_mcps']['enabled'])
        self.assertNotIn('plugins', config)
        self.assertEqual(config_path.stat().st_mode & 0o777, 0o600)
        self.assertEqual((original / 'config.toml').read_text(), text)
        self.assertEqual(env.get('HOME'), os.environ.get('HOME'))
        original_gemini = self.base / 'original-gemini.json'
        original_config = self.base / 'original-gemini' / '.gemini'
        original_config.mkdir(parents=True)
        (original_config / 'oauth_creds.json').write_text('{"token":"PRIVATE"}')
        original_gemini.write_text(json.dumps({'security': {'auth': {'selectedType': 'oauth-personal'}},
            'tools': {'core': ['ShellTool']}, 'hooksConfig': {'enabled': True}}))
        directory = self.base / 'gemini-session'
        directory.mkdir()
        env = self.backend.acp_environment('gemini', directory)
        config = json.loads(Path(env['GEMINI_CLI_SYSTEM_SETTINGS_PATH']).read_text())
        copied = Path(env['GEMINI_CLI_HOME']) / '.gemini' / 'oauth_creds.json'
        self.assertEqual(copied.read_text(), '{"token":"PRIVATE"}')
        self.assertEqual(copied.stat().st_mode & 0o777, 0o600)
        self.assertEqual(env.get('HOME'), os.environ.get('HOME'))
        self.assertEqual(config['security']['auth']['selectedType'], 'oauth-personal')
        self.assertEqual(config['tools']['core'], [])
        self.assertFalse(config['hooksConfig']['enabled'])
        self.assertFalse(config['admin']['mcp']['enabled'])
        self.assertTrue(json.loads(original_gemini.read_text())['hooksConfig']['enabled'])

    def test_catalog_identity_tracks_agent_config_and_does_not_store_secrets(self):
        identity = self.backend.system_ai_catalog_identity('grok')
        directory = self.base / 'original-grok'
        directory.mkdir()
        (directory / 'config.toml').write_text('[models]\ndefault="future"\n')
        self.assertNotEqual(identity, self.backend.system_ai_catalog_identity('grok'))
        with mock.patch.dict(os.environ, {'XAI_API_KEY': 'PRIVATE'}):
            self.assertNotEqual(identity, self.backend.system_ai_catalog_identity('grok'))
            self.assertNotIn('PRIVATE', self.backend.system_ai_catalog_identity('grok'))

    def test_availability_and_missing_commands_never_launch(self):
        with mock.patch.object(self.backend.subprocess, 'Popen') as launch:
            for agent in ('gemini', 'grok'):
                self.backend.AGENT_PATH.write_text(agent)
                self.assertTrue(self.backend.system_ai_status()['available'])
                with mock.patch.object(self.backend, 'system_agent_path', return_value=''):
                    self.assertEqual(self.backend.system_ai_status()['status'], 'missing')
        launch.assert_not_called()

    def test_parent_cancellation_stops_agent_and_removes_temporary_session(self):
        runner = self.base / 'runner.py'
        runner.write_text('import sys\nsys.path.insert(0, ' + repr(str(ROOT / 'tests')) + ')\n'
            'from test_ranking import load_backend, isolate_backend\n'
            'b=load_backend()\nisolate_backend(b, ' + repr(str(self.base)) + ')\n'
            'b.system_agent_path=lambda agent: ' + repr(str(self.fake)) + '\n'
            'b.acp_exchange("gemini", "Article", {"model":"", "effort":""}, lambda text:None)\n')
        with mock.patch.dict(os.environ, {'PYIN_ACP_MODE': 'hang-summary'}):
            parent = subprocess.Popen([sys.executable, str(runner)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            end = time.monotonic() + 5
            while time.monotonic() < end:
                path = self.base / 'requests.jsonl'
                if path.exists() and 'session/prompt' in path.read_text():
                    break
                time.sleep(0.02)
            else:
                self.fail('Agent did not reach prompt')
            parent.send_signal(signal.SIGTERM)
            parent.communicate(timeout=5)
            self.assertEqual(parent.returncode, 143)
            self.assert_cleaned()
        finally:
            if parent.poll() is None:
                parent.kill()
                parent.communicate()


if __name__ == '__main__':
    unittest.main()
