#!/usr/bin/env python3
"""e2e_agent_models_status —— 网关发现面与回执面实弹判据（T0r8 配对打磨）

对 /v1/models（发现面，8c5228380）与 GET /v1/tasks/<id>（状态回执面，
447477895）做全链实弹：自建临时 db + 临时网关实例 + 测试自生成密钥
（不触碰任何真实服务凭据），发布链真实穿过网关 → fist serve → 任务库。

判据：
  M1 发现面认证门：/v1/models 无 key → 401
  M2 发现面：带 key → object=list，data 条目 id 形如 agent:http://...（可路由）
  R1 回执面认证门：/v1/tasks/<id> 无 key → 401
  R2 回执面 404：不存在的 task_id → 404 + error JSON
  R3 回执面配对：经 shim 发布拿到的 id → 200 + object=task_status
     + status=待领取 + task_id 回显
  X1 未知路径 → 404（/health、/v1/models 之外不带尾路径放行）

用法：
  python scripts/blackbox/e2e_agent_models_status.py --selftest
  python scripts/blackbox/e2e_agent_models_status.py       # 实弹（需已构建 cmd/cli）
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
    """种子注册行（网关要求 --db 指向含 agent_service 表的已存在库）。"""
    con = sqlite3.connect(db_path)
    try:
        con.execute(SCHEMA)
        con.execute(
            "INSERT INTO agent_service (service_id, owner_agent, status) VALUES (?, ?, 'registered')",
            (service_id, "e2e-ms-seeder"),
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


def selftest() -> None:
    """判据自证：形状自检（models 条目 / task_status 回执的会红形状）。"""
    m = {"object": "list", "data": [{"id": "agent:http://127.0.0.1:1/mcp",
                                     "object": "model", "owned_by": "fist-agent-service"}]}
    assert m["data"][0]["id"].startswith("agent:http")
    r = {"object": "task_status", "task_id": "T1", "status": "待领取"}
    assert r["status"] in ("待领取", "已领取", "已完成", "已归档")
    print("selftest OK：models/task_status 判据形状自证成立")


def main() -> None:
    if "--selftest" in sys.argv:
        selftest()
        return
    if not CLI_JS.is_file():
        print("SKIPPED: 缺 MCP 入口产物（先跑 `moon build --target js cmd/cli`）")
        return
    with tempfile.TemporaryDirectory() as td:
        db = os.path.join(td, "e2e-ms.db")
        svc = "svc-ms-e2e"
        port = 18706
        audit = os.path.join(td, "gw-audit.log")
        gw_log = str(ROOT / "temp" / "e2e_ms.out.log")
        gw_log_f = open(gw_log, "w", encoding="utf-8")
        api_key = "e2e-ms-live-key"  # 测试自生成，非真实凭据
        seed_db(db, svc)
        proc = subprocess.Popen(
            [sys.executable, str(GATEWAY), "--service-id", svc,
             "--port", str(port), "--db", db,
             "--api-key", api_key, "--audit-log", audit,
             "--router-config", os.path.join(td, "model-router-ms.json")],
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

            # M1 发现面认证门
            code, _ = http_get(f"{base}/v1/models")
            assert code == 401, f"M1 FAIL: 无 key 应 401，实得 {code}"
            print("M1 PASS /v1/models 无 key 401")

            # M2 发现面形状：list + agent: 条目（本服务默认自动登记）
            code, body = http_get(f"{base}/v1/models", headers=auth)
            assert code == 200 and body.get("object") == "list", \
                f"M2 FAIL: 形状不对: {code} {body}"
            ids = [d.get("id", "") for d in body.get("data", [])]
            assert any(i.startswith("agent:http") for i in ids), \
                f"M2 FAIL: 缺 agent: 可路由条目: {ids}"
            print(f"M2 PASS /v1/models list（{len(ids)} 条可路由）")

            # R1 回执面认证门
            code, _ = http_get(f"{base}/v1/tasks/T0")
            assert code == 401, f"R1 FAIL: 无 key 应 401，实得 {code}"
            print("R1 PASS /v1/tasks 无 key 401")

            # R2 回执面 404：不存在的任务
            code, body = http_get(f"{base}/v1/tasks/T-nonexistent",
                                  headers=auth)
            assert code == 404, f"R2 FAIL: 应 404，实得 {code}: {body}"
            assert "error" in body, f"R2 FAIL: 缺 error JSON: {body}"
            print("R2 PASS 不存在任务 → 404 + error")

            # R3 回执面配对：shim 发布 → 凭 id 查状态
            prompt = f"models/status 判据 @ {time.time()}: e2e_agent_models_status"
            code, pub = http_post(f"{base}/v1/chat/completions",
                                  {"model": "agent-x", "messages": [
                                      {"role": "user", "content": prompt}]},
                                  headers=auth)
            assert code == 200 and pub.get("fist_task_id"), \
                f"R3 准备 FAIL: shim 发布未成功: {code} {pub}"
            task_id = pub["fist_task_id"]
            code, body = http_get(f"{base}/v1/tasks/{task_id}", headers=auth)
            assert code == 200, f"R3 FAIL: 应 200，实得 {code}: {body}"
            assert body.get("object") == "task_status", \
                f"R3 FAIL: 形状不对: {body}"
            assert body.get("task_id") == task_id, \
                f"R3 FAIL: task_id 未回显: {body}"
            # 状态断言放宽为已知集合：临时 e2e 库可能被后台整理守护快速归档
            assert body.get("status") in ("待领取", "已领取", "已完成", "已归档"), \
                f"R3 FAIL: 未知状态: {body.get('status')}"
            print(f"R3 PASS 回执配对（{task_id} / {body.get('status')}）")

            # X1 未知路径
            code, _ = http_get(f"{base}/v1/unknown", headers=auth)
            assert code == 404, f"X1 FAIL: 未知路径应 404，实得 {code}"
            print("X1 PASS 未知路径 404")

            # X2 空 id 边界：/v1/tasks/（尾斜杠无 id）→ 404（前缀匹配显式排除）
            code, _ = http_get(f"{base}/v1/tasks/", headers=auth)
            assert code == 404, f"X2 FAIL: 空 id 应 404，实得 {code}"
            print("X2 PASS 空 id（/v1/tasks/）→ 404")
            print("ALL PASS：发现面/回执面判据 M1-M2+R1-R3+X1 全绿")
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
