"""Provider defaults must respect user configuration without silent substitution."""

from contextlib import redirect_stdout
import io
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest import mock

from test_ranking import load_backend, isolate_backend, NOW


class CapturedInput(io.StringIO):
    def close(self):
        self.captured = self.getvalue()
        super().close()


class ProviderTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.backend = load_backend()
        isolate_backend(self.backend, temporary.name)
        self.backend.AGENT_PATH = self.base / "selected-agent"
        self.backend.AGENT_PATH.write_text("codex\n")
        patcher = mock.patch.object(self.backend, "codex_path", return_value="/test/codex")
        self.codex_path = patcher.start()
        self.addCleanup(patcher.stop)

    def test_new_profile_defaults_to_configured_and_saved_presets_are_preserved(self):
        self.assertEqual(self.backend.default_setup_profile()["ai"]["system_model"], "")
        for preset in ("fast", "balanced", "thorough"):
            with self.subTest(preset=preset):
                profile = self.backend.default_setup_profile()
                profile["version"] = 6
                profile["ai"].pop("system_model")
                profile["ai"].pop("system_effort")
                profile["ai"]["system_preset"] = preset
                normalized = self.backend.normalize_setup_profile(profile)
                expected = self.backend.system_ai_configuration(preset)
                self.assertEqual(normalized["ai"]["system_model"], expected["model"])
                self.assertEqual(normalized["ai"]["system_effort"], expected["effort"])
                self.assertNotIn("system_preset", normalized["ai"])

    def test_configured_choice_round_trips_through_export_and_import(self):
        self.backend.save_setup_profile(json.dumps(self.backend.default_setup_profile()))
        destination = self.base / "profile.json"
        self.backend.export_setup_profile(str(destination))
        exported = json.loads(destination.read_text())
        self.assertEqual(exported["profile"]["ai"]["system_model"], "")
        self.assertEqual(exported["profile"]["version"], self.backend.SETUP_PROFILE_VERSION)
        self.assertNotIn("system_ai_status", exported["profile"])
        self.backend.set_system_ai_preset("balanced")
        self.backend.import_setup_profile(str(destination))
        self.assertEqual(self.backend.load_setup_profile()["ai"]["system_model"], "")

    def test_no_selected_agent_never_falls_back_to_installed_codex(self):
        self.backend.AGENT_PATH.unlink()
        self.assertEqual(self.backend.selected_agent(), "")
        status = self.backend.system_ai_status()
        self.assertEqual(status["status"], "unset")
        self.assertFalse(status["available"])
        self.codex_path.assert_not_called()
        self.backend.AGENT_PATH.write_text("\n")
        self.assertEqual(self.backend.system_ai_status()["status"], "unset")

    def test_unsupported_and_missing_agents_are_reported_without_starting_anything(self):
        with mock.patch.object(self.backend.subprocess, "Popen") as process:
            for agent, label in (("opencode", "OpenCode"), ("something-custom", "something-custom")):
                self.backend.AGENT_PATH.write_text(agent)
                status = self.backend.system_ai_status()
                self.assertEqual(status["status"], "unsupported")
                self.assertIn(label, status["message"])
                with self.assertRaisesRegex(RuntimeError, "does not support"):
                    self.backend.run_system_ai_stream("Article", "configured", lambda delta: None)
            self.backend.AGENT_PATH.write_text("codex")
            self.codex_path.return_value = ""
            self.assertEqual(self.backend.system_ai_status()["status"], "missing")
            process.assert_not_called()

    def fake_stream(self, model="my-model", provider="my-provider", effort="medium", failure=False):
        messages = [
            {"id": 1, "result": {}},
            {"id": 2, "result": {"thread": {"id": "fixture-thread"}, "model": model,
                                  "modelProvider": provider, "reasoningEffort": effort}},
            {"id": 3, "result": {}},
            {"method": "item/started", "params": {"item": {
                "id": "commentary", "type": "agentMessage", "phase": "commentary"}}},
            {"method": "item/agentMessage/delta", "params": {
                "itemId": "commentary", "delta": "Progress must stay hidden"}},
            {"method": "item/started", "params": {"item": {
                "id": "final", "type": "agentMessage", "phase": "final_answer"}}},
            {"method": "item/agentMessage/delta", "params": {
                "itemId": "final", "delta": "A source-bound summary."}},
            {"method": "turn/completed", "params": {"turn": {
                "status": "failed" if failure else "completed", "error": {"message": "fixture failure"}}}},
        ]
        process = SimpleNamespace(
            stdin=CapturedInput(), stdout=io.StringIO("\n".join(map(json.dumps, messages)) + "\n"),
            stderr=io.StringIO(), poll=mock.Mock(return_value=None), terminate=mock.Mock(),
            wait=mock.Mock(return_value=0), kill=mock.Mock(),
        )
        return process

    def test_configured_stream_omits_all_model_and_reasoning_overrides(self):
        process = self.fake_stream()
        deltas = []
        with mock.patch.object(self.backend.subprocess, "Popen", return_value=process) as launch:
            answer, label = self.backend.run_system_ai_stream("Fixture article", "configured", deltas.append)
        self.assertEqual(launch.call_args.args[0], ["/test/codex", "app-server", "--stdio"])
        requests = [json.loads(line) for line in process.stdin.captured.splitlines()]
        thread = next(request["params"] for request in requests if request["method"] == "thread/start")
        turn = next(request["params"] for request in requests if request["method"] == "turn/start")
        self.assertNotIn("model", thread)
        self.assertNotIn("modelProvider", thread)
        self.assertNotIn("effort", turn)
        self.assertEqual(thread["sandbox"], "read-only")
        self.assertEqual(thread["approvalPolicy"], "never")
        self.assertTrue(thread["ephemeral"])
        self.assertFalse(thread["allowProviderModelFallback"])
        self.assertEqual(deltas, ["A source-bound summary."])
        self.assertEqual(answer, deltas[0])
        self.assertEqual(label, "System AI · Codex · my-model · my-provider · medium")
        process.terminate.assert_called_once()

    def test_explicit_preset_still_pins_model_and_effort(self):
        process = self.fake_stream()
        with mock.patch.object(self.backend.subprocess, "Popen", return_value=process) as launch:
            _, label = self.backend.run_system_ai_stream("Fixture article", "thorough", lambda delta: None)
        selected = self.backend.system_ai_configuration("thorough")
        command = launch.call_args.args[0]
        self.assertIn("model=" + json.dumps(selected["model"]), command)
        self.assertIn('model_reasoning_effort="high"', command)
        requests = [json.loads(line) for line in process.stdin.captured.splitlines()]
        thread = next(request["params"] for request in requests if request["method"] == "thread/start")
        turn = next(request["params"] for request in requests if request["method"] == "turn/start")
        self.assertEqual(thread["model"], selected["model"])
        self.assertEqual(turn["effort"], "high")
        self.assertEqual(label, self.backend.system_ai_provider_label("thorough"))

    def test_failed_stream_cleans_up_process_and_reports_provider_error(self):
        process = self.fake_stream(failure=True)
        with mock.patch.object(self.backend.subprocess, "Popen", return_value=process):
            with self.assertRaisesRegex(RuntimeError, "fixture failure"):
                self.backend.run_system_ai_stream("Fixture", "configured", lambda delta: None)
        process.terminate.assert_called_once()
        process.wait.assert_called_once()

    def test_nonstream_configured_request_uses_the_same_default_resolution(self):
        with mock.patch.object(self.backend, "run_system_ai_stream", return_value=("Answer", "Resolved model")) as stream:
            self.assertEqual(self.backend.run_system_ai("Article", "configured"), ("Answer", "Resolved model"))
        self.assertEqual(stream.call_args.args[:2], ("Article", "configured"))

    def test_custom_model_and_reasoning_round_trip_and_reset(self):
        self.backend.save_setup_profile(json.dumps(self.backend.default_setup_profile()))
        selection = {"model": "provider/future-model:v2", "effort": "deeper"}
        saved = self.backend.set_system_ai_model(json.dumps(selection))["profile"]
        self.assertEqual(saved["ai"]["system_model"], selection["model"])
        self.assertEqual(saved["ai"]["system_effort"], "deeper")
        self.assertNotIn("system_preset", saved["ai"])
        destination = self.base / "custom-export.json"
        self.backend.export_setup_profile(str(destination))
        self.backend.set_system_ai_model('{"model":"","effort":""}')
        self.assertEqual(self.backend.load_setup_profile()["ai"]["system_model"], "")
        self.backend.import_setup_profile(str(destination))
        self.assertEqual(self.backend.load_setup_profile(), saved)

    def test_invalid_model_selections_do_not_mutate_profile(self):
        self.backend.save_setup_profile(json.dumps(self.backend.default_setup_profile()))
        before = self.backend.load_setup_profile()
        for choice in [{"model": "--model"}, {"model": "model\nnext"}, {"model": "a" * 201},
                       {"model": 42}, {"model": "", "effort": "high"},
                       {"model": "valid", "effort": "bad effort"}]:
            with self.subTest(choice=choice), self.assertRaises(ValueError):
                self.backend.set_system_ai_model(json.dumps(choice))
            self.assertEqual(self.backend.load_setup_profile(), before)

    def test_custom_stream_overrides_only_explicit_settings_and_labels_effective_model(self):
        for effort in ("", "deeper"):
            with self.subTest(effort=effort):
                choice = {"model": "future-model", "effort": effort}
                process = self.fake_stream(model="future-model", effort=effort or "medium")
                with mock.patch.object(self.backend.subprocess, "Popen", return_value=process) as launch:
                    _, label = self.backend.run_system_ai_stream("Article", choice, lambda delta: None)
                requests = [json.loads(line) for line in process.stdin.captured.splitlines()]
                thread = next(x["params"] for x in requests if x["method"] == "thread/start")
                turn = next(x["params"] for x in requests if x["method"] == "turn/start")
                self.assertEqual(thread["model"], "future-model")
                self.assertFalse(thread["allowProviderModelFallback"])
                self.assertIn('model="future-model"', launch.call_args.args[0])
                if effort:
                    self.assertEqual(turn["effort"], effort)
                else:
                    self.assertNotIn("effort", turn)
                    self.assertFalse(any("model_reasoning_effort" in arg for arg in launch.call_args.args[0]))
                self.assertIn("future-model · my-provider", label)
                self.assertFalse(self.backend.summary_cache_allowed("system", choice))

    def test_cli_uses_saved_model_and_model_override_drops_saved_effort(self):
        self.backend.save_setup_profile(json.dumps(self.backend.default_setup_profile()))
        self.backend.set_system_ai_model('{"model":"saved","effort":"high"}')
        args = SimpleNamespace(system_preset=None, system_model=None, system_effort=None)
        choice = self.backend.ai_choice_from_args(args)
        self.assertEqual((choice["model"], choice["effort"]), ("saved", "high"))
        args.system_model = "another"
        choice = self.backend.ai_choice_from_args(args)
        self.assertEqual((choice["model"], choice["effort"]), ("another", ""))
        args.system_model = ""
        self.assertEqual(self.backend.ai_choice_from_args(args)["model"], "")

    def catalog_process(self, results):
        process = self.fake_stream()
        messages = [{"id": 1, "result": {}}]
        messages.extend({"id": index + 2, "result": result} for index, result in enumerate(results))
        process.stdout = io.StringIO("\n".join(map(json.dumps, messages)) + "\n")
        return process

    def test_discovery_paginates_filters_and_never_starts_inference(self):
        row = {"model": "future-model", "displayName": "Future model", "description": "From the agent",
               "supportedReasoningEfforts": [{"reasoningEffort": "deeper", "description": "More thought"}]}
        process = self.catalog_process([
            {"data": [row, dict(row), {"model": "hidden", "hidden": True},
                      {"model": "audio", "inputModalities": ["audio"]},
                      {"model": "bad model"}], "nextCursor": "next-page"},
            {"data": [{"model": "second-model"}], "nextCursor": None},
        ])
        with mock.patch.object(self.backend.subprocess, "Popen", return_value=process):
            models = self.backend.discover_codex_models()
        self.assertEqual([m["value"] for m in models], ["future-model", "second-model"])
        self.assertEqual(models[0]["efforts"][0]["value"], "deeper")
        requests = [json.loads(line) for line in process.stdin.captured.splitlines()]
        self.assertEqual([r["method"] for r in requests], ["initialize", "initialized", "model/list", "model/list"])
        self.assertEqual(requests[-1]["params"]["cursor"], "next-page")
        process.terminate.assert_called_once()

    def test_discovery_handles_invalid_catalog_eof_and_timeout_with_cleanup(self):
        for results in ([], [{"data": "invalid"}], [{"data": [], "nextCursor": "repeat"}] * 2):
            process = self.catalog_process(results)
            with mock.patch.object(self.backend.subprocess, "Popen", return_value=process), self.assertRaises(RuntimeError):
                self.backend.discover_codex_models()
            process.terminate.assert_called_once()
        process = self.catalog_process([])
        with mock.patch.object(self.backend.subprocess, "Popen", return_value=process), \
                mock.patch.object(self.backend.time, "monotonic", side_effect=[0, 16]), \
                self.assertRaisesRegex(RuntimeError, "timed out"):
            self.backend.discover_codex_models()
        process.terminate.assert_called_once()

    def test_catalog_cache_refresh_failure_and_agent_changes(self):
        catalog = [{"value": "from-agent", "label": "From agent", "efforts": []}]
        with mock.patch.object(self.backend, "discover_codex_models", return_value=catalog) as discover:
            self.assertFalse(self.backend.ai_models()["cached"])
            self.assertTrue(self.backend.ai_models()["cached"])
            self.assertEqual(discover.call_count, 1)
            self.backend.ai_models(refresh=True)
            self.assertEqual(discover.call_count, 2)
        with mock.patch.object(self.backend, "discover_codex_models", side_effect=RuntimeError("Retry")):
            failed = self.backend.ai_models(refresh=True)
        self.assertFalse(failed["ok"])
        self.assertTrue(failed["stale"])
        self.assertEqual(failed["models"], catalog)
        self.assertTrue(self.backend.ai_models()["cached"])
        self.backend.AGENT_PATH.write_text("opencode")
        self.assertEqual(self.backend.ai_models()["models"], [])

    def test_catalog_cache_expiry_and_cold_failure(self):
        with mock.patch.object(self.backend, "discover_codex_models", side_effect=RuntimeError("Unavailable")):
            self.assertFalse(self.backend.ai_models()["stale"])
        with mock.patch.object(self.backend, "discover_codex_models", return_value=[]) as discover:
            self.backend.ai_models()
            path = self.backend.STATE_DIR / "ai-models.json"
            cache = json.loads(path.read_text())
            cache["fetched_at"] -= 901
            path.write_text(json.dumps(cache))
            self.backend.ai_models()
            self.assertEqual(discover.call_count, 2)

    def add_cached_article(self, preset):
        key, _ = self.backend.summary_provider_details("system", "", preset)
        conn = self.backend.db()
        with conn:
            conn.execute(
                "INSERT INTO articles(id,url,title,source,published_ts,fetched_ts,ai_summary,ai_provider) "
                "VALUES ('story','https://example.test/story','Fixture','Example',?,?,?,?)",
                (NOW, NOW, "Old model output", key),
            )
        conn.close()

    def test_configured_requests_do_not_replay_a_summary_from_previous_configuration(self):
        self.add_cached_article("configured")
        with mock.patch.object(self.backend, "summary_prompt", return_value="Fixture"), \
             mock.patch.object(self.backend, "run_ai", side_effect=[("New output", "Model A"), ("Other output", "Model B")]) as ai:
            for label in ("Model A", "Model B"):
                result = self.backend.summarize("story", "system", "", "", "configured", False)
                self.assertFalse(result["cached"])
                self.assertEqual(result["provider"], label)
        self.assertEqual(ai.call_count, 2)

    def test_streaming_configured_request_does_not_replay_cached_output(self):
        self.add_cached_article("configured")
        events = []
        with mock.patch.object(self.backend, "summary_prompt", return_value="Fixture"), \
             mock.patch.object(self.backend, "run_ai_stream", return_value=("New output", "Resolved model")), \
             mock.patch.object(self.backend, "emit_stream_event", side_effect=lambda event, **data: events.append((event, data))):
            self.backend.summarize_stream("story", "system", "", "", "configured", False)
        self.assertFalse(events[0][1]["cached"])
        self.assertEqual(events[-1][0], "done")
        self.assertEqual(events[-1][1]["provider"], "Resolved model")
        self.assertFalse(events[-1][1]["cached"])

    def test_explicit_preset_retains_saved_summary_replay(self):
        self.add_cached_article("balanced")
        with mock.patch.object(self.backend, "run_ai") as ai:
            result = self.backend.summarize("story", "system", "", "", "balanced", False)
        self.assertTrue(result["cached"])
        self.assertEqual(result["text"], "Old model output")
        ai.assert_not_called()

    def test_unsupported_agent_fails_before_fetching_article_or_replaying_cache(self):
        self.add_cached_article("balanced")
        self.backend.AGENT_PATH.write_text("opencode")
        with mock.patch.object(self.backend, "summary_prompt") as prompt:
            with self.assertRaisesRegex(RuntimeError, "OpenCode"):
                self.backend.summarize("story", "system", "", "", "balanced", False)
        prompt.assert_not_called()

    def test_setup_and_profile_status_are_read_only_and_refresh_agent_choice(self):
        before = self.backend.AGENT_PATH.read_text()
        self.assertEqual(self.backend.setup_state()["system_ai_status"]["status"], "available")
        self.assertEqual(self.backend.AGENT_PATH.read_text(), before)
        self.backend.AGENT_PATH.write_text("opencode")
        self.assertEqual(self.backend.curation_profile()["system_ai_status"]["status"], "unsupported")


if __name__ == "__main__":
    unittest.main()
