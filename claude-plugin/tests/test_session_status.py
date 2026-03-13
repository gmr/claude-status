#!/usr/bin/env python3
"""Tests for the Claude Status session-status hook script."""
import json
import os
import pathlib
import subprocess
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parent.parent / "plugins" / "claude-status" / "scripts" / "session-status.py"


class SessionStatusTestCase(unittest.TestCase):
    """Base class with helpers for session-status hook tests."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.project_dir = pathlib.Path(self.tmpdir) / "projects" / "test-project"
        self.project_dir.mkdir(parents=True)
        self.session_id = "test-session-abc123"
        self.status_file = self.project_dir / f"{self.session_id}.cstatus"
        self.transcript = self.project_dir / "transcript.jsonl"

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def make_input(self, event, **extra):
        payload = {
            "hook_event_name": event,
            "session_id": self.session_id,
            "transcript_path": str(self.transcript),
            "cwd": "/tmp/test-cwd",
        }
        payload.update(extra)
        return json.dumps(payload)

    def run_hook(self, event, **extra):
        hook_input = self.make_input(event, **extra)
        env = os.environ.copy()
        env["CLAUDE_PID"] = "12345"
        # Stub notifyutil
        stub_bin = pathlib.Path(self.tmpdir) / "bin"
        stub_bin.mkdir(exist_ok=True)
        notifyutil = stub_bin / "notifyutil"
        notifyutil.write_text("#!/bin/bash\nexit 0\n")
        notifyutil.chmod(0o755)
        ps_stub = stub_bin / "ps"
        ps_stub.write_text("#!/bin/bash\necho 1\n")
        ps_stub.chmod(0o755)
        env["PATH"] = f"{stub_bin}:{env.get('PATH', '')}"
        result = subprocess.run(
            ["/usr/bin/env", "python3", str(SCRIPT)],
            input=hook_input, capture_output=True, text=True,
            env=env, timeout=10,
        )
        return result

    def read_status(self):
        return json.loads(self.status_file.read_text())


class TestEventStateMapping(SessionStatusTestCase):
    """Basic event to state mapping."""

    def test_session_start_sets_idle(self):
        self.run_hook("SessionStart")
        self.assertEqual(self.read_status()["state"], "idle")

    def test_user_prompt_submit_sets_active_thinking(self):
        self.run_hook("UserPromptSubmit")
        status = self.read_status()
        self.assertEqual(status["state"], "active")
        self.assertEqual(status["activity"], "thinking")

    def test_pre_tool_use_sets_active_with_tool_name(self):
        self.run_hook("PreToolUse", tool_name="Edit")
        status = self.read_status()
        self.assertEqual(status["state"], "active")
        self.assertEqual(status["activity"], "Edit")

    def test_post_tool_use_sets_active(self):
        self.run_hook("PostToolUse", tool_name="Edit")
        self.assertEqual(self.read_status()["state"], "active")

    def test_permission_request_sets_waiting(self):
        self.run_hook("PermissionRequest", tool_name="Bash")
        status = self.read_status()
        self.assertEqual(status["state"], "waiting")
        self.assertEqual(status["activity"], "Bash")

    def test_pre_compact_sets_compacting(self):
        self.run_hook("PreCompact", trigger="auto")
        status = self.read_status()
        self.assertEqual(status["state"], "compacting")
        self.assertEqual(status["activity"], "auto")

    def test_stop_sets_idle(self):
        self.run_hook("Stop")
        self.assertEqual(self.read_status()["state"], "idle")

    def test_subagent_start_sets_active(self):
        self.run_hook("SubagentStart", agent_type="Explore")
        status = self.read_status()
        self.assertEqual(status["state"], "active")
        self.assertEqual(status["activity"], "Explore")

    def test_unknown_event_defaults_to_active(self):
        self.run_hook("SomeNewEvent")
        self.assertEqual(self.read_status()["state"], "active")


class TestNotificationSubtypes(SessionStatusTestCase):
    """Notification event sub-type handling."""

    def test_permission_prompt_sets_waiting(self):
        self.run_hook("Notification", notification_type="permission_prompt")
        self.assertEqual(self.read_status()["state"], "waiting")

    def test_elicitation_dialog_sets_waiting(self):
        self.run_hook("Notification", notification_type="elicitation_dialog")
        self.assertEqual(self.read_status()["state"], "waiting")

    def test_idle_prompt_sets_idle(self):
        self.run_hook("Notification", notification_type="idle_prompt")
        self.assertEqual(self.read_status()["state"], "idle")

    def test_idle_prompt_sets_waiting_when_question(self):
        self.transcript.write_text(
            '{"type":"assistant","message":{"role":"assistant",'
            '"content":[{"type":"text","text":"What would you like help with?"}],'
            '"stop_reason":"end_turn"}}\n'
        )
        self.run_hook("Notification", notification_type="idle_prompt")
        status = self.read_status()
        self.assertEqual(status["state"], "waiting")
        self.assertEqual(status["activity"], "question")


class TestSessionEnd(SessionStatusTestCase):
    """SessionEnd removes the status file."""

    def test_session_end_removes_status_file(self):
        self.run_hook("SessionStart")
        self.assertTrue(self.status_file.is_file())
        self.run_hook("SessionEnd")
        self.assertFalse(self.status_file.is_file())


class TestStickyCompacting(SessionStatusTestCase):
    """Compacting state persists through tool-use events."""

    def test_compacting_persists_through_pre_tool_use(self):
        self.run_hook("PreCompact", trigger="auto")
        self.run_hook("PreToolUse", tool_name="Read")
        self.assertEqual(self.read_status()["state"], "compacting")

    def test_compacting_persists_through_post_tool_use(self):
        self.run_hook("PreCompact", trigger="auto")
        self.run_hook("PostToolUse", tool_name="Read")
        self.assertEqual(self.read_status()["state"], "compacting")

    def test_compacting_persists_through_subagent_start(self):
        self.run_hook("PreCompact", trigger="auto")
        self.run_hook("SubagentStart", agent_type="Explore")
        self.assertEqual(self.read_status()["state"], "compacting")

    def test_compacting_persists_through_subagent_stop(self):
        self.run_hook("PreCompact", trigger="auto")
        self.run_hook("SubagentStop")
        self.assertEqual(self.read_status()["state"], "compacting")

    def test_compacting_persists_through_post_tool_use_failure(self):
        self.run_hook("PreCompact", trigger="auto")
        self.run_hook("PostToolUseFailure", tool_name="Bash")
        self.assertEqual(self.read_status()["state"], "compacting")

    def test_compacting_clears_on_permission_request(self):
        self.run_hook("PreCompact", trigger="auto")
        self.run_hook("PermissionRequest", tool_name="Bash")
        self.assertEqual(self.read_status()["state"], "waiting")

    def test_compacting_clears_on_user_prompt_submit(self):
        self.run_hook("PreCompact", trigger="auto")
        self.run_hook("UserPromptSubmit")
        self.assertEqual(self.read_status()["state"], "active")

    def test_compacting_clears_on_stop(self):
        self.run_hook("PreCompact", trigger="auto")
        self.run_hook("Stop")
        self.assertEqual(self.read_status()["state"], "idle")


class TestQuestionDetection(SessionStatusTestCase):
    """Stop/idle_prompt question detection."""

    def _write_transcript(self, text, stop_reason="end_turn"):
        self.transcript.write_text(
            json.dumps({
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [{"type": "text", "text": text}],
                    "stop_reason": stop_reason,
                },
            }) + "\n"
        )

    def test_stop_sets_waiting_when_question(self):
        self._write_transcript("Want me to apply the fix?")
        self.run_hook("Stop")
        status = self.read_status()
        self.assertEqual(status["state"], "waiting")
        self.assertEqual(status["activity"], "question")

    def test_stop_sets_idle_when_no_question(self):
        self._write_transcript("Done! The bug has been fixed.")
        self.run_hook("Stop")
        self.assertEqual(self.read_status()["state"], "idle")

    def test_stop_sets_idle_when_no_transcript(self):
        self.run_hook("Stop")
        self.assertEqual(self.read_status()["state"], "idle")

    def test_stop_detects_question_with_trailing_whitespace(self):
        self._write_transcript("Should I continue?   ")
        self.run_hook("Stop")
        self.assertEqual(self.read_status()["state"], "waiting")

    def test_stop_detects_question_in_last_message_only(self):
        lines = [
            json.dumps({
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [{"type": "text", "text": "Should I proceed?"}],
                    "stop_reason": "end_turn",
                },
            }),
            json.dumps({
                "type": "human",
                "content": [{"type": "text", "text": "Yes"}],
            }),
            json.dumps({
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [{"type": "text", "text": "Done, all applied."}],
                    "stop_reason": "end_turn",
                },
            }),
        ]
        self.transcript.write_text("\n".join(lines) + "\n")
        self.run_hook("Stop")
        self.assertEqual(self.read_status()["state"], "idle")


class TestConfigChange(SessionStatusTestCase):
    """ConfigChange exits without writing."""

    def test_config_change_no_status_file(self):
        self.run_hook("ConfigChange")
        self.assertFalse(self.status_file.is_file())


class TestJsonOutput(SessionStatusTestCase):
    """Output format validation."""

    def test_records_pid(self):
        self.run_hook("SessionStart")
        self.assertEqual(self.read_status()["pid"], 12345)

    def test_cwd_with_spaces(self):
        hook_input = json.dumps({
            "hook_event_name": "SessionStart",
            "session_id": self.session_id,
            "transcript_path": str(self.transcript),
            "cwd": "/tmp/my project/src",
        })
        env = os.environ.copy()
        env["CLAUDE_PID"] = "12345"
        stub_bin = pathlib.Path(self.tmpdir) / "bin"
        stub_bin.mkdir(exist_ok=True)
        (stub_bin / "notifyutil").write_text("#!/bin/bash\nexit 0\n")
        (stub_bin / "notifyutil").chmod(0o755)
        (stub_bin / "ps").write_text("#!/bin/bash\necho 1\n")
        (stub_bin / "ps").chmod(0o755)
        env["PATH"] = f"{stub_bin}:{env.get('PATH', '')}"
        subprocess.run(
            ["/usr/bin/env", "python3", str(SCRIPT)],
            input=hook_input, capture_output=True, text=True,
            env=env, timeout=10,
        )
        self.assertEqual(self.read_status()["cwd"], "/tmp/my project/src")

    def test_handles_missing_tool_name(self):
        self.run_hook("PreToolUse")
        self.assertEqual(self.read_status()["state"], "active")

    def test_handles_missing_notification_type(self):
        self.run_hook("Notification")
        self.assertEqual(self.read_status()["state"], "idle")


if __name__ == "__main__":
    unittest.main()
