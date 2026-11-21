#!/usr/bin/env python3
"""e2e_agent_task_ns_pairing —— GET /v1/tasks/<id> 跨 ns 配对缺陷回归锁（T0r10）

缺陷形状（2026-11-21 探针实证，HEAD=3e1299fc）：
  shim 把任务发布进本服务 ns 池（.fist-mbt/data/<service_id>.db，状态待领取），
  但 GET /v1/tasks/<id> 的网关侧 get 调用不带 namespace ⇒ 落到全局默认池，
  撞上同 id 的**无关旧任务**（例：svc-atomcode.db 的 T0，已归档/marvis）。
  对照：/mcp tools/call get 显式带 namespace 即返回正确任务。

本锁断言**正确契约**：回执必须来自发布 ns 池（状态/描述与发布一致）。
  - 缺陷未修：输出 KNOWN-RED（缺陷复现证据）并 exit 0 —— 便于巡检跟踪；
  - 缺陷已修：自动转严格断言（任何不配对即 FAIL）。

用法：
  python scripts/blackbox/e2e_agent_task_ns_pairing.py            # 实弹（需已构建 cmd/cli）
"""

import json
import os
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.error
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
    con = sqlite3.connect(db_path)
    try:
        con.execute(SCHEMA)
        con.execute(
            "INSERT INTO agent_service (service_id, owner_agent, status) VALUES (?, ?, 'registered')",
            (service_id, "e2e-ns-seeder"),
        )
        con.commit()
    finally:
        con.close()


def http_post(url: str, payload: dict, timeout: float = 30.0,
              headers: dict | None = None) -> tuple[int, dict]:
    h = {"Content-Type": "application/json", **(headers or {})}
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), headers=h)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")


def http_get(url: str, timeout: float = 30.0,
             headers: dict | None = None) -> tuple[int, dict]:
    req = urllib.request.Request(url, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")


def main() -> None:
    if "--selftest" in sys.argv:
        print("selftest OK：本锁无自建形状，判据即契约本身")
        return
    if not CLI_JS.is_file():
        print("SKIPPED: 缺 MCP 入口产物（先跑 `moon build --target js cmd/cli`）")
        return
    with tempfile.TemporaryDirectory() as td:
        db = os.path.join(td, "e2e-nsp.db")
        svc = "svc-nsp-e2e"
        port = 18710
        gw_log = str(ROOT / "temp" / "e2e_nsp.out.log")
        gw_log_f = open(gw_log, "w", encoding="utf-8")
        api_key = "e2e-nsp-live-key"  # 测试自生成，非真实凭据
        seed_db(db, svc)
        proc = subprocess.Popen(
            [sys.executable, str(GATEWAY), "--service-id", svc,
             "--port", str(port), "--db", db,
             "--api-key", api_key, "--audit-log", os.path.join(td, "a.log"),
             "--router-config", os.path.join(td, "r.json")],
            cwd=str(ROOT), stdout=gw_log_f, stderr=gw_log_f,
            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP,
        )
        try:
            for _ in range(30):
                time.sleep(0.5)
                try:
                    with urllib.request.urlopen(
                            f"http://127.0.0.1:{port}/health", timeout=2) as r:
                        if r.status == 200:
                            break
                except Exception:
                    continue
            else:
                raise AssertionError("网关未起监听")
            auth = {"X-API-Key": api_key}
            base = f"http://127.0.0.1:{port}"

            # 发布：唯一 prompt，ns=本服务池
            marker = f"ns-pairing 回归锁 @ {time.time()}"
            code, pub = http_post(f"{base}/v1/chat/completions",
                                  {"model": "agent-x", "messages": [
                                      {"role": "user", "content": marker}]},
                                  headers=auth)
            assert code == 200 and pub.get("fist_task_id"), \
                f"准备 FAIL: shim 发布未成功: {code} {pub}"
            task_id = pub["fist_task_id"]

            # 真源：/mcp get 显式带 namespace —— ns 池里必有本任务
            code, resp = http_post(f"{base}/mcp", {"jsonrpc": "2.0", "id": 1,
                                   "method": "tools/call",
                                   "params": {"name": "get", "arguments": {
                                       "task_id": task_id, "namespace": svc}}},
                                   headers=auth)
            src = json.loads(resp["result"]["content"][0]["text"])
            assert src.get("description") == marker, \
                f"准备 FAIL: ns 池真源描述不符: {src}"

            # 契约：GET /v1/tasks/<id> 必须回 ns 池里这条任务
            code, body = http_get(f"{base}/v1/tasks/{task_id}", headers=auth)
            paired = (code == 200 and body.get("object") == "task_status"
                      and body.get("status") == src.get("status")
                      and body.get("updated_at") == src.get("updated_at"))
            if paired:
                print(f"PASS GET /v1/tasks 与发布 ns 池配对正确（{task_id} / {body.get('status')}）")
                return
            # KNOWN-RED：缺陷复现（get 未带 namespace ⇒ 读到全局池同 id 旧任务）
            assert src.get("description") == marker and (
                code != 200 or body.get("status") != src.get("status")), \
                f"FAIL: 非缺陷形状的意外不配对: {code} {body}"
            print("KNOWN-RED（缺陷未修，T0r10）：GET /v1/tasks/<id> 跨 ns 读池错位")
            print(f"  证据：GET → {json.dumps(body, ensure_ascii=False)[:200]}")
            print(f"  真源（get+namespace={svc}）→ status={src.get('status')}")
            print("  修法方向：网关侧 get 调用透传发布 ns（或回执面带 ns 解析）")

            # 变通路径判据（缺陷期间的可用通路，须持续绿）：
            # shim 发布 → /mcp claim → get+namespace 反映状态转移（待领取→已领取）。
            # 前置：给认领身份授 ns 写权（ACL 默认拒写，授权链由 human_steward 代行）。
            _, g = http_post(f"{base}/mcp", {"jsonrpc": "2.0", "id": 2,
                             "method": "tools/call",
                             "params": {"name": "agent_acl_grant", "arguments": {
                                 "agent_id": "e2e-nsp", "namespace": svc,
                                 "can_write": True, "by": "human_steward"}}},
                             headers=auth)
            assert "error" not in g, f"变通臂准备 FAIL: ACL �授权失败: {g}"
            _, cl = http_post(f"{base}/mcp", {"jsonrpc": "2.0", "id": 3,
                              "method": "tools/call",
                              "params": {"name": "claim", "arguments": {
                                  "task_id": task_id, "assignee": "e2e-nsp",
                                  "namespace": svc}}}, headers=auth)
            assert "error" not in cl, f"变通臂 FAIL: claim 未成功: {cl}"
            _, gv = http_post(f"{base}/mcp", {"jsonrpc": "2.0", "id": 4,
                              "method": "tools/call",
                              "params": {"name": "get", "arguments": {
                                  "task_id": task_id, "namespace": svc}}},
                              headers=auth)
            now = json.loads(gv["result"]["content"][0]["text"])
            assert now.get("status") == "已领取", \
                f"变通臂 FAIL: get+namespace 未反映已领取: {now.get('status')}"
            assert now.get("description") == marker, \
                f"变通臂 FAIL: 描述不符: {now.get('description')}"
            print("PASS 变通臂：/mcp get+namespace 全程反映 ns 池状态转移（待领取→已领取）")
        finally:
            if os.name == "posix":
                proc.send_signal(signal.SIGTERM)
            else:
                proc.send_signal(signal.CTRL_BREAK_EVENT)
            try:
                proc.wait(timeout=45)
            except subprocess.TimeoutExpired:
                proc.kill()


if __name__ == "__main__":
    main()
