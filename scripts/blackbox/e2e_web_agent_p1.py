#!/usr/bin/env python3
"""e2e_web_agent_p1 —— fist-web-agent P1 核心服务黑盒判据

P1（3119e9219）落了 Go 单二进制：/health + OpenAI 兼容 /v1/chat/completions +
/mcp JSON-RPC 网关 + X-API-Key/Bearer 双通道鉴权。本判据对实弹二进制验证：

  G1 /health 免认证：alive=true + uptime_s 存在
  G2 chat 认证门：无 key → 401；伪 key → 401
  G3 chat 形状：带 key → 200 + OpenAI 形状 + echo 回显前缀
  G4 Bearer 通道：Authorization: Bearer <key> → 200（双通道第二路）
  G5 /mcp 网关：initialize → protocolVersion/serverInfo；tools/list → health+echo

用法：
  python scripts/blackbox/e2e_web_agent_p1.py            # 实弹（需已构建二进制）
"""

import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent  # scripts/blackbox/ → 仓根
BIN = ROOT / "services" / "fist-web-agent" / "fist-web-agent.exe"
PORT = 18711
BASE = f"http://127.0.0.1:{PORT}"


def post(url: str, payload: dict, timeout: float = 10.0,
         headers: dict | None = None) -> tuple[int, dict]:
    h = {"Content-Type": "application/json", **(headers or {})}
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), headers=h)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")


def get(url: str, timeout: float = 10.0) -> tuple[int, dict]:
    try:
        with urllib.request.urlopen(req(url), timeout=timeout) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")


def req(url: str) -> urllib.request.Request:
    return urllib.request.Request(url)


def main() -> None:
    if not BIN.is_file():
        print(f"SKIPPED: 缺二进制 {BIN}（先跑 P1 构建面）")
        return
    api_key = "p1-e2e-key-0000000000000000000000"  # 测试自生成，非真实凭据
    proc = subprocess.Popen(
        [str(BIN), "--bind", f"127.0.0.1:{PORT}", "--api-key", api_key],
        cwd=str(BIN.parent), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        for _ in range(30):
            time.sleep(0.5)
            try:
                code, h = get(f"{BASE}/health")
                if code == 200 and h.get("alive") is True:
                    break
            except Exception:
                continue
        else:
            raise AssertionError("服务未起监听")

        # G1 /health 免认证
        assert code == 200 and "uptime_s" in h, f"G1 FAIL: {h}"
        print(f"G1 PASS /health 免认证（uptime_s={h['uptime_s']}）")

        # G2 chat 认证门：无 key / 伪 key 均 401
        code, _ = post(f"{BASE}/v1/chat/completions",
                       {"model": "m", "messages": [{"role": "user", "content": "x"}]})
        assert code == 401, f"G2 FAIL: 无 key 应 401，实得 {code}"
        code, _ = post(f"{BASE}/v1/chat/completions",
                       {"model": "m", "messages": [{"role": "user", "content": "x"}]},
                       headers={"X-API-Key": "wrong-key"})
        assert code == 401, f"G2 FAIL: 伪 key 应 401，实得 {code}"
        print("G2 PASS chat 认证门：无 key/伪 key 均 401")

        # G3 chat 形状 + echo 回显
        code, body = post(f"{BASE}/v1/chat/completions",
                          {"model": "agent-x", "messages": [
                              {"role": "user", "content": "e2e-ping"}]},
                          headers={"X-API-Key": api_key})
        assert code == 200, f"G3 FAIL: 应 200，实得 {code}: {body}"
        assert body.get("object") == "chat.completion", f"G3 FAIL 非OpenAI形状: {body}"
        assert body.get("id", "").startswith("chatcmpl-"), f"G3 FAIL id 形状: {body}"
        msg = body["choices"][0]["message"]["content"]
        assert msg == "fist-web-agent echo: e2e-ping", f"G3 FAIL 回显不符: {msg}"
        print("G3 PASS chat 形状 + echo 回显")

        # G4 Bearer 通道（双通道第二路）
        code, body = post(f"{BASE}/v1/chat/completions",
                          {"model": "agent-x", "messages": [
                              {"role": "user", "content": "bearer"}]},
                          headers={"Authorization": f"Bearer {api_key}"})
        assert code == 200, f"G4 FAIL: Bearer 通道应 200，实得 {code}: {body}"
        print("G4 PASS Bearer 通道 200")

        # G5 /mcp 网关：initialize / tools/list / tools/call echo
        code, body = post(f"{BASE}/mcp", {"jsonrpc": "2.0", "id": 1,
                                          "method": "initialize"},
                          headers={"X-API-Key": api_key})
        assert code == 200, f"G5 FAIL: initialize 应 200: {body}"
        assert body["result"]["protocolVersion"] == "2026-07-28", f"G5 FAIL 形状: {body}"
        code, body = post(f"{BASE}/mcp", {"jsonrpc": "2.0", "id": 2,
                                          "method": "tools/list"},
                          headers={"X-API-Key": api_key})
        names = [t["name"] for t in body["result"]["tools"]]
        assert "health" in names and "echo" in names, f"G5 FAIL: tools 缺: {names}"
        code, body = post(f"{BASE}/mcp", {"jsonrpc": "2.0", "id": 3,
                                          "method": "tools/call",
                                          "params": {"name": "echo",
                                                     "arguments": {"text": "g5"}}},
                          headers={"X-API-Key": api_key})
        assert code == 200, f"G5 FAIL: tools/call 应 200: {body}"
        print("G5 PASS /mcp 网关（initialize/tools/list/tools/call）")
        print("ALL PASS：fist-web-agent P1 判据 G1-G5 全绿")
    finally:
        proc.kill()


if __name__ == "__main__":
    main()
