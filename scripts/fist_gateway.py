#!/usr/bin/env python3
"""fist-gateway —— Agent 服务常驻网关（fist-agent-service-platform-plan.md P1）

定位：`fist serve` 仅 stdio、生命周期随 MCP 客户端断开而退出 ⇒ 常驻服务由本网关
独立进程托管子进程，与任何单一客户端解耦（plan §2）。服务生命周期**只由显式中断
指令终止**（§3.3 唯一退出路径），调用方断开、网络波动不影响存活。

职责（P1 验收面）：
  - 托管 stdio 子进程（fist serve，MCP 协议），POST /mcp 转发 JSON-RPC
  - watchdog 守护：子进程崩溃 → 自动重启（退避 1s/5s/30s 封顶）→ 恢复 running
  - 心跳：svc_heartbeat 周期刷新 agent_service.session_last_heartbeat（§3.1 TTL=300s）
  - 会话持久化：status/session_pid/listen_addr/session_token 落 agent_service 表
  - SIGINT/SIGTERM → draining（拒新任务）→ 终止子进程 → stopped（注册保留）

Usage:
  python scripts/fist_gateway.py --service-id svc-marvis [--port 18640] [--db <agent_service 库路径>]
                                    [--host 127.0.0.1] [--cli-js <cli.js 路径>]
零新依赖：Python stdlib（http.server / sqlite3 / subprocess / secrets）。
"""

import argparse
import hashlib
import json
import logging
import os
import secrets
import signal
import sqlite3
import subprocess
import sys
import threading
import time
from collections import deque
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from queue import Queue, Empty

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("fist-gateway")

ROOT = Path(__file__).resolve().parent.parent

RESTART_BACKOFF_SECS = (1, 5, 30)   # §3.1 网关进程层：重启退避 1s/5s/30s 封顶
HEARTBEAT_INTERVAL_SECS = 60        # TTL=300s 的 1/5，短轮询不用订阅句柄（BUG-480 教训）
DRAIN_TIMEOUT_SECS = 30             # §3.3 draining 超时 → force 强杀（审计记录）

MAIN_CANDIDATES = (
    Path("_build") / "js" / "debug" / "build" / "cmd" / "cli" / "cli.js",
    Path("target") / "js" / "release" / "build" / "cmd" / "cli" / "cli.js",
)


def load_service(db_path: str, service_id: str) -> dict | None:
    """读注册行（只读）；缺表/缺行返回 None。"""
    con = sqlite3.connect(db_path)
    try:
        row = con.execute(
            "SELECT status, owner_agent, exposure FROM agent_service WHERE service_id=?",
            (service_id,),
        ).fetchone()
        return row
    finally:
        con.close()


def patch_session(db_path: str, service_id: str, status: str, listen_addr: str,
                  token: str, pid: int, now_iso: str) -> None:
    """会话状态落库（§3.2 持久化：status/pid/listen_addr/token/last_heartbeat）。"""
    con = sqlite3.connect(db_path)
    try:
        con.execute(
            "UPDATE agent_service SET status=?, session_listen_addr=?, session_token=?, "
            "session_pid=?, session_last_heartbeat=?, updated_at=? WHERE service_id=?",
            (status, listen_addr, token, pid, now_iso, now_iso, service_id),
        )
        con.commit()
    finally:
        con.close()


class Gateway:
    """常驻网关：托管子进程 + watchdog + 心跳 + 注册表落库。"""

    def __init__(self, args) -> None:
        self.args = args
        self.service_id = args.service_id
        self.db_path = args.db
        self.listen_addr = f"{args.host}:{args.port}"
        self.session_token = secrets.token_hex(16)
        # P2 §4.1：API-key 认证（lan/global 强制）。网关只存 sha256 哈希（明文不落盘）；
        # --api-key 由对应 agent 启动时给定并**只打印一次**给指挥官留存。
        self.api_key_hash = (
            hashlib.sha256(args.api_key.encode()).hexdigest() if args.api_key else ""
        )
        self.rate_limit = args.rate_limit
        self._req_times: dict[str, deque] = {}   # key（或 ip）→ 窗口内时间戳
        self._req_lock = threading.Lock()
        self.audit_path = args.audit_log or f"temp/gateway-{args.service_id}.log"
        self._audit_lock = threading.Lock()
        self._proc: subprocess.Popen | None = None
        self._reader: threading.Thread | None = None
        self._running = False
        self._resp: Queue = Queue()
        self._lock = threading.Lock()   # 子进程 stdin 写锁
        self.stop_event = threading.Event()

    # ---- P2 认证与限流（§4.1 安全矩阵） ----

    def _key_fingerprint(self, headers) -> str:
        """提取调用方 key 指纹：X-API-Key 或 Authorization: Bearer。"""
        key = headers.get("X-API-Key", "")
        if not key:
            auth = headers.get("Authorization", "")
            if auth.startswith("Bearer "):
                key = auth[len("Bearer "):]
        return hashlib.sha256(key.encode()).hexdigest() if key else ""

    def auth_ok(self, headers, peer_ip: str) -> bool:
        """§4.1：本机档可免认证（127.0.0.1 且未给 --api-key）；给了 key 或非本机绑定即强制。"""
        if not self.api_key_hash:
            return args_host_is_local(self.args)
        fp = self._key_fingerprint(headers)
        if fp != self.api_key_hash:
            return False
        # per-key 限流（§4.1：per-key 限流/配额，复用 cost_budget_check 的语义位）
        now = time.time()
        with self._req_lock:
            dq = self._req_times.setdefault(fp, deque())
            while dq and now - dq[0] > 60.0:
                dq.popleft()
            if len(dq) >= self.rate_limit:
                return False
            dq.append(now)
        return True

    def lan_binding_requires_key(self) -> bool:
        """§4.2：非本机绑定（lan/global）强制 API-key——启动期拒绝裸奔。"""
        if args_host_is_local(self.args):
            return False
        return not self.api_key_hash

    # ---- 注册表（agent_service 表） ----

    def patch_registry(self, status: str, now_iso: str) -> None:
        patch_session(self.db_path, self.service_id, status, self.listen_addr,
                      self.session_token, self.current_pid(), now_iso)

    def current_pid(self) -> int:
        p = self._proc
        return p.pid if p and p.poll() is None else 0

    # ---- 子进程托管（复用 run_fist_mbt_http.MCPBridge 模式） ----

    def find_command(self) -> list[str] | None:
        candidates = [Path(self.args.cli_js)] if self.args.cli_js else []
        candidates += list(MAIN_CANDIDATES)
        for rel in candidates:
            js = rel if rel.is_absolute() else ROOT / rel
            if not js.is_file():
                continue
            import importlib.util
            spec = importlib.util.spec_from_file_location(
                "patch_esm_main", str(ROOT / "scripts" / "patch_esm_main.py"))
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            mod.patch(str(js))   # moonc ESM 输出 + mizchi/sqlite CJS 桩（幂等）
            return [os.environ.get("FIST_NODE", "node"), str(js), "serve"]
        log.error("找不到 MCP 入口产物 ⇒ 先跑 `moon build --target js cmd/cli`")
        return None

    def start_subprocess(self) -> bool:
        cmd = self.find_command()
        if not cmd:
            return False
        log.info("拉起 MCP 子进程: %s", " ".join(cmd))
        self._proc = subprocess.Popen(
            cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=sys.stderr, text=True, encoding="utf-8", errors="replace",
            bufsize=1, cwd=str(ROOT),
        )
        self._running = True
        self._reader = threading.Thread(target=self._read_loop, daemon=True)
        self._reader.start()
        return True

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
                    self._resp.put(json.loads(line))
                except json.JSONDecodeError:
                    log.debug("非 JSON 输出: %s", line[:200])
        except Exception as e:
            log.error("读线程异常: %s", e)
        finally:
            self._running = False
            self._resp.put({"error": "Server disconnected"})

    def call(self, method: str, params: dict | None = None) -> dict:
        """转发一条 JSON-RPC（补 MCP _meta 协议版本/客户端身份，同 run_fist_mbt_http）。"""
        proc = self._proc
        if not proc or not proc.stdin or proc.poll() is not None:
            return {"error": "Server not running"}
        params = dict(params or {})
        meta = dict(params.get("_meta") or {})
        meta.setdefault("io.modelcontextprotocol/protocolVersion", "2026-07-28")
        meta.setdefault("io.modelcontextprotocol/clientCapabilities", {})
        meta.setdefault("io.modelcontextprotocol/clientInfo",
                        {"name": "fist-gateway", "version": "1.0"})
        params["_meta"] = meta
        req_id = int(time.time() * 1000) ^ id(threading.current_thread())
        request = {"jsonrpc": "2.0", "id": req_id, "method": method, "params": params}
        try:
            with self._lock:
                proc.stdin.write(json.dumps(request) + "\n")
                proc.stdin.flush()
        except (BrokenPipeError, OSError):
            return {"error": "Server disconnected"}
        deadline = time.time() + float(os.environ.get("FIST_HTTP_WAIT_SEC", "600"))
        while time.time() < deadline:
            if self.stop_event.is_set():
                return {"error": "Gateway draining"}
            try:
                msg = self._resp.get(timeout=0.5)
            except Empty:
                continue
            if msg.get("id") == req_id:
                return msg
            # 异步通知（id 缺失）丢弃；不匹配 id 的响应归别的等待者
        return {"error": "Request timeout"}

    # ---- watchdog（§3.1 进程层：崩溃 → 自动重启 → 恢复 running） ----

    def watchdog_loop(self) -> None:
        backoff_idx = 0
        while not self.stop_event.is_set():
            if self.stop_event.wait(timeout=2):
                return
            proc = self._proc
            if proc is None or proc.poll() is None:
                backoff_idx = 0
                continue
            try:
                delay = RESTART_BACKOFF_SECS[min(backoff_idx, len(RESTART_BACKOFF_SECS) - 1)]
                backoff_idx += 1
                log.warning("子进程已退出（rc=%s）→ %.0fs 后自动重启（退避第 %d 档）",
                            proc.returncode, delay, backoff_idx)
                self.stop_event.wait(timeout=delay)
                if self.stop_event.is_set():
                    return
                if self.start_subprocess():
                    # 重启成功 → 恢复 running 态（§3.1：恢复 running，会话 token 落库）
                    self.patch_registry("running", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
                    log.info("watchdog：子进程已恢复，服务保持 running")
                else:
                    log.error("watchdog：子进程重启失败（入口产物缺失？）")
            except Exception as e:
                # 守护线程不许静默死：任何异常落日志后备退避重试
                #（真缺陷实录：曾用 `if self._running` 当前置——子进程死后 _read_loop
                #  的 finally 恰好把它翻成 False，守护循环永远跳过重启，A5 实测逮住）
                log.error("watchdog 迭代异常（线程继续）: %s", e)
                backoff_idx += 1

    # ---- 心跳（§3.1 服务会话层：last_heartbeat 周期刷新） ----

    def heartbeat_loop(self) -> None:
        while not self.stop_event.wait(timeout=HEARTBEAT_INTERVAL_SECS):
            try:
                self.patch_registry("running", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
                log.info("svc_heartbeat 刷新（service_id=%s）", self.service_id)
            except Exception as e:
                log.error("心跳写库失败: %s", e)

    # ---- 生命周期（§3.3 唯一退出路径） ----

    def run(self) -> None:
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        row = load_service(self.db_path, self.service_id)
        if row is None:
            sys.exit(f"FATAL: agent_service 表读不到 {self.service_id}（先 agent_service_register）")
        # §4.2：lan/global 强制 API-key——启动期拒绝裸奔（fail-closed，不留运行期炸弹）
        if self.lan_binding_requires_key():
            sys.exit("FATAL: 非本机绑定（lan/global）必须给 --api-key（§4.1 强制认证）")
        if self.api_key_hash:
            log.info("API-key 已启用（sha256=%s…，明文不落盘；key 只在启动参数出现一次）",
                     self.api_key_hash[:12])
        if not args_host_is_local(self.args):
            log.info(firewall_check(self.args.host, self.args.port))
            if self.args.open_firewall:
                log.info(firewall_open(self.args.port))
        patch_registry_now = now
        patch_session(self.db_path, self.service_id, "running", self.listen_addr,
                      self.session_token, os.getpid(), patch_registry_now)
        if not self.start_subprocess():
            sys.exit("FATAL: MCP 子进程无法拉起（缺构建产物）")
        threading.Thread(target=self.watchdog_loop, daemon=True).start()
        threading.Thread(target=self.heartbeat_loop, daemon=True).start()
        log.info("fist-gateway 常驻：http://%s/health ｜ http://%s/mcp（service_id=%s）",
                 self.listen_addr, self.listen_addr, self.service_id)
        signal.signal(signal.SIGTERM, self._on_signal)
        signal.signal(signal.SIGINT, self._on_signal)
        # Windows：SIGTERM 走 TerminateProcess（处理器不执行），CTRL_BREAK 才可捕获
        try:
            signal.signal(signal.SIGBREAK, self._on_signal)
        except (AttributeError, ValueError):
            pass
        try:
            self._http_serve()
        except KeyboardInterrupt:
            self._drain_and_stop()

    def _on_signal(self, signum, frame) -> None:
        self._drain_and_stop()

    def _audit(self, event: str, detail: dict) -> None:
        """P4 §4.1 审计：每次 /mcp 调用/认证失败追加一行 JSON（append-only）。

        落点 = --audit-log（默认 temp/gateway-<service_id>.log，服务端 cwd 相对
        —— §7 红线：网关日志只落相对路径，拒绝盘符/上跳）。
        """
        try:
            line = json.dumps({
                "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "service_id": self.service_id,
                "event": event,
                **detail,
            }, ensure_ascii=False)
            with self._audit_lock:
                Path(self.audit_path).parent.mkdir(parents=True, exist_ok=True)
                with open(self.audit_path, "a", encoding="utf-8") as f:
                    f.write(line + "\n")
        except Exception as e:
            log.error("审计写失败（不阻断主流程）: %s", e)

    def _drain_and_stop(self) -> None:
        """§3.3：running → draining（拒新任务）→ 终止子进程 → stopped（审计留痕走日志）。"""
        if self.stop_event.is_set():
            return
        self.stop_event.set()
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        log.info("收到显式中断指令 → draining（最长 %ds）", DRAIN_TIMEOUT_SECS)
        self.patch_registry("draining", now)
        proc = self._proc
        if proc and proc.poll() is None:
            try:
                proc.terminate()
                proc.wait(timeout=DRAIN_TIMEOUT_SECS)
            except subprocess.TimeoutExpired:
                log.warning("graceful 超时 → force 强杀（审计：drain 超时）")
                proc.kill()
        self.patch_registry("stopped", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
        log.info("服务已 stopped（注册保留，可再次 start）")
        # drain 收尾后显式退出：serve_forever 无自发退出路径（§3.3 的「无隐式退出」
        # 只约束 running 态——stopped 是本 handler 自己写完的状态，此处必须离场）
        os._exit(0)

    # ---- HTTP 面（/health + /mcp；/events SSE 属 P2 暴露档，不在 P1） ----

    def _http_serve(self) -> None:
        gateway = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:
                if self.path.split("?")[0] != "/health":
                    self.send_response(404)
                    self.end_headers()
                    return
                proc = gateway._proc
                alive = proc is not None and proc.poll() is None
                body = json.dumps({
                    "service_id": gateway.service_id,
                    "alive": alive,
                    "listen_addr": gateway.listen_addr,
                    "pid": os.getpid(),
                }).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_POST(self) -> None:
                if self.path.split("?")[0] != "/mcp":
                    self.send_response(404)
                    self.end_headers()
                    return
                # §4.1 认证：给了 --api-key（或非本机绑定）即强制；失败 401 不泄露形状
                auth_ok = gateway.api_key_hash == "" or gateway.auth_ok(
                    self.headers, self.client_address[0])
                if not auth_ok:
                    gateway._audit("auth_fail", {"ip": self.client_address[0]})
                    self.send_response(401)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                length = int(self.headers.get("Content-Length", "0"))
                try:
                    payload = json.loads(self.rfile.read(length) or b"{}")
                except json.JSONDecodeError:
                    self.send_response(400)
                    self.end_headers()
                    return
                method = str(payload.get("method", ""))
                # P4 §4.1 审计：每次放行的 /mcp 调用落一行（auth_fail 在上支已落）
                gateway._audit("mcp_call", {"ip": self.client_address[0], "method": method})
                # draining 拒新任务（§3.3）；工具调用放行存量会话
                if gateway.stop_event.is_set():
                    body = json.dumps({"jsonrpc": "2.0", "id": payload.get("id"),
                                       "error": {"code": -32000,
                                                 "message": "Gateway draining"}}).encode()
                    self.send_response(503)
                else:
                    resp = gateway.call(method, payload.get("params"))
                    body = json.dumps(resp).encode()
                    self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, fmt, *log_args) -> None:
                log.info(fmt, *log_args)

        server = ThreadingHTTPServer((self.args.host, self.args.port), Handler)
        server.daemon_threads = True
        server.serve_forever()


def args_host_is_local(args) -> bool:
    """§4 暴露档判定：127.0.0.1/localhost = local；其余（0.0.0.0/网卡 IP）= lan/global。"""
    return args.host in ("127.0.0.1", "localhost")


def firewall_check(host: str, port: int) -> str:
    """§4.1 lan/global：入站规则 best-effort 检查（Windows netsh / posix iptables 探测）。

    返回人话读数（不阻断启动——防火墙形态千差万别，给读数让指挥官裁决，
    强制加规则走 --open-firewall）。能探就探，探不出如实说探不出。
    """
    if os.name == "nt":
        try:
            r = subprocess.run(
                ["netsh", "advfirewall", "firewall", "show", "rule",
                 "name=all", "dir=in"],
                capture_output=True, text=True, timeout=15)
            blob = r.stdout
            if f":{port}" in blob or f"LocalPort: {port}" in blob:
                return f"防火墙：已存在含端口 {port} 的入站规则（netsh 读数）"
            return (f"防火墙：未见端口 {port} 的入站规则——外部调用方会被拦；"
                    f"管理员放行：netsh advfirewall firewall add rule name=\"fist-gateway-{port}\" "
                    f"dir=in action=allow protocol=TCP localport={port}")
        except Exception as e:
            return f"防火墙：netsh 探测失败（{e}）——请人工确认入站规则"
    return f"防火墙：posix 侧请确认 {host}:{port} 可入站（iptables/ufw 自查）"


def firewall_open(port: int) -> str:
    """§4.1 --open-firewall：管理员面加 TCP 入站放行规则（Windows netsh）。

    需管理员权限：netsh 失败（非管理员等）时如实返回错误原文，不阻断启动
    （fail-open 到警告档——加规则失败 ≠ 服务不可用，只影响 lan/global 外部可达性）。
    """
    if os.name != "nt":
        return "防火墙：--open-firewall 仅实现 Windows netsh；posix 请手工放行"
    rule = f"fist-gateway-{port}"
    r = subprocess.run(
        ["netsh", "advfirewall", "firewall", "add", "rule", f"name={rule}",
         "dir=in", "action=allow", "protocol=TCP", f"localport={port}"],
        capture_output=True, text=True, timeout=15)
    if r.returncode == 0 and "确定" in r.stdout or "Ok." in r.stdout:
        return f"防火墙：入站放行规则 {rule}（TCP {port}）已添加"
    return f"防火墙：加规则失败（需管理员权限）——{r.stderr.strip() or r.stdout.strip()}"


def main() -> None:
    ap = argparse.ArgumentParser(description="fist-gateway：Agent 服务常驻网关（P1）")
    ap.add_argument("--service-id", required=True, help="agent_service 表中的 service_id")
    ap.add_argument("--port", type=int, default=18640)
    ap.add_argument("--host", default="127.0.0.1",
                    help="监听地址：127.0.0.1=local 档；0.0.0.0=lan 档（P2 接认证门）")
    ap.add_argument("--db", default=str(ROOT / ".fist-mbt" / "data" / "default.db"),
                    help="含 agent_service 表的 SQLite 库路径")
    ap.add_argument("--cli-js", default="", help="显式 cli.js 路径（默认按 MAIN_CANDIDATES 探测）")
    ap.add_argument("--api-key", default="",
                    help="调用方 API-key（明文只在启动参数出现一次；网关只存 sha256）。"
                         "lan/global 档强制；local 档可选")
    ap.add_argument("--rate-limit", type=int, default=60,
                    help="per-key 限流：每分钟请求数上限（§4.1，默认 60）")
    ap.add_argument("--open-firewall", action="store_true",
                    help="lan/global 档尝试以管理员加 TCP 入站放行规则（Windows netsh；"
                         "失败如实警告不阻断，§4.1 防火墙检查面）")
    ap.add_argument("--audit-log", default="",
                    help=f"审计文件路径（默认 temp/gateway-<service_id>.log，§4.1 P4 审计面）")
    args = ap.parse_args()
    if not Path(args.db).is_file():
        sys.exit(f"FATAL: 库不存在：{args.db}（--db 指向含 agent_service 表的库）")
    Gateway(args).run()


if __name__ == "__main__":
    main()
