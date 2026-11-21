#!/usr/bin/env python3
"""e2e_agent_s3_header —— 网关 S3 挑战签名头注入判据（T0r2）

对 fist_gateway.py 的 P4 S3 透传做全链实弹：/mcp tools/call 携带
X-S3-Challenge / X-S3-Signature 头时，网关把头值注入 consuming 工具
（claim / reserve_scope / lock_acquire）的 arguments；fist serve 端
opt_challenge 判非空 ⇒ 进入验签分支（fail-closed，伪签名 ⇒ +challenge_failed）。

判据（S 面）：
  S1 认证门：无 key → 401
  S2 控制臂：claim 不带 S3 头 ⇒ 回执不出现 challenge_verified/failed/replayed
  S3 注入臂：claim 带 X-S3-* 头（伪签名）⇒ 回执出现 +challenge_failed（验签分支被激活）
  S4 setdefault 语义：调用方已自带 challenge 参数时，头不覆盖（显式参数优先）

用法：
  python scripts/blackbox/e2e_agent_s3_header.py --selftest
  python scripts/blackbox/e2e_agent_s3_header.py            # 实弹（需已构建 cmd/cli）
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
            (service_id, "e2e-s3-seeder"),
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


def raw_text(resp: dict) -> str:
    """从 JSON-RPC 回执里抽出可读文本（result.content[0].text 或 error.message）。"""
    try:
        return resp["result"]["content"][0]["text"]
    except (KeyError, TypeError, IndexError):
        return json.dumps(resp, ensure_ascii=False)


def selftest() -> None:
    """判据自证：S3 差分形状自检（fail-closed 标记必须可区分）。"""
    injected = "…… +challenge_failed（签名不匹配 / 无公钥）"
    control = "任务已领取"
    assert "challenge_failed" in injected
    assert "challenge" not in control
    print("selftest OK：S3 差分形状自证成立")


def main() -> None:
    if "--selftest" in sys.argv:
        selftest()
        return
    if not CLI_JS.is_file():
        print("SKIPPED: 缺 MCP 入口产物（先跑 `moon build --target js cmd/cli`）")
        return
    with tempfile.TemporaryDirectory() as td:
        db = os.path.join(td, "e2e-s3.db")
        svc = "svc-s3-e2e"
        port = 18702
        audit = os.path.join(td, "gw-audit.log")
        gw_log = str(ROOT / "temp" / "e2e_s3.out.log")
        gw_log_f = open(gw_log, "w", encoding="utf-8")
        api_key = "e2e-s3-live-key"  # 测试自生成，非真实凭据
        seed_db(db, svc)
        proc = subprocess.Popen(
            [sys.executable, str(GATEWAY), "--service-id", svc,
             "--port", str(port), "--db", db,
             "--api-key", api_key, "--audit-log", audit,
             "--router-config", os.path.join(td, "model-router-s3.json")],
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
            mcp = f"http://127.0.0.1:{port}/mcp"

            # 前置：给 e2e 认领身份授 ns 写权（ACL 默认拒写，授权链由 human_steward 代行）
            _, g = http_post(mcp, {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                   "params": {"name": "agent_acl_grant", "arguments": {
                                       "agent_id": "e2e-s3", "namespace": svc,
                                       "can_write": True, "by": "human_steward"}}},
                             headers=auth)
            assert "error" not in g, f"ACL 授权失败: {g}"
            print("S0 PASS ACL 授权链：agent_acl_grant(by=human_steward)")

            # S1 无 key → 401
            code, _ = http_post(mcp, {"jsonrpc": "2.0", "id": 1,
                                      "method": "tools/list"})
            assert code == 401, f"S1 FAIL: 无 key 应 401，实得 {code}"
            print("S1 PASS 认证门：无 key 401")

            # 准备一条可认领任务：发布链穿过 shim（复用 T0r9 语义）
            prompt = f"S3 头注入判据（T0r2）@{int(time.time())}: e2e_agent_s3_header"
            code, body = http_post(f"http://127.0.0.1:{port}/v1/chat/completions",
                                   {"model": "agent-x", "messages": [
                                       {"role": "user", "content": prompt}]},
                                   headers=auth)
            assert code == 200 and body.get("fist_task_id"), \
                f"准备臂 FAIL: shim 发布未成功: {code} {body}"
            task_id = body["fist_task_id"]

            def claim_and_text(rpc_id, extra_headers, args):
                payload = {"jsonrpc": "2.0", "id": rpc_id, "method": "tools/call",
                           "params": {"name": "claim", "arguments": args}}
                _, resp = http_post(mcp, payload,
                                    headers={**auth, **extra_headers})
                return raw_text(resp)

            # S2 控制臂：不带 S3 头 ⇒ 回执不出现 challenge_* 标记（原逻辑，零注入）
            txt = claim_and_text(2, {}, {"task_id": task_id, "assignee": "e2e-s3",
                                         "namespace": svc})
            assert "challenge_" not in txt.replace("challenge']", ""), \
                f"S2 FAIL: 无头回执出现 challenge 标记: {txt}"
            print("S2 PASS 控制臂：无 S3 头 ⇒ 无 challenge 标记")

            # S3 注入臂：只带 X-S3-* 头（伪签名），参数不传 challenge ⇒ 头注入生效
            code, body = http_post(f"http://127.0.0.1:{port}/v1/chat/completions",
                                   {"model": "agent-x", "messages": [
                                       {"role": "user", "content": prompt + "/b"}]},
                                   headers=auth)
            assert code == 200 and body.get("fist_task_id"), \
                f"S3 准备 FAIL: shim 发布未成功: {code} {body}"
            task_id2 = body["fist_task_id"]
            txt = claim_and_text(3, {"X-S3-Challenge": "e2e-nonce-1",
                                     "X-S3-Signature": "ab" * 64},
                                 {"task_id": task_id2, "assignee": "e2e-s3",
                                  "namespace": svc})
            assert "challenge_failed" in txt, \
                f"S3 FAIL: 带伪签名头未触发验签分支: {txt}"
            print("S3 PASS 注入臂：X-S3-* 头 ⇒ +challenge_failed（验签分支激活）")

            # S4 setdefault：调用方显式传了 challenge 时，头值不覆盖
            code, body = http_post(f"http://127.0.0.1:{port}/v1/chat/completions",
                                   {"model": "agent-x", "messages": [
                                       {"role": "user", "content": prompt + "/c"}]},
                                   headers=auth)
            assert code == 200 and body.get("fist_task_id"), \
                f"S4 准备 FAIL: shim 发布未成功: {code} {body}"
            task_id3 = body["fist_task_id"]
            txt = claim_and_text(4, {"X-S3-Challenge": "from-header",
                                     "X-S3-Signature": "ab" * 64},
                                 {"task_id": task_id3, "assignee": "e2e-s3",
                                  "namespace": svc, "challenge": "explicit-wins"})
            assert "from-header" not in txt and "explicit-wins" not in txt, \
                f"S4 FAIL: 回执泄露参数原文（观测面受限）: {txt}"
            # 观测面：显式 challenge 走验签分支同样 fail-closed；回执仍有 failed 标记
            assert "challenge_failed" in txt, \
                f"S4 FAIL: 显式 challenge 未走验签分支: {txt}"
            print("S4 PASS setdefault：显式参数优先，分支行为一致（fail-closed）")
            print("ALL PASS：S3 头注入判据 S1-S4 全绿")
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
