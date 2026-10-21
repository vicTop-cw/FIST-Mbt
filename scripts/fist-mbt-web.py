#!/usr/bin/env python3
"""FIST-Mbt Web 管理面板 —— M0 只读任务看板 后端

定位：MCP Server 的可视化操作层后端（只读）。复用 scripts/fist-mbt-http.py 的
MCPBridge 直接调用 stdio MCP server，绝不绕过 MCP 直读 SqliteStore。

端点：
  GET  /                     → web/index.html（不存在时返回占位 HTML + 状态页）
  GET  /static/<path>        → web/ 目录下的静态资源（路径穿越 403）
  GET  /api/tasks?ns=<ns>    → list → 平铺数组 → 嵌套树 JSON
  GET  /api/tasks/<task_id>  → get → 单任务详情
  GET  /api/status           → status_summary → 项目脉冲
  GET  /api/events           → SSE：连接即发 snapshot，之后每 15s heartbeat
  GET  /health               → {"ok":true,"server":"fist-mbt-web","mcp_alive":bool}

认证：
  FIST_WEB_TOKEN 设置时校验 `Authorization: Bearer <token>` 或 `?token=<token>`；
  未设置时默认无认证（默认只监听 127.0.0.1）。

用法：
  python scripts/fist-mbt-web.py [port]
  FIST_WEB_PORT=5173 python scripts/fist-mbt-web.py
  两者都给时位置参数优先。

环境：
  FIST_WEB_PORT  : 端口（默认 5173，避开 HTTP 桥的 3000）
  FIST_WEB_TOKEN : 可选访问令牌
  FIST_DB_PATH   : 传给 MCP server 子进程的库路径（默认隔离到系统临时目录）
"""

import json
import logging
import os
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from queue import Empty, Queue

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("fist-mbt-web")

ROOT = Path(__file__).resolve().parent.parent
WEB_DIR = ROOT / "web"

# 复用 fist-mbt-http.py 的 MCPBridge / SSE subscriber / heartbeat 循环（不复制粘贴）。
# 注意：fist-mbt-http.py 顶层的 `PORT = resolve_port(...)` 与全局 `bridge` 在 import 时求值，
# 这里不引入副作用：本文件的 PORT 由自己的 resolve_port 决定，bridge 由本文件新建。
# 文件名带连字符不是合法标识符 ⇒ 用 importlib 从文件路径加载模块。
import importlib.util as _ilu

_http_spec = _ilu.spec_from_file_location(
    "_fist_mbt_http_bridge", str(ROOT / "scripts" / "fist-mbt-http.py"))
assert _http_spec and _http_spec.loader, "无法定位 scripts/fist-mbt-http.py"
_fist_mbt_http = _ilu.module_from_spec(_http_spec)
_http_spec.loader.exec_module(_fist_mbt_http)

MAIN_CANDIDATES = _fist_mbt_http.MAIN_CANDIDATES
MCPBridge = _fist_mbt_http.MCPBridge
_heartbeat_loop = _fist_mbt_http._heartbeat_loop
_publish = _fist_mbt_http._publish
_subscribers = _fist_mbt_http._subscribers
_subscribers_lock = _fist_mbt_http._subscribers_lock


# --- 端口解析：位置参数 > FIST_WEB_PORT > 5173 -----------------------------------
def resolve_port(argv, env) -> int:
    raw = argv[0] if argv else env.get("FIST_WEB_PORT", "")
    if not str(raw).strip():
        return 5173
    try:
        p = int(str(raw).strip())
    except ValueError:
        raise SystemExit(
            "FATAL 端口不是整数：%r（用法：python scripts/fist-mbt-web.py [port]，"
            "或 FIST_WEB_PORT=<port>）" % raw)
    if not (1 <= p <= 65535):
        raise SystemExit("FATAL 端口越界（1..65535）：%d" % p)
    return p


PORT = resolve_port(sys.argv[1:], os.environ)
TOKEN = os.environ.get("FIST_WEB_TOKEN", "").strip()


# --- 产物新鲜度检查：spawn 前确认 cli.js 已构建，缺失则补一次 build -----------------
def ensure_mcp_build() -> None:
    """`_build/js/debug/build/cmd/cli/cli.js` 已存在且新鲜则跳过。

    缺失时执行 `moon build --target js cmd/cli`；仍失败抛出 SystemExit 给可诊断 error，
    绝不静默起服。
    """
    candidate = ROOT / MAIN_CANDIDATES[0]
    if candidate.is_file():
        log.info("MCP 产物已存在（%s），跳过 build", candidate)
        return
    log.warning("MCP 产物缺失，执行 `moon build --target js cmd/cli` ...")
    try:
        proc = subprocess.run(
            ["moon", "build", "--target", "js", "cmd/cli"],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            timeout=300,
        )
    except Exception as e:
        raise SystemExit(f"FATAL `moon build --target js cmd/cli` 异常：{e}")
    if proc.returncode != 0 or not candidate.is_file():
        raise SystemExit(
            f"FATAL `moon build --target js cmd/cli` 退出码 {proc.returncode}，"
            f"且产物 {candidate} 仍不存在。stderr 尾：\n{proc.stderr[-800:]}")
    log.info("MCP 产物构建完成：%s", candidate)


# --- DB 隔离：把 FIST_DB_PATH 交给子进程，避免污染仓库根 fist-mbt.db ---------------
def configure_db_path() -> Path:
    """决定交给 MCP 子进程的 `FIST_DB_PATH`。须在 bridge.start() 之前调用。

    优先级：
      1. 调用方显式设过 `FIST_DB_PATH` —— 照它的。
      2. 复用与 `scripts/fist.py` 同源的隔离库 `temp/fist.db`（BUG-122 同型收口：默认改道
         temp/ 下的隔离库，绝不裸跑往仓库根自举台账 `fist-mbt.db` 塞数据）。
         复用共享隔离库才能让面板在 M0 看到真实任务树。
      3. 兜底 `temp/fist-mbt-web.db`（隔离库不存在时）。

    无论走哪条，都把 `FIST_DB_PATH` **显式**交给子进程（check_demo_isolation 判据）。
    """
    db_path = os.environ.get("FIST_DB_PATH")
    if db_path:
        log.info("FIST_DB_PATH 使用外部指定：%s", db_path)
        return Path(db_path)

    shared = ROOT / "temp" / "fist.db"
    if shared.is_file():
        db_path = str(shared)
        log.info("复用同源隔离库 temp/fist.db（面板可读真实任务）：%s", db_path)
    else:
        db_path = str(ROOT / "temp" / "fist-mbt-web.db")
        log.info("temp/fist.db 不存在，使用隔离库：%s", db_path)
    os.environ["FIST_DB_PATH"] = db_path
    return Path(db_path)


# --- MCP 调用封装：超时/失败绝不 crash，映射为 HTTP 502 ----------------------------
def call_mcp(bridge: MCPBridge, name: str, arguments: dict | None = None):
    """调用 MCP 工具，返回 (ok, data, error)。

    - bridge.send 内部自带 30s deadline；超时返回 {"error": "Request timeout"}。
    - 返回体剥壳规则：result.content[*].text 中若是合法 JSON 则解析为 data。
    """
    try:
        resp = bridge.send("tools/call", {"name": name, "arguments": arguments or {}})
    except Exception as e:
        return False, None, f"mcp: {e}"
    if resp is None:
        return False, None, "mcp: no response"
    if "error" in resp:
        return False, None, f"mcp: {resp.get('error')}"
    result = resp.get("result") or {}
    if result.get("isError"):
        text = ""
        content = result.get("content")
        if isinstance(content, list) and content:
            text = str(content[0].get("text", ""))[:300]
        return False, None, f"mcp: {text or 'tool reported isError'}"
    content = result.get("content")
    if isinstance(content, list) and len(content) == 1 and content[0].get("type") == "text":
        raw = content[0].get("text", "")
        try:
            return True, json.loads(raw), None
        except json.JSONDecodeError:
            return True, {"_raw_text": raw}, None
    return True, result, None


# --- 嵌套树化算法 ----------------------------------------------------------------
def nest_tasks(flat: list) -> list:
    """平铺任务数组 → 嵌套树。

    - 根 = parent_id 为空（None / "" / "None"）的任务
    - 每个任务保留全部原字段，再挂 `children` 数组
    - 兄弟按 id 排序（稳定，字符串比较）
    - 父节点不在本 ns 内的孤立子节点当根挂出，避免丢节点
    """
    by_id: dict[str, dict] = {}
    for t in flat:
        if not isinstance(t, dict):
            continue
        tid = t.get("id")
        if tid is None:
            continue
        t["children"] = []
        by_id[str(tid)] = t

    roots: list[dict] = []
    for t in flat:
        if not isinstance(t, dict):
            continue
        tid = t.get("id")
        if tid is None:
            continue
        pid = t.get("parent_id")
        if pid is None or str(pid) == "" or str(pid) == "None":
            roots.append(t)
        else:
            parent = by_id.get(str(pid))
            if parent is not None:
                parent["children"].append(t)
            else:
                roots.append(t)

    def sort_tree(nodes: list[dict]) -> None:
        for n in nodes:
            if n.get("children"):
                sort_tree(n["children"])
        nodes.sort(key=lambda n: str(n.get("id", "")))

    sort_tree(roots)
    return roots


def aggregate_status(roots: list[dict]) -> dict:
    """按 status 递归聚合计数。"""
    by_status: dict[str, int] = {}

    def walk(nodes: list[dict]) -> None:
        for n in nodes:
            st = n.get("status", "未知")
            by_status[st] = by_status.get(st, 0) + 1
            if n.get("children"):
                walk(n["children"])

    walk(roots)
    return by_status


# --- 静态资源解析（路径穿越 403） -------------------------------------------------
def resolve_static(path: str) -> Path | None:
    """把 /static/<path> 解析到 web/ 目录内的真实文件；越界/不存在返回 None。

    也接受根级裸文件名（如 `/style.css`、`/app.js`），供 index.html 里
    `<link href="style.css">` 这种相对引用直接命中。
    """
    if path.startswith("/static/"):
        rest = path[len("/static/"):].lstrip("/")
    else:
        rest = path.lstrip("/")
        if not rest or "/" in rest:
            return None  # 多段路径交给其它路由
    if not rest:
        return None
    if rest.startswith("/") or "\\" in rest:
        return None
    target = (WEB_DIR / rest).resolve()
    web_dir = WEB_DIR.resolve()
    if web_dir != target and web_dir not in target.parents:
        return None
    if not target.is_file():
        return None
    return target


# --- 占位 HTML（web/index.html 不存在时）------------------------------------------
PLACEHOLDER_HTML = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>fist-mbt Dashboard</title>
<style>
body{font-family:system-ui,sans-serif;max-width:780px;margin:40px auto;padding:0 20px;color:#222}
h1{border-bottom:2px solid #2563eb;padding-bottom:8px}
.pill{display:inline-block;padding:2px 10px;border-radius:12px;background:#dcfce7;color:#166534;font-size:12px;margin-left:8px}
code{background:#f3f4f6;padding:2px 6px;border-radius:4px}
table{border-collapse:collapse;width:100%;margin-top:12px}
th,td{border:1px solid #e5e7eb;padding:6px 10px;text-align:left;font-size:14px}
th{background:#f9fafb}
</style>
</head>
<body>
<h1>fist-mbt Dashboard<span class="pill">后端已就绪，前端待建</span></h1>
<p>M0 任务看板后端已就绪（<code>scripts/fist-mbt-web.py</code>）。前端
<code>web/index.html</code> 尚未创建，此页为占位状态页。</p>
<h2>API 一览</h2>
<table>
<tr><th>端点</th><th>说明</th></tr>
<tr><td><code>GET /health</code></td><td>健康检查</td></tr>
<tr><td><code>GET /api/status</code></td><td>项目脉冲（status_summary）</td></tr>
<tr><td><code>GET /api/tasks?ns=&lt;ns&gt;</code></td><td>任务树（嵌套）</td></tr>
<tr><td><code>GET /api/tasks/&lt;task_id&gt;</code></td><td>单任务详情</td></tr>
<tr><td><code>GET /api/events</code></td><td>SSE 实时流</td></tr>
</table>
<h2>服务状态</h2>
<p id="health">加载中…</p>
<script>
fetch('/health').then(r=>r.json()).then(j=>{
  document.getElementById('health').innerHTML =
    'mcp_alive: <code>'+j.mcp_alive+'</code> · updated_at: <code>'+j.updated_at+'</code>';
}).catch(e=>{document.getElementById('health').textContent='健康检查失败: '+e});
</script>
</body>
</html>
"""

_MIME = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".ico": "image/x-icon",
    ".woff": "font/woff",
    ".woff2": "font/woff2",
    ".map": "application/json; charset=utf-8",
}


def mime_type(p: Path) -> str:
    return _MIME.get(p.suffix.lower(), "application/octet-stream")


def parse_qs(q: str) -> dict[str, str]:
    import urllib.parse
    return {k: v[0] for k, v in urllib.parse.parse_qs(q).items()}


def now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime())


# --- HTTP Handler ---------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    server_version = "fist-mbt-web/0.1"

    def log_message(self, fmt, *args):
        log.info("%s - %s", self.address_string(), fmt % args)

    @property
    def bridge(self) -> MCPBridge:
        return self.server.bridge  # type: ignore[attr-defined]

    # --- 认证 ---
    def _authorized(self) -> bool:
        if not TOKEN:
            return True
        auth = self.headers.get("Authorization", "")
        if auth.startswith("Bearer "):
            return auth[7:].strip() == TOKEN
        qs = parse_qs(self.path.split("?", 1)[1] if "?" in self.path else "")
        return qs.get("token", "") == TOKEN

    # --- 响应 ---
    def _send_json(self, data, status: int = 200) -> None:
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_bytes(self, body: bytes, ctype: str, status: int = 200) -> None:
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_unauthorized(self) -> None:
        self._send_json({"ok": False, "error": "unauthorized"}, status=401)

    def _mcp_alive(self) -> bool:
        b: MCPBridge = self.bridge
        return bool(getattr(b, "_running", False) and b._proc)

    # --- OPTIONS ---
    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.send_header("Access-Control-Max-Age", "86400")
        self.end_headers()

    # --- GET ---
    def do_GET(self) -> None:
        if not self._authorized():
            self._send_unauthorized()
            return

        path = self.path.split("?", 1)[0]

        if path == "/health":
            self._send_json({
                "ok": True,
                "server": "fist-mbt-web",
                "mcp_alive": self._mcp_alive(),
                "updated_at": now_iso(),
            })
            return
        if path == "/":
            self._handle_index()
            return
        if path.startswith("/static/"):
            self._handle_static(path)
            return
        # 根级静态资源（index.html 用相对路径引用的 style.css / app.js）
        if "/" not in path.lstrip("/"):
            t = resolve_static(path)
            if t is not None:
                self._handle_static(path)
                return
        if path == "/api/status":
            self._handle_status()
            return
        if path == "/api/events":
            self._handle_events()
            return
        if path == "/api/tasks":
            self._handle_tasks()
            return
        if path.startswith("/api/tasks/"):
            tid = path[len("/api/tasks/"):]
            if tid:
                self._handle_task_detail(tid)
                return
        self._send_json({"ok": False, "error": "not found"}, status=404)

    def _handle_index(self) -> None:
        idx = WEB_DIR / "index.html"
        if idx.is_file():
            try:
                self._send_bytes(idx.read_bytes(), "text/html; charset=utf-8")
            except Exception as e:
                self._send_json({"ok": False, "error": f"read index.html failed: {e}"}, status=500)
            return
        self._send_bytes(PLACEHOLDER_HTML.encode("utf-8"), "text/html; charset=utf-8")

    def _handle_static(self, path: str) -> None:
        target = resolve_static(path)
        if target is None:
            self._send_json({"ok": False, "error": "forbidden"}, status=403)
            return
        try:
            body = target.read_bytes()
        except Exception as e:
            self._send_json({"ok": False, "error": f"read failed: {e}"}, status=500)
            return
        self._send_bytes(body, mime_type(target))

    def _handle_tasks(self) -> None:
        qs = parse_qs(self.path.split("?", 1)[1] if "?" in self.path else "")
        ns = qs.get("ns") or "default"

        ok, data, err = call_mcp(self.bridge, "list", {"namespace": ns})
        if not ok:
            self._send_json({"ok": False, "error": err}, status=502)
            return
        flat = data if isinstance(data, list) else (
            data.get("tasks") or data.get("data") or [] if isinstance(data, dict) else []
        )
        if not isinstance(flat, list):
            self._send_json({"ok": False, "error": f"mcp: unexpected data shape {type(data).__name__}"}, status=502)
            return

        roots = nest_tasks([dict(t) for t in flat if isinstance(t, dict)])
        self._send_json({
            "ok": True,
            "ns": ns,
            "updated_at": now_iso(),
            "tasks": roots,
            "flat_count": len(flat),
            "by_status": aggregate_status(roots),
        })

    def _handle_task_detail(self, task_id: str) -> None:
        ok, data, err = call_mcp(self.bridge, "get", {"task_id": task_id})
        if not ok:
            self._send_json({"ok": False, "error": err}, status=502)
            return
        self._send_json({"ok": True, "task_id": task_id, "task": data})

    def _handle_status(self) -> None:
        ok, data, err = call_mcp(self.bridge, "status_summary", {})
        if not ok:
            self._send_json({"ok": False, "error": err}, status=502)
            return
        self._send_json({"ok": True, "status": data, "updated_at": now_iso()})

    def _handle_events(self) -> None:
        """GET /api/events：SSE 流。连接即发 snapshot，之后每 15s heartbeat。"""
        q: Queue = Queue()
        with _subscribers_lock:
            _subscribers.append(q)

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()

        # 连接即发一次 snapshot（走同一总线，复用 _publish）
        _publish("snapshot", {"ts": time.time(), "note": "dashboard connected"})

        try:
            while True:
                try:
                    event = q.get(timeout=1.0)
                except Empty:
                    continue
                event_type = event.get("type", "message")
                data = json.dumps(event, ensure_ascii=False)
                self.wfile.write(f"event: {event_type}\ndata: {data}\n\n".encode("utf-8"))
                self.wfile.flush()
        except (ConnectionResetError, BrokenPipeError):
            pass
        except Exception as e:
            log.debug("SSE stream error: %s", e)
        finally:
            with _subscribers_lock:
                if q in _subscribers:
                    _subscribers.remove(q)


# --- 带 server.bridge 的 ThreadingHTTPServer -------------------------------------
class WebServer(ThreadingHTTPServer):
    def __init__(self, addr, handler_cls, bridge: MCPBridge):
        super().__init__(addr, handler_cls)
        self.bridge = bridge


# --- main -----------------------------------------------------------------------
def main() -> None:
    # 1. 确保 MCP 产物新鲜
    ensure_mcp_build()
    # 2. 隔离 DB（环境变量传给子进程）
    configure_db_path()
    # 3. 启动 MCPBridge（复用 fist_mbt_http 的实现）
    bridge = MCPBridge()
    try:
        bridge.start()
    except Exception as e:
        raise SystemExit(f"FATAL MCPBridge.start() 失败：{e}；请检查产物是否可跑 `node {MAIN_CANDIDATES[0]} serve`")
    if not bridge._proc or not bridge._proc.stdin:
        raise SystemExit("FATAL MCPBridge 未能拉起子进程（_proc 为空或 stdin 不可用），诊断 stderr 见上")

    # 4. 心跳线程（复用 fist_mbt_http 的实现，15s 间隔）
    threading.Thread(target=_heartbeat_loop, daemon=True).start()

    # 5. 起 HTTP 服务（只绑 127.0.0.1）
    try:
        server = WebServer(("127.0.0.1", PORT), Handler, bridge)
    except OSError as e:
        bridge.stop()
        raise SystemExit(f"FATAL 无法监听 127.0.0.1:{PORT}：{e}")

    log.info("FIST-Mbt Web 管理面板（M0 只读任务看板）已就绪")
    log.info("  Dashboard: http://127.0.0.1:%d/", PORT)
    log.info("  Health:    http://127.0.0.1:%d/health", PORT)
    log.info("  Tasks:     http://127.0.0.1:%d/api/tasks?ns=fist-mbt-web", PORT)
    log.info("  SSE:       http://127.0.0.1:%d/api/events", PORT)
    if TOKEN:
        log.info("  认证：已启用 FIST_WEB_TOKEN（Bearer 或 ?token=）")
    else:
        log.info("  认证：未启用 FIST_WEB_TOKEN（默认仅本机，局域网勿暴露）")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("Shutting down...")
    finally:
        bridge.stop()
        server.server_close()


if __name__ == "__main__":
    main()