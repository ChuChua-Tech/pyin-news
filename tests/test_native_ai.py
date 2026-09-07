"""Authentication, cancellation and action rejection at the native AI boundary."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from test_ranking import load_backend, isolate_backend

ai = load_backend().news_ai

SERVER = r'''
import json, pathlib, sys, time
root=pathlib.Path(sys.argv[1]); mode=sys.argv[2]
def send(value): print(json.dumps(value),flush=True)
while True:
    line=sys.stdin.readline()
    if not line: break
    with (root/'received.jsonl').open('a') as stream: stream.write(line)
    message=json.loads(line); method=message.get('method'); result={}
    if method=='initialize': result={}
    elif method=='initialized': continue
    elif method=='account/read': result={'requiresOpenaiAuth':True,'account':None if mode=='signed-out' else {'type':'chatgpt'}}
    elif method=='model/list':
        result={'data':[{'model':'future-model','displayName':'Future model','supportedReasoningEfforts':[{'reasoningEffort':'high'}]}]}
        if mode=='pagination' and 'cursor' not in message['params']: result['nextCursor']='second'
        elif mode=='pagination': result['data']=[{'model':'other-model'}]
        elif mode=='bad-cursor': result['nextCursor']='repeated'
    elif method=='thread/start': result={'thread':{'id':'t'},'model':'configured-model'}
    elif method=='turn/start':
        send({'id':message['id'],'result':{}})
        if mode=='timeout': time.sleep(60)
        if mode=='action':
            send({'id':'file-action','method':'fs/read','params':{'path':'private'}})
            reply=sys.stdin.readline()
            with (root/'received.jsonl').open('a') as stream: stream.write(reply)
            assert json.loads(reply)['error']['code']==-32601
        if mode=='tool-item':
            send({'method':'item/started','params':{'threadId':'t','item':{'type':'commandExecution'}}})
            time.sleep(60)
        if mode=='oversized-line': print('x'*1048577,flush=True); time.sleep(60)
        send({'method':'item/agentMessage/delta','params':{'threadId':'another','delta':'wrong conversation'}})
        send({'method':'item/reasoning/textDelta','params':{'threadId':'t','delta':'private reasoning'}})
        if mode!='empty':
            for text in (['x'*65537] if mode=='oversized-answer' else ['A concise ','summary.']):
                send({'method':'item/agentMessage/delta','params':{'threadId':'t','delta':text}})
        send({'method':'turn/completed','params':{'threadId':'t','turn':{'status':'failed' if mode=='failed' else 'completed'}}})
        continue
    send({'id':message['id'],'result':result})
'''


class CodexProtocolTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.worker = self.root / 'agent.py'
        self.worker.write_text(SERVER)

    def exchange(self, mode='', prompt='Article', choice=None, timeout=3):
        command = [sys.executable, str(self.worker), str(self.root), mode]
        self.fragments = []
        with mock.patch.object(ai, 'codex_launch', return_value=(command, {})):
            return ai.codex_exchange('unused', self.root, prompt, choice or {'model':'','effort':''},
                                     self.fragments.append, timeout=timeout)

    def received(self):
        return [json.loads(line) for line in (self.root/'received.jsonl').read_text().splitlines()]

    def test_native_account_and_fresh_session_stream_only_the_answer(self):
        result = self.exchange(choice={'model':'chosen','effort':'high'})
        self.assertEqual(result['answer'], 'A concise summary.')
        self.assertEqual(self.fragments, ['A concise ', 'summary.'])
        requests = {item.get('method'):item.get('params') for item in self.received()}
        self.assertFalse(requests['account/read']['refreshToken'])
        thread = requests['thread/start']
        self.assertTrue(thread['ephemeral'])
        self.assertEqual(thread['environments'], [])
        self.assertEqual(thread['dynamicTools'], [])
        self.assertEqual(thread['model'], 'chosen')
        self.assertEqual(requests['turn/start']['effort'], 'high')

    def test_signed_out_never_starts_a_thread_or_sends_article(self):
        with self.assertRaisesRegex(RuntimeError, 'Sign in'):
            self.exchange('signed-out')
        self.assertNotIn('Article', json.dumps(self.received()))

    def test_catalog_pages_without_a_thread_or_inference(self):
        result = self.exchange('pagination', prompt=None)
        self.assertEqual([row['model'] for row in result['models']], ['future-model','other-model'])
        self.assertFalse(any(item.get('method') in {'thread/start','turn/start'} for item in self.received()))

    def test_repeated_catalog_cursor_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'cursor'):
            self.exchange('bad-cursor', prompt=None)

    def test_server_actions_are_denied_without_reading_files(self):
        self.assertEqual(self.exchange('action')['answer'], 'A concise summary.')
        denial = next(item for item in self.received() if item.get('id')=='file-action')
        self.assertEqual(denial['error']['code'], -32601)

    def test_tool_events_failed_empty_and_excessive_output_are_errors(self):
        for mode in ('tool-item','failed','empty','oversized-line','oversized-answer'):
            with self.subTest(mode=mode), self.assertRaises(RuntimeError):
                self.exchange(mode)

    def test_timeout_stops_the_process_and_restores_signal_handler(self):
        import signal
        previous = signal.getsignal(signal.SIGTERM)
        with self.assertRaisesRegex(RuntimeError, 'timed out'):
            self.exchange('timeout', timeout=0.2)
        self.assertIs(signal.getsignal(signal.SIGTERM), previous)


class NativeConfigurationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def test_environment_excludes_unrelated_secrets_proxies_and_agent_features(self):
        source = {'HOME':os.environ.get('HOME',''), 'PATH':'untrusted', 'ANTHROPIC_API_KEY':'native-key',
                  'GITHUB_TOKEN':'secret', 'HTTPS_PROXY':'http://proxy', 'NODE_OPTIONS':'--require evil',
                  'CLAUDE_CODE_USE_BEDROCK':'1', 'CLAUDE_CONFIG_DIR':'personal-config'}
        result = ai.clean_environment('claude', source)
        self.assertEqual(result, {'HOME':source['HOME'], 'PATH':'/usr/bin:/bin','ANTHROPIC_API_KEY':'native-key'})

    def test_codex_retains_only_model_configuration(self):
        config = self.root/'.codex'
        config.mkdir()
        (config/'config.toml').write_text('model="chosen"\nmodel_reasoning_effort="high"\n'
            '[mcp_servers.private]\ncommand="must-not-start"\n[features]\nshell_tool=true\n')
        with mock.patch.object(Path, 'home', return_value=self.root), mock.patch.dict(os.environ, {}, clear=True):
            settings, location = ai.codex_settings()
        self.assertEqual(settings, {'model':'chosen','model_reasoning_effort':'high'})
        self.assertEqual(location, config)

    def test_native_env_reads_only_explicit_keys_without_expansion(self):
        path = self.root/'.env'
        path.write_text('GEMINI_API_KEY="native-key" # comment\n'
                        'GITHUB_TOKEN=unrelated-secret\nEVIL=$(touch /tmp/never)\n')
        self.assertEqual(ai.native_env_file(path, {'GEMINI_API_KEY'}), {'GEMINI_API_KEY':'native-key'})

    def test_codex_model_override_drops_only_the_other_models_effort(self):
        for selected in ('', 'native-model', 'different-model'):
            with self.subTest(selected=selected), \
                 mock.patch.object(ai,'codex_settings',return_value=({
                     'model':'native-model','model_reasoning_effort':'max'},self.root)), \
                 mock.patch.object(ai,'isolated_command',return_value=['agent']), \
                 mock.patch.object(ai,'verify_version'):
                command,_ = ai.codex_launch('agent',self.root,{'model':selected,'effort':''})
                config = dict(command[i+1].split('=',1) for i,arg in enumerate(command) if arg=='-c')
                self.assertEqual(json.loads(config['model']),selected or 'native-model')
                if selected == 'different-model':
                    self.assertNotIn('model_reasoning_effort',config)
                else:
                    self.assertEqual(json.loads(config['model_reasoning_effort']),'max')

    def test_isolation_mounts_one_credential_and_private_runtime_not_user_home(self):
        auth = self.root/'auth.json'; auth.write_text('{}')
        command = ai.isolated_command('codex', [sys.executable], self.root, {},
                                       credential_files=[(auth,Path('/private/auth.json'))])
        self.assertNotIn('--ro-bind / /', ' '.join(command))
        self.assertNotIn('--ro-bind '+str(Path.home())+' '+str(Path.home()), ' '.join(command))
        self.assertIn('--unshare-pid', command)
        self.assertIn('--unshare-ipc', command)
        self.assertIn('--bind '+str(auth)+' /private/auth.json', ' '.join(command))
        self.assertNotIn('/run/user', command)

    def test_unknown_version_stops_before_article_process(self):
        worker = self.root/'version.py'
        worker.write_text('print("codex 999.0.0")\n')
        with self.assertRaisesRegex(RuntimeError, 'has not verified'):
            ai.verify_version('codex', [sys.executable,str(worker)], {})

    def test_oversized_version_output_is_bounded(self):
        worker = self.root/'version.py'; worker.write_text('print("x"*10000)\n')
        with self.assertRaisesRegex(RuntimeError, 'too much output'):
            ai.verify_version('codex', [sys.executable,str(worker)], {})

    def test_claude_retains_native_credentials_and_model_but_no_hooks_or_projects(self):
        original = self.root/'original'; original.mkdir()
        (original/'settings.json').write_text(json.dumps({'model':'chosen','hooks':{'command':'bad'},
                                                        'env':{'GITHUB_TOKEN':'secret'}}))
        auth = original/'.credentials.json'; auth.write_text('{"native":"credential"}')
        (original/'.claude.json').write_text(json.dumps({'hasCompletedOnboarding':True,'projects':{'secret':'private'}}))
        directory = self.root/'runtime'; directory.mkdir()
        with mock.patch.dict(os.environ, {'CLAUDE_CONFIG_DIR':str(original)}), \
             mock.patch.object(ai, 'isolated_command', return_value=['agent']) as isolate, \
             mock.patch.object(ai, 'verify_version', return_value='2.1.261'):
            command, environment = ai.prepare_native('claude', ['agent','--print'], directory)
        settings = json.loads((directory/'claude-config/settings.json').read_text())
        self.assertEqual(settings, {'model':'chosen','disableAllHooks':True})
        self.assertNotIn('projects', (directory/'claude-config/.claude.json').read_text())
        self.assertEqual(isolate.call_args.kwargs['credential_files'], [(auth,directory/'claude-config/.credentials.json')])
        self.assertNotIn('GITHUB_TOKEN', environment)

    def test_shared_input_and_output_bounds_apply_to_all_ai_features(self):
        backend = load_backend(); isolate_backend(backend,self.root)
        with mock.patch.object(backend,'run_system_ai_stream') as run:
            with self.assertRaises(ValueError):
                backend.run_ai('x'*(ai.MAX_INPUT_CHARS+1),'system','','','configured')
            run.assert_not_called()
        def excessive(prompt, choice, on_delta):
            on_delta('x'*(ai.MAX_ANSWER_CHARS+1))
        with mock.patch.object(backend,'run_system_ai_stream',side_effect=excessive):
            with self.assertRaisesRegex(RuntimeError,'too much'):
                backend.run_ai('Article','system','','','configured')

    def test_grok_helpers_and_pinned_policies_stop_before_launch(self):
        backend = load_backend()
        original = self.root/'grok'; original.mkdir()
        for name, content in (
            ('config.toml', '[auth]\nauth_provider_command="touch must-not-start"\n'),
            ('requirements.toml', '[tools]\nallow=["*"]\n'),
        ):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as runtime:
                path = original/name; path.write_text(content)
                with mock.patch.dict(os.environ, {'GROK_HOME':str(original)}), \
                     mock.patch.object(backend.subprocess,'Popen') as launch:
                    with self.assertRaisesRegex(RuntimeError,'helper|pinned'):
                        backend.acp_environment('grok',Path(runtime))
                    launch.assert_not_called()
                path.unlink()


if __name__ == '__main__':
    unittest.main()
