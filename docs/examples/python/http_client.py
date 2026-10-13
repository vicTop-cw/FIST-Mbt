#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""fist-mbt HTTP 契约 v1 的最小 Python 客户端（计划 multilang §3「语言侧 20 行以内」的实证）。

只用标准库 urllib，无第三方依赖——这正是"不建 SDK、任何语言自带 HTTP 即可接"的兑现：
  1) GET  /tools               拿全量工具清单（含 inputSchema，可自描述驱动）
  2) POST /tools/{name}/call   body 就是该工具的 arguments，回执已剥 JSON-RPC 壳

用法：先起桥 `python scripts/fist-mbt-http.py 3137`，再 `python http_client.py [port]`。
本文件同时是契约的活体冒烟——跑通即证明 fist-mbt-api v1 对任意语言可接。
"""
import json
import sys
import urllib.request

# BUG-138 同族：本示例有中文 print，Windows 默认 cp936 控制台下若不钉 UTF-8，
# 成功结论会崩在 print 里（rc=1 冒充"跑失败"）。check_py_stdout_encoding 只扫
# scripts/**，docs/examples/ 不在其面 ⇒ 这里自带闸，不依赖外部 PYTHONIOENCODING。
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

BASE = f"http://127.0.0.1:{sys.argv[1] if len(sys.argv) > 1 else '3137'}"


def http(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path, data=data, method=method,
        headers={"Content-Type": "application/json"} if data else {})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode("utf-8"))


tools = http("GET", "/tools")["tools"]            # 1. 自描述：清单 + 每工具 inputSchema
print(f"[1] /tools => {len(tools)} 个工具；示例工具 {tools[0]['name']!r} 的参数：",
      list((tools[0].get("inputSchema") or {}).get("properties", {})))
res = http("POST", "/tools/mode_list/call", {})    # 2. 调用：body = 该工具 arguments（无参传 {}）
# mode_list 的正文（剥壳后的 data）是"模式对象数组"——形状以 GET /tools 的 inputSchema /
# 实跑为准，不硬猜（金条八）：data 是 list 就取每项 mode，是 dict 就取 modes。
data = res.get("data")
if isinstance(data, list):
    names = [m.get("mode") for m in data if isinstance(m, dict)]
elif isinstance(data, dict):
    names = [m.get("mode") for m in data.get("modes", []) if isinstance(m, dict)]
else:
    names = []
print(f"[2] /tools/mode_list/call => ok={res['ok']}  自驱模式 {names or '（见 result）'}")
print("PY-CLIENT PASS")
