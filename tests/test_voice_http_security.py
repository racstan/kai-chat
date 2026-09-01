import http.client
import importlib.util
import json
import os
import socket
import tempfile
import threading
import time
import unittest


VOICE_HELPER = os.path.join(
    os.path.dirname(__file__), "..", "org.kde.plasma.kdeaichat", "contents", "ui", "voice", "voice_helper.py"
)
spec = importlib.util.spec_from_file_location("voice_helper_http", VOICE_HELPER)
voice_helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voice_helper)


class TestVoiceHttpSecurity(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.token_path = os.path.join(self.temp_dir.name, "token")
        self.token = voice_helper.load_or_create_http_token(self.token_path)
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            self.port = sock.getsockname()[1]
        self.helper = voice_helper.VoiceHelper()
        self.thread = threading.Thread(
            target=self.helper.run_http_server,
            args=(self.port, "stt", self.token_path),
            daemon=True,
        )
        self.thread.start()
        for _ in range(100):
            if self.helper.http_server is not None:
                return
            time.sleep(0.01)
        self.fail("voice HTTP server did not start")

    def tearDown(self):
        if self.helper.http_server is not None:
            self.helper.http_server.shutdown()
        self.thread.join(timeout=3)
        self.temp_dir.cleanup()

    def request(self, method, path, body=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=3)
        try:
            connection.request(method, path, body=body, headers=headers or {})
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def test_status_requires_token(self):
        status, _ = self.request("GET", "/status")
        self.assertEqual(status, 403)

    def test_status_accepts_private_token(self):
        status, body = self.request("GET", "/status", headers={"X-KDE-AI-Chat-Token": self.token})
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["status"], "idle")

    def test_origin_and_command_allowlist_are_enforced(self):
        headers = {
            "Content-Type": "application/json",
            "X-KDE-AI-Chat-Token": self.token,
            "Origin": "http://evil.example",
        }
        status, _ = self.request("POST", "/command", body=json.dumps({"cmd": "play_audio"}), headers=headers)
        self.assertEqual(status, 403)

        headers["Origin"] = "http://127.0.0.1"
        status, _ = self.request("POST", "/command", body=json.dumps({"cmd": "play_audio"}), headers=headers)
        self.assertEqual(status, 400)

    def test_token_file_is_private(self):
        self.assertEqual(os.stat(self.token_path).st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
