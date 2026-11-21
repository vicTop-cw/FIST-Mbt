#!/usr/bin/env python3
"""e2e_agent_shim_live —— /v1/chat/completions shim 实弹判据（T0r9）

对 fist_gateway.py 的 OpenAI 形状执行器（T0r8 落地）做全链实弹：
自建临时 db + 临时网关实例 + 测试自生成密钥（不触碰任何真实服务凭据），
发布链真实穿过网关 → fist serve → 任务库。

判据（B 面）：
  B1 认证门：无 key → 401
  B2 messages 无 user 内容 → 400
  B3 正常 prompt → 200 + OpenAI 形状（id=chatcmpl-*，choices[0].message.content
     携带 task_id 回执）+ fist_task_id 字段
  B4 任务真落库：临时 db tasks 表出现 status='待领取' 且描述= prompt（截 500 字）
  B5 审计：audit log 出现 chat_completions 行

用法：
  python scripts/blackbox/e2e_agent_shim_live.py --selftest
  python scripts/blackbox/e2e_agent_shim_live.py            # 实弹（需已构建 cmd/cli）
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
            (service_id, "e2e-shim-seeder"),
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


def selftest() -> None:
    """判据自证：脚本形状自检（OpenAI 回执解析 + 描述截断规则会红）。"""
    body = {"id": "chatcmpl-x", "choices": [{"index": 0,
            "message": {"role": "assistant", "content": "任务已受理：T9"}}],
            "fist_task_id": "T9"}
    assert body["fist_task_id"] == "T9"
    assert "任务已受理" in body["choices"][0]["message"]["content"]
    assert "任务已受理：T9（" [:6] == "任务已受理：", "形状自检"
    print("selftest OK：shim 判据形状自证成立")


def main() -> None:
    if "--selftest" in sys.argv:
        selftest()
        return
    if not CLI_JS.is_file():
        print("SKIPPED: 缺 MCP 入口产物（先跑 `moon build --target js cmd/cli`）")
        return
    with tempfile.TemporaryDirectory() as td:
        db = os.path.join(td, "e2e-shim.db")
        svc = "svc-shim-e2e"
        port = 18701
        audit = os.path.join(td, "gw-audit.log")
        gw_log = str(ROOT / "temp" / "e2e_shim.out.log")
        gw_log_f = open(gw_log, "w", encoding="utf-8")
        api_key = "e2e-shim-live-key"  # 测试自生成，非真实凭据
        seed_db(db, svc)
        # fist serve 的数据目录不随 cwd 解析（按 cli.js 位置固定到仓根），
        # 隔离靠专用 ns：任务落 .fist-mbt/data/svc-shim-e2e.db（只装本测试的发布）。
        proc = subprocess.Popen(
            [sys.executable, str(GATEWAY), "--service-id", svc,
             "--port", str(port), "--db", db,
             "--api-key", api_key, "--audit-log", audit,
             "--router-config", os.path.join(td, "model-router-shim.json")],
            cwd=str(ROOT), stdout=gw_log_f, stderr=gw_log_f,
            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP,
        )
        try:
            # 等网关起监听
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
            url = f"http://127.0.0.1:{port}/v1/chat/completions"

            # B1 无 key → 401
            code, _ = http_post(url, {"model": "agent-x", "messages": [
                {"role": "user", "content": "hi"}]})
            assert code == 401, f"B1 FAIL: 无 key 应 401，实得 {code}"
            print("B1 PASS 认证门：无 key 401")

            # B2 无 user 内容 → 400
            code, body = http_post(url, {"model": "agent-x", "messages": [
                {"role": "system", "content": "no user here"}]}, headers=auth)
            assert code == 400, f"B2 FAIL: 无 user 应 400，实得 {code}: {body}"
            print("B2 PASS messages 缺 user → 400")

            # B3 正常 prompt → 200 + OpenAI 形状（prompt 唯一化，B4 精确匹配本轮行）
            prompt = f"shim 实弹验证（T0r9）@{int(time.time())}: e2e_agent_shim_live"
            code, body = http_post(url, {"model": "agent-x", "messages": [
                {"role": "system", "content": "sys"},
                {"role": "user", "content": prompt}]}, headers=auth)
            assert code == 200, f"B3 FAIL: 应 200，实得 {code}: {body}"
            assert body.get("object") == "chat.completion", f"B3 FAIL 非OpenAI形状: {body}"
            assert body.get("id", "").startswith("chatcmpl-"), f"B3 FAIL id 形状: {body}"
            task_id = body.get("fist_task_id", "")
            assert task_id, f"B3 FAIL 缺 fist_task_id: {body}"
            assert task_id in body["choices"][0]["message"]["content"], \
                f"B3 FAIL content 未携带 task_id: {body['choices'][0]}"
            print(f"B3 PASS OpenAI 形状回执，task_id={task_id}")

            # B4 任务真落库（发布链穿过 fist serve；库=专用 e2e ns，仓根 data 下）
            task_db = ROOT / ".fist-mbt" / "data" / f"{svc}.db"
            con = sqlite3.connect(str(task_db))
            try:
                row = con.execute(
                    "SELECT status, ns, substr(description,1,200) FROM tasks "
                    "WHERE description=? ORDER BY created_at DESC LIMIT 1",
                    (prompt,)).fetchone()
            finally:
                con.close()
            assert row, f"B4 FAIL: task_id={task_id} 未落库"
            assert row[0] == "待领取", f"B4 FAIL: 状态应待领取，实得 {row[0]}"
            assert row[1] == svc, f"B4 FAIL: ns 应为本服务，实得 {row[1]}"
            assert row[2] == prompt[:500], f"B4 FAIL: 描述不符: {row[2]}"
            print(f"B4 PASS 任务落库（{row[0]} / ns={row[1]}）")

            # B6 id 序列：同 ns 连续两次发布必须拿到不同 id（发布链无串号/复用）
            code, pub2 = http_post(url, {"model": "agent-x", "messages": [
                {"role": "user", "content": prompt + "/b"}]}, headers=auth)
            assert code == 200 and pub2.get("fist_task_id"), \
                f"B6 FAIL: 第二次发布未成功: {code} {pub2}"
            task_id2 = pub2["fist_task_id"]
            assert task_id2 != task_id, \
                f"B6 FAIL: 连续两次发布返回同 id {task_id}（串号/复用）: {pub2}"
            print(f"B6 PASS id 序列：{task_id} ≠ {task_id2}（发布链无串号）")

            # B5 审计行
            time.sleep(0.5)
            audit_text = Path(audit).read_text(encoding="utf-8", errors="replace")
            assert '"chat_completions"' in audit_text, \
                f"B5 FAIL: 审计缺 chat_completions 行: {audit_text}"
            print("B5 PASS 审计落行 chat_completions")
            print("ALL PASS：shim 实弹判据 B1-B5 全绿")
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
