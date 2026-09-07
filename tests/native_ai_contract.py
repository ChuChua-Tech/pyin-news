#!/usr/bin/env python3
"""Run installed agents against a fake model, without accounts or outside network.

Usage: python tests/native_ai_contract.py [codex|claude|gemini|grok ...]
Requires Linux, Bubblewrap and the selected installed agents. Python 3.14 can
decode native request compression. This is separate from the fast unit suite.
"""

from __future__ import annotations

import ctypes
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
from test_ranking import load_backend, isolate_backend

ANSWER = "The library opens on Monday."
PRIVATE = "PYIN_NATIVE_PRIVATE_CANARY_947126"


def response_events(agent, attack, private_path):
    if agent == "codex":
        item = ({"type":"function_call", "id":"fc_test", "call_id":"call_test", "name":"exec_command",
                 "arguments":json.dumps({"cmd":"cat " + str(private_path)}), "status":"completed"} if attack else
                {"type":"message", "id":"msg_test", "role":"assistant", "status":"completed",
                 "content":[{"type":"output_text", "text":ANSWER, "annotations":[]}]})
        events = [{"type":"response.created", "response":{"id":"r", "status":"in_progress", "output":[]}},
                  {"type":"response.output_item.added", "output_index":0, "item":item}]
        if not attack:
            events.append({"type":"response.output_text.delta", "item_id":"msg_test", "output_index":0,
                           "content_index":0, "delta":ANSWER})
        events.extend([{"type":"response.output_item.done", "output_index":0, "item":item},
                       {"type":"response.completed", "response":{"id":"r", "status":"completed", "output":[item],
                        "usage":{"input_tokens":10, "output_tokens":5, "total_tokens":15}}}])
        return [(None,event) for event in events]
    if agent == "gemini":
        part = ({"functionCall":{"name":"read_file", "args":{"file_path":str(private_path)}}}
                if attack else {"text":ANSWER})
        return [(None,{"candidates":[{"content":{"parts":[part], "role":"model"}, "finishReason":"STOP", "index":0}],
                       "usageMetadata":{"promptTokenCount":10, "candidatesTokenCount":5, "totalTokenCount":15},
                       "modelVersion":"fixture"})]
    if agent == "grok":
        delta = ({"role":"assistant", "tool_calls":[{"index":0, "id":"call_test", "type":"function",
                  "function":{"name":"read_file", "arguments":json.dumps({"file_path":str(private_path)})}}]}
                 if attack else {"role":"assistant", "content":ANSWER})
        return [(None,{"id":"test", "object":"chat.completion.chunk", "created":1, "model":"fixture",
                        "choices":[{"index":0, "delta":delta, "finish_reason":None}]}),
                (None,{"id":"test", "object":"chat.completion.chunk", "created":1, "model":"fixture",
                        "choices":[{"index":0, "delta":{}, "finish_reason":"tool_calls" if attack else "stop"}],
                        "usage":{"prompt_tokens":10, "completion_tokens":5, "total_tokens":15}})]
    block = {"type":"tool_use", "id":"tool_test", "name":"Read", "input":{}} if attack else {"type":"text", "text":""}
    delta = ({"type":"input_json_delta", "partial_json":json.dumps({"file_path":str(private_path)})}
             if attack else {"type":"text_delta", "text":ANSWER})
    events = [
        {"type":"message_start", "message":{"id":"test", "type":"message", "role":"assistant", "model":"fixture",
         "content":[], "stop_reason":None, "stop_sequence":None, "usage":{"input_tokens":10, "output_tokens":0}}},
        {"type":"content_block_start", "index":0, "content_block":block},
        {"type":"content_block_delta", "index":0, "delta":delta},
        {"type":"content_block_stop", "index":0},
        {"type":"message_delta", "delta":{"stop_reason":"tool_use" if attack else "end_turn", "stop_sequence":None},
         "usage":{"output_tokens":5}}, {"type":"message_stop"}]
    return [(event["type"],event) for event in events]


def worker(descriptor_path):
    descriptor = json.loads(Path(descriptor_path).read_text())
    agent, executable = descriptor["agent"], descriptor["executable"]
    base = Path(descriptor_path).parent
    private_path = Path.home()/"Documents/private.txt"
    private_path.parent.mkdir(parents=True)
    private_path.write_text(PRIVATE)
    (Path.home()/"AGENTS.md").write_text(PRIVATE)
    libc = ctypes.CDLL(None, use_errno=True)
    requests = []
    state = {"attack":False}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            self.send_response(200); self.end_headers()
            self.wfile.write(b'{"data":[],"models":[]}')

        def do_POST(self):
            raw = self.rfile.read(int(self.headers["Content-Length"]))
            if self.headers.get("Content-Encoding") == "zstd":
                from compression import zstd
                raw = zstd.decompress(raw)
            request = json.loads(raw)
            requests.append(request)
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            for name, event in response_events(agent, state["attack"] and len(requests)==1, private_path):
                prefix = ("event: " + name + "\n") if name else ""
                self.wfile.write((prefix + "data: " + json.dumps(event) + "\n\n").encode())
            if agent == "grok":
                self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()

    server = ThreadingHTTPServer(("127.0.0.1",0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    endpoint = f"http://127.0.0.1:{server.server_port}"
    original = base/"original"; original.mkdir()
    if agent == "codex":
        config = Path.home()/".codex"; config.mkdir()
        (config/"AGENTS.md").write_text(PRIVATE)
        (config/"config.toml").write_text('model="gpt-6-astra"\nmodel_reasoning_effort="ultra"\nmodel_provider="fixture"\n'
            '[model_providers.fixture]\nname="Fixture"\nbase_url="'+endpoint+'/v1"\nwire_api="responses"\n'
            'requires_openai_auth=false\nsupports_websockets=false\n[mcp_servers.canary]\n'
            'command="/usr/bin/touch"\nargs=['+json.dumps(str(base/"startup-marker"))+']\n')
    elif agent == "claude":
        (original/"settings.json").write_text(json.dumps({"hooks":{"SessionStart":[{"hooks":[{
            "type":"command", "command":"touch " + str(base/"startup-marker")}]}]}}))
        (original/"CLAUDE.md").write_text(PRIVATE)
        (original/".claude.json").write_text(json.dumps({"projects":{"private":PRIVATE}}))
        os.environ.update({"CLAUDE_CONFIG_DIR":str(original), "ANTHROPIC_API_KEY":"dummy-key",
                           "ANTHROPIC_BASE_URL":endpoint})
    elif agent == "gemini":
        config = original/".gemini"; config.mkdir()
        (config/"settings.json").write_text(json.dumps({"security":{"auth":{"selectedType":"gemini-api-key"}},
            "model":{"name":"fixture"}, "context":{"fileName":["GEMINI.md"]},
            "hooksConfig":{"enabled":True}, "mcpServers":{"canary":{"command":"touch",
            "args":[str(base/"startup-marker")]}}}))
        (config/"GEMINI.md").write_text(PRIVATE)
        (config/".env").write_text("UNRELATED_SECRET="+PRIVATE)
        os.environ.update({"GEMINI_CLI_HOME":str(original), "GEMINI_API_KEY":"dummy-key",
                           "GOOGLE_GEMINI_BASE_URL":endpoint})
    else:
        (original/"config.toml").write_text('[models]\ndefault="fixture"\n[model.fixture]\n'
            'model="fixture"\nbase_url="'+endpoint+'/v1"\napi_key="dummy-key"\nmax_retries=0\n'
            '[plugins]\npaths=['+json.dumps(str(base/"startup-marker"))+']\n')
        (original/"GROK.md").write_text(PRIVATE)
        os.environ.update({"GROK_HOME":str(original)})

    backend = load_backend()
    isolate_backend(backend,base/"backend")
    backend.system_agent_path = lambda name: executable
    backend.codex_path = lambda: executable
    backend.claude_path = lambda: executable
    backend.CLAUDE_SUMMARY_TIMEOUT_SECONDS = backend.ACP_SUMMARY_TIMEOUT_SECONDS = 30
    cases = [("summary", False, {}), ("forced tool", True, {})]
    if agent == "codex":
        cases.append(("selected model default", False, {"model":"gpt-5.4-mini", "effort":""}))
    for case, attack, choice in cases:
        requests.clear(); state["attack"] = attack
        watch = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        assert watch >= 0 and libc.inotify_add_watch(watch,os.fsencode(private_path),1) >= 0
        try:
            if agent == "codex":
                result = backend.codex_exchange("Summarize: the library opens on Monday.",
                                                choice or {"model":"","effort":""}, lambda text:None)
            elif agent == "gemini":
                result = backend.acp_exchange(agent,"Summarize: the library opens on Monday.", {"model":"fixture","effort":""}, lambda text:None)
            else:
                result = backend.messages_exchange(agent,"Summarize: the library opens on Monday.", {"model":"fixture","effort":""}, lambda text:None)
            outcome = result.get("answer")
        except RuntimeError as error:
            if not attack:
                raise
            outcome = "stopped: " + str(error)
        try:
            read_events = os.read(watch,4096)
        except BlockingIOError:
            read_events = b""
        private_path.read_bytes()
        assert os.read(watch,4096), "file-read detector failed its positive control"
        os.close(watch)
        assert not read_events, "native agent accessed the private file"
        assert requests, "agent did not reach the fake model"
        assert PRIVATE not in json.dumps(requests), "personal context entered the model request"
        for request in requests:
            for tool in request.get("tools",[]):
                assert agent == "gemini" and set(tool) <= {"functionDeclarations"} and not tool.get("functionDeclarations"), "tools were offered"
        assert not (base/"startup-marker").exists(), "agent customization started"
        if not attack:
            assert outcome == ANSWER, outcome
        if choice.get("model"):
            assert all(request.get("model") == choice["model"] for request in requests), "selected model changed"
            assert all(request.get("reasoning",{}).get("effort") != "ultra" for request in requests), "inherited another model's effort"
        print(json.dumps({"agent":agent,"case":case, "tools":0,
                          "private_file_reads":0,"private_context_sent":False,"outcome":outcome}),flush=True)
    server.shutdown()


def main():
    if len(sys.argv)>1 and sys.argv[1]=="--inside":
        worker(sys.argv[2]); return
    agents = sys.argv[1:] or ["codex","claude","gemini","grok"]
    assert all(agent in {"codex","claude","gemini","grok"} for agent in agents)
    backend = load_backend()
    for agent in agents:
        native_path = backend.system_agent_path(agent)
        if not native_path:
            raise RuntimeError(f"Install {agent} before running its native contract test")
        executable = Path(native_path).resolve(strict=True)
        with tempfile.TemporaryDirectory(prefix="pyin-native-contract-") as temporary:
            base = Path(temporary)
            private_root = base/"user"; private_root.mkdir()
            descriptor = base/"test.json"
            descriptor.write_text(json.dumps({"agent":agent,"executable":str(executable)}))
            command = [shutil.which("bwrap"),"--die-with-parent","--unshare-net","--unshare-pid","--unshare-ipc",
                       "--ro-bind","/","/","--tmpfs","/tmp","--bind",str(base),str(base),
                       "--bind",str(private_root),str(Path.home()),"--tmpfs","/run/user",
                       "--ro-bind",str(ROOT),str(ROOT)]
            bundles = {backend.news_ai._runtime_bundle(executable),Path(sys.base_prefix)}
            node = shutil.which("node")
            if node:
                bundles.add(backend.news_ai._runtime_bundle(Path(node).resolve()))
            for bundle in sorted(bundles):
                command += ["--ro-bind",str(bundle),str(bundle)]
            command += ["--proc","/proc","--dev","/dev","--chdir",str(base),sys.executable,
                        str(Path(__file__).resolve()),"--inside",str(descriptor)]
            environment = {key:os.environ[key] for key in ("HOME","LANG","LC_ALL") if key in os.environ}
            environment["PATH"] = (str(Path(node).resolve().parent)+":" if node else "") + "/usr/bin:/bin"
            subprocess.run(command,env=environment,check=True,timeout=100)


if __name__ == "__main__":
    main()
