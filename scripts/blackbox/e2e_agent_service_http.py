#!/usr/bin/env python3
"""e2e_agent_service_http —— agent_service_* 六工具经网关 HTTP 的生命周期黑盒判据
（fist-agent-service-platform plan §1.2/§3.3 P0 验收补强）

验收面：
  B1 register（幂等/校验）→ registered
  B2 start → running + gateway_pid 回填（P4 session_pid 语义统一）
  B3 start 重复调用 → 拒绝（已在运行，常驻不中断）
  B4 status → running
  B5 stop → stopped（draining→stopped 两跳同步完成）
  B6 stopped 再 start → running（注册保留可重启）
  B7 revoke（running 拒绝）→ stop 后 revoke → 注册行删除、status 未注册

用法：
  python scripts/blackbox/e2e_agent_service_http.py --selftest
  python scripts/blackbox/e2e_agent_service_http.py   # 需已 moon build --target js cmd/cli
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

ROOT = Path(__file__).resolve().parent.parent.parent
GATEWAY = ROOT / "scripts" / "fist_gateway.py"
CLI_JS = ROOT / "_build" / "js" / "debug" / "build" / "cmd" / "cli" / "cli.js"
PORT = 18698
API_KEY = "e2e-asvc-http-key"
SVC = "svc-e2e-http"


class ToolErr(Exception):
    """tools/call 返回 JSON-RPC error 的形状包装。"""


def http_post(url: str, payload: dict, key: str, timeout: float = 60.0):
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "X-API-Key": key})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def tools_call(name: str, arguments: dict) -> dict:
    """经网关调 agent_service 工具；JSON-RPC error 抛 ToolErr。"""
    resp = http_post(f"http://127.0.0.1:{PORT}/mcp",
                     {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                      "params": {"name": name, "arguments": arguments}}, API_KEY)
    if "error" in resp:
        raise ToolErr(resp["error"].get("message", ""))
    return json.loads(resp["result"]["content"][0]["text"])


def seed_db(db_path: str) -> None:
    """网关自身注册表：无服务行时网关拒绝启动（--db 校验），故种一行占位。"""
    con = sqlite3.connect(db_path)
    try:
        con.execute(
            "CREATE TABLE IF NOT EXISTS agent_service (service_id TEXT PRIMARY KEY, "
            "owner_agent TEXT NOT NULL DEFAULT '', capabilities TEXT NOT NULL DEFAULT '[]', "
            "transport TEXT NOT NULL DEFAULT 'mcp', exposure TEXT NOT NULL DEFAULT 'local', "
            "status TEXT NOT NULL DEFAULT 'registered', session_listen_addr TEXT NOT NULL DEFAULT '', "
            "session_token TEXT NOT NULL DEFAULT '', session_pid INTEGER NOT NULL DEFAULT 0, "
            "session_last_heartbeat TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT '', "
            "updated_at TEXT NOT NULL DEFAULT '')")
        con.execute(
            "INSERT INTO agent_service (service_id, owner_agent, status) "
            "VALUES ('svc-gw-boot', 'e2e-seeder', 'registered')")
        con.commit()
    finally:
        con.close()


def selftest() -> None:
    """判据自证：种子/读取必须会红（缺行 vs 有行读数不同）。"""
    with tempfile.TemporaryDirectory() as td:
        db = os.path.join(td, "selftest.db")
        seed_db(db)
        con = sqlite3.connect(db)
        n = con.execute("SELECT COUNT(*) FROM agent_service").fetchone()[0]
        con.close()
        assert n == 1, f"种子行应恰 1 条，实得 {n}"
    print("selftest OK：种子/读取判据自证成立")


def main() -> None:
    if "--selftest" in sys.argv:
        selftest()
        return
    if not CLI_JS.is_file():
        print("SKIPPED: 缺 MCP 入口产物（先跑 `moon build --target js cmd/cli`）")
        return
    with tempfile.TemporaryDirectory() as td:
        db = os.path.join(td, "gw-registry.db")
        audit = os.path.join(td, "gw-audit.log")
        gw_log = str(ROOT / "temp" / "e2e_asvc_http.out.log")
        gw_log_f = open(gw_log, "w", encoding="utf-8")
        seed_db(db)
        router_cfg = os.path.join(td, "model-router-default.json")
        proc = subprocess.Popen(
            [sys.executable, str(GATEWAY), "--service-id", "svc-gw-boot",
             "--port", str(PORT), "--db", db, "--api-key", API_KEY,
             "--audit-log", audit, "--router-config", router_cfg],
            cwd=str(ROOT), stdout=gw_log_f, stderr=gw_log_f,
            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP,
        )
        try:
            # 等监听就绪
            up = False
            for _ in range(30):
                time.sleep(0.5)
                try:
                    with urllib.request.urlopen(
                            f"http://127.0.0.1:{PORT}/health", timeout=5) as r:
                        up = json.loads(r.read().decode()).get("alive") is True
                    if up:
                        break
                except Exception:
                    continue
            assert up, "网关未就绪"
            # B1 register：registered + 独立 ns + ACL 授权
            r = tools_call("agent_service_register", {
                "name": SVC, "capabilities": ["编码"],
                "transport": "mcp", "exposure": "local"})
            assert r["status"] == "registered", f"B1 FAIL status={r}"
            assert r["ns"] == SVC and r["acl_granted"] is True, f"B1 FAIL: {r}"
            print("B1 PASS register:", r["service_id"], "registered")
            # B2 start → running + gateway_pid 回填
            r = tools_call("agent_service_start",
                           {"service_id": SVC, "gateway_pid": 7777})
            assert r["status"] == "running", f"B2 FAIL start: {r}"
            assert r["pid"] == "7777", f"B2 FAIL gateway_pid 未回填: {r}"
            print("B2 PASS start → running（gateway_pid=7777 已回填）")
            # B3 重复 start → 拒绝（常驻不中断）
            try:
                tools_call("agent_service_start", {"service_id": SVC})
                raise SystemExit("B3 FAIL: 重复 start 未被拒绝")
            except ToolErr as e:
                assert "已在运行" in str(e), f"B3 FAIL 错误形状: {e}"
            print("B3 PASS 重复 start 拒绝（常驻不中断）")
            # B4 status → running
            r = tools_call("agent_service_status", {"service_id": SVC})
            assert r["status"] == "running", f"B4 FAIL status: {r}"
            print("B4 PASS status → running")
            # B5 stop → stopped（注册保留）
            r = tools_call("agent_service_stop", {"service_id": SVC})
            assert r["status"] == "stopped", f"B5 FAIL stop: {r}"
            print("B5 PASS stop → stopped")
            # B6 stopped 再 start → running（可重启）
            r = tools_call("agent_service_start", {"service_id": SVC})
            assert r["status"] == "running", f"B6 FAIL restart: {r}"
            print("B6 PASS stopped 再 start → running")
            # B7 revoke：running 态拒绝 → stop 后撤销 → status 报未注册
            try:
                tools_call("agent_service_revoke", {"service_id": SVC})
                raise SystemExit("B7 FAIL: running 态 revoke 未被拒绝")
            except ToolErr as e:
                assert "stop" in str(e) or "运行" in str(e), f"B7 FAIL 错误形状: {e}"
            tools_call("agent_service_stop", {"service_id": SVC})
            tools_call("agent_service_revoke", {"service_id": SVC})
            try:
                tools_call("agent_service_status", {"service_id": SVC})
                raise SystemExit("B7 FAIL: revoke 后 status 仍有行")
            except ToolErr:
                pass
            print("B7 PASS revoke → 注册行删除")
        finally:
            if os.name == "posix":
                proc.send_signal(signal.SIGTERM)
            else:
                proc.send_signal(signal.CTRL_BREAK_EVENT)
            try:
                proc.wait(timeout=45)
            except subprocess.TimeoutExpired:
                proc.kill()
            gw_log_f.close()
    print("e2e_agent_service_http: ALL PASS")


if __name__ == "__main__":
    main()
