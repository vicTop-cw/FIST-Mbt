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


def http_post(url: str, payload: dict, timeout: float = 30.0) -> tuple[int, dict]:
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
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
        seed_db(db, svc)
        proc = subprocess.Popen(
            [sys.executable, str(GATEWAY), "--service-id", svc,
             "--port", str(port), "--db", db],
            cwd=str(ROOT), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, encoding="utf-8", errors="replace",
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
            # A2 MCP 转发：initialize → tools/list
            _, init = http_post(f"http://127.0.0.1:{port}/mcp", {
                "jsonrpc": "2.0", "id": 1, "method": "initialize",
                "params": {"protocolVersion": "2026-07-28"}})
            assert "error" not in init, f"A2 initialize 失败: {init}"
            _, tools = http_post(f"http://127.0.0.1:{port}/mcp",
                                 {"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
            assert "error" not in tools and "result" in tools, f"A2 tools/list 失败: {tools}"
            print(f"A2 PASS /mcp 转发（tools/list result 键在）")
            # A3 心跳：session_last_heartbeat 被刷新（等一个心跳周期 >0 而非空串）
            hb = read_status(db, svc)[1]
            assert hb, "A3 心跳未落库"
            print("A3 PASS heartbeat:", hb)
            # A5（posix only）杀 MCP 子进程 → watchdog 自动重启
            if os.name == "posix":
                children = subprocess.run(["pgrep", "-P", str(proc.pid)],
                                          capture_output=True, text=True).stdout.split()
                if children:
                    os.kill(int(children[0]), signal.SIGKILL)
                    time.sleep(8)   # 退避 1s + 重启 + /health 复活
                    _, h2 = http_get(f"http://127.0.0.1:{port}/health")
                    assert h2.get("alive") is True, f"A5 watchdog 未恢复: {h2}"
                    print("A5 PASS watchdog 自动重启")
                else:
                    print("A5 SKIP: 未找到子进程（pgrep 空）")
            else:
                print("A5 SKIP: watchdog 重启臂仅 posix（Windows 句柄约束）")
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
    print("e2e_agent_gateway: ALL PASS")


if __name__ == "__main__":
    main()
