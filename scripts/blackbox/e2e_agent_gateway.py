#!/usr/bin/env python3
"""e2e_agent_gateway —— fist-gateway 常驻网关黑盒判据（fist-agent-service-platform-plan P1）

验收面（plan §6 P1：断开调用方连接服务不退出；进程被杀自动重启）：
  A1 /health �活体 + 服务身份回显
  A2 POST /mcp 转发 JSON-RPC（initialize → tools/list 两次握手）
  A3 svc_heartbeat：agent_service.session_last_heartbeat 被网关周期刷新
  A4 SIGTERM → draining → stopped（§3.3 唯一退出路径，注册保留）
  A5（posix only）杀 MCP 子进程 → watchdog 自动重启恢复 alive（退避后）

--selftest：不拉网关、不起子进程，只验证种子/读取 + CLI 入口解析（显式/回退/变异）。

用法：
  python scripts/blackbox/e2e_agent_gateway.py --selftest
  python scripts/blackbox/e2e_agent_gateway.py            # 全链实弹（_build/target/dist 自动探测）
  python scripts/blackbox/e2e_agent_gateway.py --cli-js dist/fist-mbt.js
  # Node.js 不在 PATH 默认位置时可指定：FIST_NODE=/path/to/node24 ...
"""

import argparse
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

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent.parent  # scripts/blackbox/ → 仓根
GATEWAY = ROOT / "scripts" / "fist_gateway.py"

# 入口候选：源码构建优先，官方预构建 dist 兜底。
# 黑盒用户只会拿到 dist/fist-mbt.js，不能因为没有 _build 就整条判据 SKIP。
CLI_CANDIDATES = (
    Path("_build") / "js" / "debug" / "build" / "cmd" / "cli" / "cli.js",
    Path("target") / "js" / "release" / "build" / "cmd" / "cli" / "cli.js",
    Path("dist") / "fist-mbt.js",
)


def resolve_cli_js(explicit: str = "", root: Path = ROOT) -> Path | None:
    """显式 --cli-js 优先；否则按 CLI_CANDIDATES 自动探测。

    显式给错路径必须 fail-closed（返回 None），不得静默回退到别的产物——
    否则「指定了 A 却跑了 B」会让判据看起来绿着但测的不是目标。
    """
    if explicit:
        p = Path(explicit)
        candidates = [p if p.is_absolute() else root / p]
    else:
        candidates = [root / rel for rel in CLI_CANDIDATES]
    for p in candidates:
        if p.is_file():
            return p
    return None


def popen_group_kwargs() -> dict:
    """Windows 才需要 CREATE_NEW_PROCESS_GROUP；POSIX 上该属性不存在。"""
    if os.name == "posix":
        return {}
    flag = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    return {"creationflags": flag} if flag else {}

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
    """判据自证：种子/读取 + CLI 入口解析都必须能红。"""
    with tempfile.TemporaryDirectory() as td:
        db = os.path.join(td, "selftest.db")
        seed_db(db, "svc-selftest")
        assert read_status(db, "svc-selftest")[0] == "registered", "种子行应可读"
        assert read_status(db, "svc-absent")[0] == "", "缺席行必须给空串（会红的形状）"
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        dist = root / "dist" / "fist-mbt.js"
        dist.parent.mkdir(parents=True)
        dist.write_text("// dist", encoding="utf-8")
        # 显式路径优先（相对路径按仓根解析）
        assert resolve_cli_js("dist/fist-mbt.js", root) == dist
        # 无 _build 时回退 dist（黑盒用户的真实形状）
        assert resolve_cli_js("", root) == dist
        # _build 存在时优先源码产物
        build = root / CLI_CANDIDATES[0]
        build.parent.mkdir(parents=True)
        build.write_text("// build", encoding="utf-8")
        assert resolve_cli_js("", root) == build
        # 变异对照：两处产物都删掉 → 必须返回 None，不许静默给幻影路径
        build.unlink()
        dist.unlink()
        assert resolve_cli_js("", root) is None
        # 显式给错路径必须 fail-closed，不得回退到 dist
        dist.parent.mkdir(parents=True, exist_ok=True)
        dist.write_text("// dist", encoding="utf-8")
        assert resolve_cli_js("dist/absent.js", root) is None
        if os.name == "posix":
            assert popen_group_kwargs() == {}, "POSIX 不该带 Windows 进程组参数"
    print("selftest OK：种子/读取 + CLI 入口（显式/回退/变异）+ 进程组参数")


def parse_args(argv=None):
    ap = argparse.ArgumentParser(
        description="fist-gateway 常驻网关黑盒判据（A1-A9）")
    ap.add_argument("--selftest", action="store_true",
                    help="只跑判据自证，不起网关")
    ap.add_argument("--cli-js", default="",
                    help="MCP 入口 cli.js；缺省按 _build/target/dist 自动探测")
    return ap.parse_args(argv)


def main(argv=None) -> None:
    args = parse_args(argv)
    if args.selftest:
        selftest()
        return
    cli_js = resolve_cli_js(args.cli_js)
    if cli_js is None:
        print("SKIPPED: 缺 MCP 入口产物（_build/.../cli.js 或 dist/fist-mbt.js；可用 --cli-js 指定）")
        return
    (ROOT / "temp").mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as td:
        db = os.path.join(td, "e2e.db")
        svc = "svc-gw-e2e"
        port = 18699
        audit = os.path.join(td, "gw-audit.log")
        gw_log = str(ROOT / "temp" / "e2e_gateway.out.log")
        gw_log_f = open(gw_log, "w", encoding="utf-8")
        router_cfg = os.path.join(td, "model-router-default.json")
        seed_db(db, svc)
        proc = subprocess.Popen(
            [sys.executable, str(GATEWAY), "--service-id", svc,
             "--port", str(port), "--db", db,
             "--api-key", "e2e-p2-api-key", "--audit-log", audit,
             "--router-config", router_cfg, "--cli-js", str(cli_js)],
            cwd=str(ROOT), stdout=gw_log_f, stderr=gw_log_f,
            **popen_group_kwargs(),
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
            # A8 模型自动路由（默认自动加入）：路由配置的 agent_services 收到本服务条目
            with open(router_cfg, encoding="utf-8") as f:
                rcfg = json.load(f)
            svc_entries = [s for s in rcfg.get("agent_services", [])
                           if s.get("service_id") == svc]
            assert svc_entries, f"A8 FAIL: 路由配置未登记本服务: {rcfg}"
            assert svc_entries[0].get("endpoint", "").endswith("/mcp"), \
                f"A8 FAIL: 路由条目缺端点: {svc_entries[0]}"
            print("A8 PASS 模型自动路由：agent_services 已登记（默认自动加入）")
            # A6 lan 绑定臂（§4）：0.0.0.0 绑定 + key，经 127.0.0.1 调通
            #（本机即 lan 拓扑的最小可用形：绑定面与认证门全链）
            svc2 = svc + "-lan"
            seed_db(db, svc2)
            lan_port = port + 1
            lan = subprocess.Popen(
                [sys.executable, str(GATEWAY), "--service-id", svc2,
                 "--port", str(lan_port), "--db", db, "--host", "0.0.0.0",
                 "--api-key", "e2e-lan-key",
                 "--router-config", os.path.join(td, "model-router-lan.json"),
                 "--cli-js", str(cli_js)],
                cwd=str(ROOT), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, encoding="utf-8", errors="replace",
                **popen_group_kwargs(),
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
        # A9 §3.2 重启恢复：网关进程重启 → 按注册表恢复 running（会话 token 落库语义）
        gw_log_f.close()
        gw_log_f2 = open(gw_log, "a", encoding="utf-8")
        proc2 = subprocess.Popen(
            [sys.executable, str(GATEWAY), "--service-id", svc,
             "--port", str(port), "--db", db,
             "--api-key", "e2e-p2-api-key", "--audit-log", audit,
             "--router-config", router_cfg, "--cli-js", str(cli_js)],
            cwd=str(ROOT), stdout=gw_log_f2, stderr=gw_log_f2,
            **popen_group_kwargs(),
        )
        try:
            h3 = None
            for _ in range(30):
                time.sleep(0.5)
                try:
                    _, h3 = http_get(f"http://127.0.0.1:{port}/health")
                    if h3.get("alive") is True:
                        break
                except Exception:
                    continue
            assert h3 and h3.get("alive") is True, f"A9 FAIL: 重启后未恢复: {h3}"
            st_restart, _ = read_status(db, svc)
            assert st_restart == "running", f"A9 FAIL: 重启后注册表状态={st_restart}"
            print("A9 PASS 重启恢复 running（§3.2 会话持久化）")
        finally:
            if os.name == "posix":
                proc2.send_signal(signal.SIGTERM)
            else:
                proc2.send_signal(signal.CTRL_BREAK_EVENT)
            proc2.wait(timeout=45)
        st2, _ = read_status(db, svc)
        assert st2 == "stopped", f"A9 FAIL: 二次终止后={st2}"
        gw_log_f2.close()
    print("e2e_agent_gateway: ALL PASS")


if __name__ == "__main__":
    main()
