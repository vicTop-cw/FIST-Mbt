#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/map_verify.py — 验证 fist://map 项目地图 resource 端到端可用，且 tool_groups 覆盖全部真源工具。"""

# BUG-138 残余面：Windows 默认 cp936 控制台下，中文结论一红就崩在 print 里，
# traceback + rc=1 会被读成「缺陷在场」那一档——那是尺子自己坏了。先把两条流钉 UTF-8。
import sys as _sys
if hasattr(_sys.stdout, "reconfigure"):
    _sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(_sys.stderr, "reconfigure"):
    _sys.stderr.reconfigure(encoding="utf-8", errors="replace")
import json, os, subprocess
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NODE = os.environ.get("FIST_NODE", "node")
# BUG-122 同型收口：不带 FIST_DB_PATH 裸跑会把演示数据写进仓库根的自举台账 fist-mbt.db。
# 默认改道 temp/ 下的隔离库；调用方显式设过 FIST_DB_PATH 就照它的（store_isolation_probe 那类必须自己控制）。
_FIST_ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
if not (os.environ.get("FIST_DB_PATH") or "").strip():
    os.environ["FIST_DB_PATH"] = os.path.join(_FIST_ROOT, "temp", "map_verify.db")
MAIN = "_build/js/debug/build/cmd/cli/cli.js"
META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "map-verify", "version": "1.0"}}
# 2026-10-26 Lane D：删掉一行死代码 `RE_TOOL = re.compile(r'instrumented_tool\(...')`。
# 依据——全仓 `grep RE_TOOL` 只有它自己那一行定义、零使用；且它与
# `scripts/check_doc_surface.py:143` 的 `RE_TOOL` **逐字相同**（那份才是真在用的，
# 见 `check_doc_surface.py:190` 的 `RE_TOOL_BLOCK_START.finditer`）⇒ 本文件这份是
# 复制残留。留着会让 `pyflakes` 永远报一条假噪音，也会让人误以为本脚本解析工具名。

def rpc(proc, method, **payload):
    params = {"_meta": META}; params.update(payload)
    req = {"jsonrpc": "2.0", "id": "1", "method": method, "params": params}
    proc.stdin.write(json.dumps(req, ensure_ascii=False) + "\n"); proc.stdin.flush()
    line = proc.stdout.readline()
    if not line: raise RuntimeError("server closed stdout")
    return json.loads(line)

def main():
    import importlib.util
    spec = importlib.util.spec_from_file_location("patch_esm_main", os.path.join(ROOT, "scripts", "patch_esm_main.py"))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); mod.patch(MAIN)
    proc = subprocess.Popen([NODE, MAIN, "serve"], cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace", bufsize=1)
    try:
        r = rpc(proc, "resources/list")
        res = r.get("result", {}).get("resources", [])
        names = [x.get("uri") for x in res]
        print("PASS resources/list →", names)
        if "fist://map" not in names:
            raise RuntimeError("fist://map 未注册")
        r = rpc(proc, "resources/read", uri="fist://map")
        content = r.get("result", {}).get("contents", [])
        if not content:
            raise RuntimeError("fist://map 读为空")
        text = content[0].get("text", "")
        payload = json.loads(text)
        assert payload.get("product") == "FIST-Mbt"
        assert "engine" in payload.get("packages", {})
        assert "生命周期" in payload.get("tool_groups", {})
        # R36：地图须含最新分组（Marketplace·能力路由 / 看板·脉冲·预订·推荐+DAG / 自驱含 pick_next）
        assert "Marketplace·能力路由" in payload.get("tool_groups", {}), "地图缺 Marketplace 分组"
        assert "看板/脉冲/预订/推荐+DAG" in payload.get("tool_groups", {}), "地图缺看板/脉冲分组"
        assert "executor_register" in payload.get("tool_groups", {}).get("Marketplace·能力路由", "")
        # R48：地图补齐此前漏掉的工具家族（生命周期 parallel/reopen、强验证 verify/fix、运维杂项、衍生 ATGC）
        tg = payload.get("tool_groups", {})
        assert "publish_parallel" in tg.get("生命周期", "") and "reopen_task" in tg.get("生命周期", ""), "地图生命周期缺 publish_parallel/reopen_task"
        assert "verify_fix" in tg.get("强验证", ""), "地图强验证缺 omega_verify_fix"
        assert "运维·日志/缺陷/成本/调度" in tg, "地图缺运维杂项分组"
        assert "call_log" in tg.get("运维·日志/缺陷/成本/调度", ""), "地图运维杂项缺 call_log"
        assert "衍生·ATGC-old" in tg, "地图缺衍生 ATGC-old 分组"
        assert "atgc_old_compile" in tg.get("衍生·ATGC-old", ""), "地图衍生缺 atgc_old_compile"
        print("PASS resources/read fist://map → product=", payload.get("product"),
              "packages=", list(payload.get("packages", {})), "tool_groups=", list(payload.get("tool_groups", {})))
        print("MCP-MAP-VERIFY PASS")
    finally:
        try:
            proc.stdin.close(); proc.terminate(); proc.wait(timeout=5)
        except Exception:
            pass

if __name__ == "__main__":
    main()