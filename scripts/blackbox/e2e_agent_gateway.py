#!/usr/bin/env python3
"""e2e_agent_gateway —— fist-gateway 常驻网关黑盒判据（fist-agent-service-platform-plan P1）

验收面（plan §6 P1：断开调用方连接服务不退出；进程被杀自动重启）：
  A1 /health �活体 + 服务身份回显
  A2 POST /mcp 转发 JSON-RPC（initialize → tools/list 两次握手）
  A3 svc_heartbeat：agent_service.session_last_heartbeat 被网关周期刷新
  A4 SIGTERM → draining → stopped（§3.3 唯一退出路径，注册保留）
  A5（posix only）杀 MCP 子进程 → watchdog 自动重启恢复 alive（退避后）

--selftest：不拉网关、不起子进程，只验证脚本自身判据会红（sqlite 种子/读取逻辑）。

用法：
  python scripts/blackbox/e2e_agent_gateway.py --selftest
  python scripts/blackbox/e2e_agent_gateway.py            # 全链实弹（需已构建 cmd/cli）
"""

import json
import os
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent  # scripts/blackbox/ → 仓根
GATEWAY = ROOT / "scripts" / "fist_gateway.py"
CLI_JS = ROOT / "_build" / "js" / "debug" / "build" / "cmd" / "cli" / "cli.js"

SCHEMA = (
    "CREATE TABLE IF NOT EXISTS agent_service (service_id TEXT PRIMARY KEY, "
    "owner_agent TEXT NOT NULL DEFAULT '', capabilities TEXT NOT NULL DEFAULT '[]', "
    "transport TEXT NOT NULL DEFAULT 'mcp', exposure TEXT NOT NULL DEFAULT 'local', "
    "status TEXT NOT NULL DEFAULT 'registered', session_listen_addr TEXT NOT NULL DEFAULT '', "
    "session_token TEXT NOT NULL DEFAULT '', session_pid INTEGER NOT NULL DEFAULT 0, "
    "session_last_heartbeat TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT '', "
    "updated_at TEXT NOT NULL DEFAULT '')"
)


def seed_db(db_path: str, service_id: str) -> None:
    """种子注册行（P0 注册语义：registered 静态登记）。"""
    con = sqlite3.connect(db_path)
    try:
        con.execute(SCHEMA)
        con.execute(
            "INSERT INTO agent_service (service_id, owner_agent, status) VALUES (?, ?, 'registered')",
            (service_id, "e2e-seeder"),
        )
        con.commit()
    finally:
        con.close()


def read_status(db_path: str, service_id: str) -> tuple[str, str]:
    con = sqlite3.connect(db_path)
    try:
        row = con.execute(
            "SELECT status, session_last_heartbeat FROM agent_service WHERE service_id=?",
            (service_id,),
        ).fetchone()
        return (row[0], row[1]) if row else ("", "")
    finally:
        con.close()


def http_get(url: str, timeout: float = 5.0) -> tuple[int, dict]:
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.status, json.loads(r.read().decode())


def http_post(url: str, payload: dict, timeout: float = 30.0,
              headers: dict | None = None) -> tuple[int, dict]:
    h = {"Content-Type": "application/json", **(headers or {})}
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode(), headers=h)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, json.loads(r.read().decode())


def selftest() -> None:
    """判据自证：种子/读取逻辑必须会红（假库 vs 真库读数不同）。"""
    with tempfile.TemporaryDirectory() as td:
        db = os.path.join(td, "selftest.db")
        seed_db(db, "svc-selftest")
        assert read_status(db, "svc-selftest")[0] == "registered", "种子行应可读"
        assert read_status(db, "svc-absent")[0] == "", "缺席行必须给空串（会红的形状）"
    print("selftest OK：种子/读取判据自证成立")


def main() -> None:
    if "--selftest" in sys.argv:
        selftest()
        return
    if not CLI_JS.is_file():
        print("SKIPPED: 缺 MCP 入口产物（先跑 `moon build --target js cmd/cli`）")
        return
    with tempfile.TemporaryDirectory() as td:
        db = os.path.join(td, "e2e.db")
        svc = "svc-gw-e2e"
        port = 18699
        audit = os.path.join(td, "gw-audit.log")
        gw_log = str(ROOT / "temp" / "e2e_gateway.out.log")
        gw_log_f = open(gw_log, "w", encoding="utf-8")
        seed_db(db, svc)
        proc = subprocess.Popen(
            [sys.executable, str(GATEWAY), "--service-id", svc,
             "--port", str(port), "--db", db,
             "--api-key", "e2e-p2-api-key", "--audit-log", audit],
            cwd=str(ROOT), stdout=gw_log_f, stderr=gw_log_f,
            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP,
        )
        try:
            # A1 /health �活体（等网关起监听）
            health = None
            for _ in range(30):
                time.sleep(0.5)
                try:
                    code, health = http_get(f"http://127.0.0.1:{port}/health")
                    if code == 200:
                        break
                except Exception:
                    continue
            assert health and health.get("alive") is True, f"A1 /health 不活体: {health}"
            print("A1 PASS /health:", health["service_id"])
            # A2 MCP 转发：initialize → tools/list（网关带 --api-key，请求须带认证头）
            auth_key = "e2e-p2-api-key"
            auth = {"X-API-Key": auth_key}
            _, init = http_post(f"http://127.0.0.1:{port}/mcp", {
                "jsonrpc": "2.0", "id": 1, "method": "initialize",
                "params": {"protocolVersion": "2026-07-28"}}, headers=auth)
            assert "error" not in init, f"A2 initialize 失败: {init}"
            _, tools = http_post(f"http://127.0.0.1:{port}/mcp",
                                 {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
                                 headers=auth)
            assert "error" not in tools and "result" in tools, f"A2 tools/list 失败: {tools}"
            print("A2 PASS /mcp 转发（tools/list result 键在）")
            # A2b §4.1 认证门：无 key → 401；带 key → 200
            try:
                http_post(f"http://127.0.0.1:{port}/mcp",
                          {"jsonrpc": "2.0", "id": 3, "method": "tools/list"})
                raise SystemExit("A2b FAIL: 无 key 请求未拒（认证门空转）")
            except urllib.error.HTTPError as e:
                assert e.code == 401, f"A2b FAIL: 无 key 应 401，实得 {e.code}"
            code, authed = http_post(
                f"http://127.0.0.1:{port}/mcp",
                {"jsonrpc": "2.0", "id": 4, "method": "tools/list"},
                headers={"X-API-Key": auth_key})
            assert code == 200 and "result" in authed, f"A2b FAIL: 带 key 应 200: {authed}"
            print("A2b PASS 认证门：无 key 401 / 带 key 200")
            # A6 lan 绑定臂（§4）：0.0.0.0 绑定 + key，经 127.0.0.1 调通
            #（本机即 lan 拓扑的最小可用形：绑定面与认证门全链）
            svc2 = svc + "-lan"
            seed_db(db, svc2)
            lan_port = port + 1
            lan = subprocess.Popen(
                [sys.executable, str(GATEWAY), "--service-id", svc2,
                 "--port", str(lan_port), "--db", db, "--host", "0.0.0.0",
                 "--api-key", "e2e-lan-key"],
                cwd=str(ROOT), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, encoding="utf-8", errors="replace",
                creationflags=subprocess.CREATE_NEW_PROCESS_GROUP,
            )
            try:
                lan_alive = None
                for _ in range(30):
                    time.sleep(0.5)
                    try:
                        _, lan_alive = http_get(f"http://127.0.0.1:{lan_port}/health")
                        if lan_alive.get("alive") is True:
                            break
                    except Exception:
                        continue
                assert lan_alive and lan_alive.get("alive") is True, f"A6 lan 网关未起: {lan_alive}"
                code, _ = http_post(
                    f"http://127.0.0.1:{lan_port}/mcp",
                    {"jsonrpc": "2.0", "id": 1, "method": "tools/list"},
                    headers={"X-API-Key": "e2e-lan-key"})
                assert code == 200, f"A6 FAIL: lan 绑定带 key 应 200，实得 {code}"
                print("A6 PASS lan 绑定（0.0.0.0）+ 认证全链")
            finally:
                if os.name == "posix":
                    lan.send_signal(signal.SIGTERM)
                else:
                    lan.send_signal(signal.CTRL_BREAK_EVENT)
                lan.wait(timeout=45)
            assert read_status(db, svc2)[0] == "stopped", "A6 FAIL: lan 网关未落 stopped"
            # A3 心跳：session_last_heartbeat 被刷新（等一个心跳周期 >0 而非空串）
            hb = read_status(db, svc)[1]
            assert hb, "A3 心跳未落库"
            print("A3 PASS heartbeat:", hb)
            # A5 watchdog：杀 MCP 子进程 → 自动重启恢复 alive（§3.1 进程层）
            if os.name == "posix":
                children = subprocess.run(["pgrep", "-P", str(proc.pid)],
                                          capture_output=True, text=True).stdout.split()
            else:
                # Windows：Get-CimInstance 按父进程找子进程（wmic 可能空返回，见既有教训）
                children = subprocess.run(
                    ["powershell", "-NoProfile", "-Command",
                     f"(Get-CimInstance Win32_Process -Filter "
                     f"\"ParentProcessId={proc.pid}\").ProcessId"],
                    capture_output=True, text=True).stdout.split()
            if children:
                victim = int(children[0])
                if os.name == "posix":
                    os.kill(victim, signal.SIGKILL)
                else:
                    subprocess.run(["taskkill", "/F", "/PID", str(victim)],
                                   capture_output=True)
                # 退避 1s + 重启 + /health 复活（watchdog 第 0 档）
                time.sleep(8)
                _, h2 = http_get(f"http://127.0.0.1:{port}/health")
                assert h2.get("alive") is True, f"A5 watchdog 未恢复: {h2}"
                print("A5 PASS watchdog 自动重启（杀子进程后恢复 alive）")
            else:
                print("A5 SKIP: 未找到 MCP 子进程（枚举面无读数）")
        finally:
            # A4 显式中断：SIGTERM（posix）/ CTRL_BREAK（Windows，可捕获）→ stopped
            if os.name == "posix":
                proc.send_signal(signal.SIGTERM)
            else:
                proc.send_signal(signal.CTRL_BREAK_EVENT)
            try:
                proc.wait(timeout=45)
            except subprocess.TimeoutExpired:
                proc.kill()
                raise SystemExit("A4 FAIL: 网关 45s 未退出（draining 卡死）")
        status, _ = read_status(db, svc)
        assert status == "stopped", f"A4 FAIL: 终止后状态={status}（应为 stopped）"
        print("A4 PASS 显式中断 → stopped（注册保留）")
        # A7 P4 审计面：mcp_call 与 auth_fail 双事件均落审计账（append-only）
        audit_lines = Path(audit).read_text(encoding="utf-8").strip().splitlines()
        events = [json.loads(l).get("event") for l in audit_lines if l.strip()]
        assert "mcp_call" in events, f"A7 FAIL: 审计无 mcp_call: {events}"
        assert "auth_fail" in events, f"A7 FAIL: 审计无 auth_fail: {events}"
        print(f"A7 PASS 审计账：{len(events)} 行（mcp_call + auth_fail 双事件在）")
    print("e2e_agent_gateway: ALL PASS")


if __name__ == "__main__":
    main()
