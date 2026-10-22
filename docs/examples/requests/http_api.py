#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""docs/examples/requests/http_api.py — 多语言接入的 requests 示例（计划 multilang §4 / L88 / L149）。

计划原文三处点名它：
  L88  「README 给最小示例：curl / requests / HttpClient / fetch」
  L149 「S1（P2 末期）… curl / **requests** / fetch 示例可用」（验收标准）
⇒ 仓内原先只有 curl / fetch / python（**用标准库 urllib，刻意零依赖**）三支，
  "requests"（第三方库这条线）一直**无对应文件**。本文件补上这一格。

与 docs/examples/python/http_client.py 的分工（两支刻意并存，覆盖两类用户）：
  - python/http_client.py ：**零依赖**（只用标准库 urllib）——证明"任何语言自带 HTTP 即可接"
  - requests/http_api.py   ：**第三方库**这条线（requests 的 Session/params/错误语义）——覆盖
                            习惯 requests 的用户，且演示 `raise_for_status` 的显式错误面

契约真源 docs/openapi/fist.yaml；桥起法：python scripts/fist-mbt-http.py [port]
用法：python docs/examples/requests/http_api.py [port]        # 默认 3137
依赖：pip install requests（无它时本文件**显式报前置不满足**，不假装跑通）
"""
import sys

# BUG-138 同族：本示例有中文 print，Windows 默认 cp936 控制台下若不钉 UTF-8，
# 成功结论会崩在 print 里（rc=1 冒充"跑失败"）。check_py_stdout_encoding 只扫
# scripts/**，docs/examples/ 不在其面 ⇒ 这里自带闸，不依赖外部 PYTHONIOENCODING。
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

try:
    import requests
except ImportError:
    # 前置不满足必须显式（§0.1 承诺纪律：不许以"没跑起来"冒充"跑通了"）
    print("PRECONDITION REFUSED: 未安装 requests（pip install requests）—— 本示例不跑假绿")
    sys.exit(3)

BASE = "http://127.0.0.1:%s" % (sys.argv[1] if len(sys.argv) > 1 else "3137")
S = requests.Session()
S.headers.update({"Content-Type": "application/json"})


def _die(msg):
    """前置/连接类失败必须**显式且可辨**（把"没跑起来"与"示例坏了"分开）——
    否则读者看到一串 ConnectionError traceback，会把环境问题误读成示例缺陷。"""
    print("PRECONDITION REFUSED: " + msg)
    sys.exit(3)


# 0) 先探桥是否在（/health 是契约里最轻的探针）；连不上就明确指路，不抛堆栈。
try:
    h = S.get(BASE + "/health", timeout=10)
    h.raise_for_status()
except requests.RequestException as e:
    _die("连不上桥 %s（%s）—— 请先起 python scripts/fist-mbt-http.py %s"
         % (BASE, type(e).__name__, sys.argv[1] if len(sys.argv) > 1 else "3137"))

# 1) 自描述：清单 + inputSchema 就是参数真源，别硬编码参数表。
#    用 requests 的 raise_for_status 把 HTTP 层错误显式化（这是本支相对 urllib 支的差异点之一）。
r = S.get(BASE + "/tools", timeout=30)
r.raise_for_status()
tools = r.json()["tools"]
print("[1] GET /tools => %d 个工具；示例工具 %r 的参数：" % (len(tools), tools[0]["name"]),
      list((tools[0].get("inputSchema") or {}).get("properties", {})))

# 2) 调用：body 就是该工具的 arguments（无参传 {}）；回执已剥 JSON-RPC 壳。
r2 = S.post(BASE + "/tools/mode_list/call", data="{}", timeout=30)
r2.raise_for_status()
res = r2.json()
data = res.get("data")
# 形状以实跑为准，不硬猜（金条八）：list 取每项 mode，dict 取 modes。
if isinstance(data, list):
    names = [m.get("mode") for m in data if isinstance(m, dict)]
elif isinstance(data, dict):
    names = [m.get("mode") for m in data.get("modes", []) if isinstance(m, dict)]
else:
    names = []
print("[2] POST /tools/mode_list/call => ok=%s  自驱模式 %s" % (res.get("ok"), names or "（见 result）"))

print("REQUESTS-EXAMPLE PASS")
