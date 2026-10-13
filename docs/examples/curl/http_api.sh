#!/usr/bin/env bash
# docs/examples/curl/http_api.sh — 多语言接入的 curl 示例（计划 multilang S1「curl/requests/fetch
# 示例可用」的 curl 那格；契约真源 docs/openapi/fist.yaml，桥起法 python scripts/fist-mbt-http.py）。
# 纯标准工具（curl + python3 只做 JSON 摘要，没有它就整行输出原文）。
# 用法：bash docs/examples/curl/http_api.sh [port]     # 默认 3137
set -euo pipefail
BASE="http://127.0.0.1:${1:-3137}"

echo "[1] GET /health"
curl -fsS --max-time 15 "$BASE/health"; echo

echo "[2] GET /tools（已剥 JSON-RPC 壳；只报数量与前 5 名，不刷屏）"
if command -v python3 >/dev/null 2>&1; then
  curl -fsS --max-time 30 "$BASE/tools" | python3 -c '
import json, sys
t = json.load(sys.stdin)["tools"]
print("  %d 个工具；前 5 个: %s" % (len(t), ", ".join(x["name"] for x in t[:5])))
'
else
  curl -fsS --max-time 30 "$BASE/tools"
fi

echo "[3] POST /tools/mode_list/call（body 就是该工具的 arguments；无参传 {}）"
if command -v python3 >/dev/null 2>&1; then
  curl -fsS --max-time 30 -X POST -H 'Content-Type: application/json' \
    -d '{}' "$BASE/tools/mode_list/call" | python3 -c '
import json, sys
r = json.load(sys.stdin)
modes = [m.get("mode") for m in (r.get("data") or []) if isinstance(m, dict)]
print("  ok=%s  模式: %s" % (r["ok"], ", ".join(modes) if modes else "（见 result）"))
'
else
  curl -fsS --max-time 30 -X POST -H 'Content-Type: application/json' \
    -d '{}' "$BASE/tools/mode_list/call"
fi

echo "CURL-EXAMPLE PASS"
