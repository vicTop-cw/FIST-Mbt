#!/usr/bin/env python3
"""FIST-Mbt HTTP/SSE Transport Server

Bridges the stdio-based MCP server (MoonBit) to HTTP.
Exposes:
  GET  /health  → Health check
  POST /mcp     → JSON-RPC request → MCP server response
  GET  /sse     → Server-Sent Events stream (notifications)

Usage:
  python scripts/fist-mbt-http.py [port]
  FIST_MCP_PORT=3000 python scripts/fist-mbt-http.py

Environment:
  FIST_MCP_PORT: HTTP port (default 3000)
  FIST_MCP_TRANSPORT: "http" to enable HTTP bridge (otherwise stdio only)
"""

import json
import os
import subprocess
import sys
import time
import threading
import logging
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from queue import Queue, Empty

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("fist-mbt-http")

PORT = int(os.environ.get("FIST_MCP_PORT", 3000))

# Path to compiled MoonBit JS entry (fallback to moon run)
MBT_MAIN_JS = Path(__file__).parent.parent / "target" / "js" / "release" / "build" / "cmd" / "main" / "main.js"
MBT_MAIN_MBT = Path(__file__).parent.parent / "cmd" / "main" / "main.mbt"

# Pending requests awaiting response
_response_queue: Queue = Queue()
_request_id = 0
_request_id_lock = threading.Lock()

# --- SSE event bus -----------------------------------------------------------
# Each SSE connection registers one Queue as a subscriber.
_subscribers: list[Queue] = []
_subscribers_lock = threading.Lock()

SSE_HEARTBEAT_INTERVAL = 15  # seconds


def _publish(event_type: str, payload: dict) -> None:
    """Push an event to every active SSE subscriber."""
    event = {"type": event_type, **payload}
    with _subscribers_lock:
        subscribers = list(_subscribers)
    for q in subscribers:
        try:
            q.put_nowait(event)
        except Exception:
            # Broken/invalid queue; drop this subscriber.
            with _subscribers_lock:
                if q in _subscribers:
                    _subscribers.remove(q)


def _heartbeat_loop() -> None:
    while True:
        time.sleep(SSE_HEARTBEAT_INTERVAL)
        _publish("heartbeat", {"ts": time.time()})


def next_id() -> int:
    global _request_id
    with _request_id_lock:
        _request_id += 1
        return _request_id


class MCPBridge:
    """Bridge to stdio MCP server via subprocess."""

    def __init__(self) -> None:
        self._proc: subprocess.Popen | None = None
        self._reader: threading.Thread | None = None
        self._running = False

    def start(self) -> None:
        if self._running:
            return
        cmd = self._find_command()
        if not cmd:
            log.error("Cannot find FIST-Mbt server entry point")
            sys.exit(1)
        log.info("Starting MCP server: %s", " ".join(cmd))
        self._proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=sys.stderr,
            text=True,
            bufsize=1,
        )
        self._running = True
        self._reader = threading.Thread(target=self._read_loop, daemon=True)
        self._reader.start()

    def _find_command(self) -> list[str] | None:
        if MBT_MAIN_JS.exists():
            return ["node", str(MBT_MAIN_JS)]
        if MBT_MAIN_MBT.exists():
            return ["moon", "run", "cmd/main"]
        # Fallback: try moon directly
        return ["moon", "run", "cmd/main"]

    def _read_loop(self) -> None:
        try:
            while self._running and self._proc and self._proc.stdout:
                line = self._proc.stdout.readline()
                if not line:
                    break
                line = line.strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                    _response_queue.put(msg)
                except json.JSONDecodeError:
                    log.debug("Non-JSON output: %s", line[:200])
        except Exception as e:
            log.error("Reader error: %s", e)
        finally:
            self._running = False

    def send(self, method: str, params: dict | None = None) -> dict | None:
        if not self._proc or not self._proc.stdin:
            return {"error": "Server not running"}
        req_id = next_id()
        request = {
            "jsonrpc": "2.0",
            "id": req_id,
            "method": method,
            "params": params or {},
        }
        try:
            self._proc.stdin.write(json.dumps(request) + "\n")
            self._proc.stdin.flush()
        except BrokenPipeError:
            return {"error": "Server disconnected"}
        # Wait for response with matching id
        deadline = time.time() + 30
        while time.time() < deadline:
            try:
                msg = _response_queue.get(timeout=0.5)
                if msg.get("id") == req_id:
                    return msg
            except Empty:
                continue
        return {"error": "Request timeout"}

    def stop(self) -> None:
        self._running = False
        if self._proc:
            try:
                self._proc.terminate()
                self._proc.wait(timeout=5)
            except Exception:
                self._proc.kill()


bridge = MCPBridge()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        log.info("%s - %s", self.address_string(), format % args)

    def _json_response(self, data: dict, status: int = 200) -> None:
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self) -> None:
        if self.path == "/health":
            self._json_response({
                "status": "ok",
                "product": "FIST-Mbt",
                "transport": "http",
            })
            return
        if self.path == "/events":
            self._handle_sse()
            return
        self._json_response({"error": "Not found"}, status=404)

    def _handle_sse(self) -> None:
        """GET /events: Server-Sent Events stream."""
        queue: Queue = Queue()
        with _subscribers_lock:
            _subscribers.append(queue)
        log.info("SSE subscriber connected (total: %d)", len(_subscribers))
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        try:
            while True:
                try:
                    event = queue.get(timeout=1.0)
                except Empty:
                    continue
                event_type = event.get("type", "message")
                data = json.dumps(event, ensure_ascii=False)
                frame = f"event: {event_type}\ndata: {data}\n\n"
                self.wfile.write(frame.encode("utf-8"))
                self.wfile.flush()
        except (ConnectionResetError, BrokenPipeError):
            pass
        except Exception as e:
            log.debug("SSE stream error: %s", e)
        finally:
            with _subscribers_lock:
                if queue in _subscribers:
                    _subscribers.remove(queue)
            log.info("SSE subscriber disconnected (total: %d)", len(_subscribers))

    def do_POST(self) -> None:
        if self.path != "/mcp":
            self._json_response({"error": "Not found"}, status=404)
            return
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8")
        try:
            request = json.loads(body)
        except json.JSONDecodeError as e:
            self._json_response({"error": f"Invalid JSON: {e}"}, status=400)
            return
        method = request.get("method", "")
        params = request.get("params", {})
        if not method:
            self._json_response({"error": "Missing method"}, status=400)
            return
        response = bridge.send(method, params)
        _publish("request", {"method": method, "ts": time.time()})
        if response is None:
            self._json_response({"error": "No response from server"}, status=502)
        elif "error" in response:
            self._json_response(response, status=502)
        else:
            self._json_response(response)


def main() -> None:
    bridge.start()
    threading.Thread(target=_heartbeat_loop, daemon=True).start()
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    log.info("FIST-Mbt HTTP bridge listening on port %d", PORT)
    log.info("  Health: http://localhost:%d/health", PORT)
    log.info("  MCP:    http://localhost:%d/mcp", PORT)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("Shutting down...")
    finally:
        bridge.stop()
        server.server_close()


if __name__ == "__main__":
    main()
