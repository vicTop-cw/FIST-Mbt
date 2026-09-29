#!/usr/bin/env python3
"""FIST-Mbt HTTP/SSE Transport Server

Bridges the stdio-based MCP server (MoonBit) to HTTP.
Exposes:
  GET  /health  → Health check
  POST /mcp     → JSON-RPC request → MCP server response
  GET  /events  → Server-Sent Events stream (notifications)

Usage:
  python scripts/fist-mbt-http.py [port]        # 位置参数（README「HTTP/SSE 桥」广告的就是这条）
  FIST_MCP_PORT=3000 python scripts/fist-mbt-http.py
  两者都给时**位置参数优先**（命令行比环境更靠近这次调用）。

Environment:
  FIST_MCP_PORT: HTTP port (default 3000)
  FIST_DB_PATH : 传给 server 子进程的库路径（不设置＝server 按自己的默认解析落库）
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

ROOT = Path(__file__).resolve().parent.parent

# 端口解析：位置参数 > FIST_MCP_PORT > 3000。
# BUG-118：README.md:96-97 广告的是 `python scripts/fist-mbt-http.py [port]`，而这里过去
# **只读 env**，位置参数被静默忽略 ⇒ 用户传 3001 仍监听 3000，第二个宿主直接 bind 失败。
def resolve_port(argv, env) -> int:
    raw = argv[0] if argv else env.get("FIST_MCP_PORT", "")
    if not str(raw).strip():
        return 3000
    try:
        p = int(str(raw).strip())
    except ValueError:
        raise SystemExit(
            "FATAL 端口不是整数：%r（用法：python scripts/fist-mbt-http.py [port]，"
            "或 FIST_MCP_PORT=<port>）" % raw)
    if not (1 <= p <= 65535):
        raise SystemExit("FATAL 端口越界（1..65535）：%d" % p)
    return p


PORT = resolve_port(sys.argv[1:], os.environ)

# 现役 MCP 入口产物：cmd/cli（cmd/main 已退役；曾经这里指着 target/js/release/cmd/main，
# 那个路径在本仓根本不存在 ⇒ 每次都退到 `moon run cmd/cli`，而 moon run 重发的 ESM bundle
# 没有 require shim ⇒ ReferenceError: require is not defined，桥接服务从来就没起过 server）。
MAIN_CANDIDATES = (
    Path("_build") / "js" / "debug" / "build" / "cmd" / "cli" / "cli.js",
    Path("target") / "js" / "release" / "build" / "cmd" / "cli" / "cli.js",
)

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
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            cwd=str(ROOT),
        )
        self._running = True
        self._reader = threading.Thread(target=self._read_loop, daemon=True)
        self._reader.start()

    def _find_command(self) -> list[str] | None:
        """现役入口 + `serve` + ESM require shim；找不到产物就点名要跑的 build 命令。

        曾经的两级回退都不可用：① 上一代入口的 release 产物路径——那个 cmd 目标已退役，且本仓
        根本没有那个路径；② `moon run cmd/cli` 会**重新发一遍** bundle，把 patch_esm_main
        注入的 shim 抹掉 ⇒ 起服即 `ReferenceError: require is not defined`。
        """
        for rel in MAIN_CANDIDATES:
            js = ROOT / rel
            if not js.is_file():
                continue
            # moonc ≥0.10.14 对可执行目标输出 ESM，mizchi/sqlite 的 JS 桩用 CJS require（幂等注入）
            import importlib.util
            spec = importlib.util.spec_from_file_location(
                "patch_esm_main", str(ROOT / "scripts" / "patch_esm_main.py"))
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            mod.patch(str(js))
            return [os.environ.get("FIST_NODE", "node"), str(js), "serve"]
        log.error(
            "找不到 MCP 入口产物（试过的候选：%s）⇒ 先跑 `moon build --target js cmd/cli`",
            ", ".join(str(c) for c in MAIN_CANDIDATES))
        return None

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
            # 服务器断连哨兵：唤醒所有等待中的请求（subprocess 退出从未通知 queue）
            _response_queue.put({"error": "Server disconnected"})

    def send(self, method: str, params: dict | None = None) -> dict | None:
        if not self._proc or not self._proc.stdin:
            return {"error": "Server not running"}
        req_id = next_id()
        # 本 server 走 MCP 2026-07-28 形状：每条请求的 params._meta 要带协议版本/客户端身份，
        # 缺了服务端直接拒。HTTP 侧不该要求每个调用方都手抄这段 ⇒ 桥这里补齐（调用方给了就尊重）。
        params = dict(params or {})
        meta = dict(params.get("_meta") or {})
        meta.setdefault("io.modelcontextprotocol/protocolVersion", "2026-07-28")
        meta.setdefault("io.modelcontextprotocol/clientCapabilities", {})
        meta.setdefault("io.modelcontextprotocol/clientInfo",
                        {"name": "fist-mbt-http-bridge", "version": "1.0"})
        params["_meta"] = meta
        request = {
            "jsonrpc": "2.0",
            "id": req_id,
            "method": method,
            "params": params,
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
            except Empty:
                continue
            if msg.get("id") == req_id:
                return msg
            if "error" in msg and "id" not in msg:
                # 服务器断连/错误哨兵（无 id）：立即返回，不必等满 deadline
                return msg
            # 该响应属于其它并发请求：放回队列以免被错误消费；无 id 的通知则丢弃
            if msg.get("id") is not None:
                _response_queue.put(msg)
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
        if not isinstance(request, dict):
            self._json_response({"error": "Request must be a JSON object"}, status=400)
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
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
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
