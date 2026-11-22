#!/usr/bin/env python3
"""web-bridge —— 网页版 AI 常驻桥接网关（svc-webai）

定位：把网页版 AI（DeepSeek 网页版 / 腾讯元宝）接入 fist-mbt 常驻 Agent 服务，
重点服务「网页资源搜索」。复用 fist_gateway.py 模式：
  /health + /mcp + X-API-Key(sha256) + 限流 + 审计 + 自动路由挂载。

分期落地：
  P0 骨架（会话状态/工具契约/JSON-RPC）
  P1 网关暴露（--serve：/health + /mcp + API-key + 审计 + 心跳）
  P2 真实驱动（CDP 连接用户已登录的 Chrome，驱动 DeepSeek/元宝页面）
  P3 自动路由（启动时把 svc-webai 登记进 model-router-default.json 的 agent_services）

用法：
  python scripts/web_bridge.py --serve --port 18645 [--provider deepseek|yuanbao] [--cdp-port 9222]
  python scripts/web_bridge.py --selftest
"""

import argparse
import asyncio
import hashlib
import json
import logging
import os
import secrets
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from collections import deque
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from typing import Any, Callable
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("web-bridge")

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / ".fist-mbt" / "data"
SESSION_FILE = DATA_DIR / "webai-session.json"
APIKEY_FILE = DATA_DIR / "svc-webai.apikey"
ROUTER_CONFIG = DATA_DIR / "model-router-default.json"
DEFAULT_AUDIT_LOG = ROOT / "temp" / "gateway-svc-webai.log"

DEFAULT_PROVIDER = "deepseek"
LOGIN_URLS = {
    "deepseek": "https://chat.deepseek.com/",
    "yuanbao": "https://yuanbao.tencent.com/",
}
DEFAULT_CDP_PORT = 9222
RATE_LIMIT_PER_MIN = 60
HEARTBEAT_INTERVAL_SECS = 60
REPLY_WAIT_SECS = 120        # 等网页版回复上限
REPLY_IDLE_SECS = 6          # 回复稳定判据：内容连续 N 秒不变
INPUT_WAIT_SECS = 20         # 等输入框出现上限

# 本机浏览器候选（用于拉起调试实例；连接已有 CDP 优先）
CHROME_CANDIDATES = [
    os.path.expandvars(r"%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"),
    os.path.expandvars(r"%ProgramFiles%\Google\Chrome\Application\chrome.exe"),
    os.path.expandvars(r"%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"),
    os.path.expandvars(r"%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"),
    os.path.expandvars(r"%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"),
]
WEBAI_PROFILE_DIR = DATA_DIR / "webai-chrome-profile"


# ---------------------------------------------------------------------------
# 会话状态（P0 骨架）
# ---------------------------------------------------------------------------

FIELD_LOGGED_IN = "logged_in"
FIELD_HEARTBEAT = "last_heartbeat"
FIELD_PROVIDER = "provider"
FIELD_UPDATED_AT = "updated_at"


def _now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime())


def load_session(path: Path = SESSION_FILE) -> dict[str, Any]:
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def save_session(state: dict[str, Any], path: Path = SESSION_FILE) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    state[FIELD_UPDATED_AT] = _now_iso()
    with open(path, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)


def heartbeat(state: dict[str, Any], path: Path = SESSION_FILE) -> None:
    state[FIELD_HEARTBEAT] = _now_iso()
    save_session(state, path)


def first_run_guide(provider: str = DEFAULT_PROVIDER) -> None:
    import webbrowser

    url = LOGIN_URLS.get(provider, LOGIN_URLS[DEFAULT_PROVIDER])
    print("=" * 60)
    print("网页版 AI 桥接器 · 首次启动")
    print("=" * 60)
    print("即将打开浏览器登录页：%s" % url)
    print()
    print("【请在弹出的浏览器窗口中登录网页版 AI（DeepSeek 网页版或腾讯元宝），登录完成后按回车】")
    print()
    try:
        webbrowser.open(url)
    except Exception as exc:  # 浏览器打不开不阻断，用户可手动复制 URL
        print("[提示] 自动打开浏览器失败（%s），请手动访问上述 URL。" % exc)
    try:
        input()
    except EOFError:
        print("[提示] 非交互环境：跳过回车等待（--selftest 或被网关拉起时属正常）。")
    print("[OK] 登录等待结束，标记登录态。")


def mark_logged_in(
    state: dict[str, Any], provider: str = DEFAULT_PROVIDER, path: Path = SESSION_FILE
) -> dict[str, Any]:
    state[FIELD_LOGGED_IN] = True
    state[FIELD_PROVIDER] = provider
    heartbeat(state, path)
    return state


# ---------------------------------------------------------------------------
# P2 真实驱动：CDP 连接用户已登录的 Chrome（websockets 实现，零 playwright）
# ---------------------------------------------------------------------------

def find_chrome() -> str:
    for p in CHROME_CANDIDATES:
        if p and os.path.isfile(p):
            return p
    return ""


def launch_debug_chrome(cdp_port: int = DEFAULT_CDP_PORT) -> str | None:
    """拉起独立 profile 的调试 Chrome（用户在该窗口手动登录，cookie 留档复用）。

    返回启动结果人话；已在跑 CDP 则直接返回已连接。"""
    if cdp_reachable(cdp_port):
        return "CDP 已在 %s 端口就绪" % cdp_port
    exe = find_chrome()
    if not exe:
        return "未找到 Chrome/Edge，请手动用 --remote-debugging-port=%s 启动浏览器" % cdp_port
    WEBAI_PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.Popen(
            [exe, "--remote-debugging-port=%d" % cdp_port,
             "--user-data-dir=%s" % str(WEBAI_PROFILE_DIR),
             "--no-first-run", "--no-default-browser-check"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    except OSError as exc:
        return "拉起 Chrome 失败：%s" % exc
    # 等 CDP 就绪（最多 15s）
    for _ in range(30):
        time.sleep(0.5)
        if cdp_reachable(cdp_port):
            return "已拉起调试 Chrome（port=%s，profile=%s）" % (cdp_port, WEBAI_PROFILE_DIR)
    return "Chrome 已拉起但 CDP 未就绪（port=%s）——请确认端口未被占用" % cdp_port


def cdp_reachable(cdp_port: int) -> bool:
    try:
        urllib.request.urlopen("http://127.0.0.1:%d/json/version" % cdp_port, timeout=1.5)
        return True
    except Exception:
        return False


def _page_ws_url(cdp_port: int, provider: str) -> str:
    """取目标登录页的 page websocket；无则新建标签页。"""
    target = LOGIN_URLS[provider]
    host = "127.0.0.1:%d" % cdp_port
    pages = json.load(urllib.request.urlopen("http://%s/json/list" % host, timeout=3))
    domain = urllib.parse.urlparse(target).netloc
    page = next(
        (p for p in pages
         if p.get("type") == "page" and domain in (p.get("url") or "")
         and "newtab" not in (p.get("url") or "")),
        None,
    )
    if page is None:
        req = urllib.request.Request(
            "http://%s/json/new?url=%s" % (host, urllib.parse.quote(target)),
            method="PUT",
        )
        page = json.load(urllib.request.urlopen(req, timeout=5))
    ws = page.get("webSocketDebuggerUrl")
    if not ws:
        raise RuntimeError("CDP 页面无 websocket（%s）" % (page.get("url") or "?"))
    return ws


# 注入页面的 JS（新版驱动：CDP 原生输入 + 真实按键，替代合成事件）
_FOCUS_JS_TEMPLATE = r"""
(async (inputWaitSec) => {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  let box = null;
  const deadline = Date.now() + inputWaitSec * 1000;
  while (Date.now() < deadline) {
    box = document.querySelector('textarea')
      || document.querySelector('[contenteditable="true"]')
      || document.querySelector('[contenteditable="plaintext-only"]');
    if (box) break;
    await sleep(300);
  }
  if (!box) return { ok: false, err: 'no_input_box' };
  box.focus();
  box.click();
  return { ok: true };
})"""

_PICK_JS_TEMPLATE = r"""
(() => {
  const nodes = Array.from(document.querySelectorAll(
    '.ds-markdown, [class*="markdown"], [data-testid*="assistant"], [data-message-author-role="assistant"]'));
  for (let i = nodes.length - 1; i >= 0; i--) {
    const t = (nodes[i].innerText || '').trim();
    if (t) return t;
  }
  const all = Array.from(document.querySelectorAll('[class*="message"], [class*="chat-item"]'))
    .map(n => n.innerText.trim()).filter(Boolean);
  return all.length ? all[all.length - 1] : '';
})()"""

# 注入页面的 JS：等输入框 → 填入问题 → 发送 → 轮询助手回复（best-effort 通用策略，旧版合成事件，保留备用）
_ASK_JS_TEMPLATE = r"""
(async (question, inputWaitSec, replyWaitSec, idleSec) => {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  // 1) 等输入框（textarea 或 contenteditable）
  let box = null;
  const deadline = Date.now() + inputWaitSec * 1000;
  while (Date.now() < deadline) {
    box = document.querySelector('textarea')
      || document.querySelector('[contenteditable="true"]')
      || document.querySelector('[contenteditable="plaintext-only"]');
    if (box) break;
    await sleep(300);
  }
  if (!box) return { ok: false, err: 'no_input_box' };
  // 2) 填入问题
  if (box.tagName === 'TEXTAREA' || box.tagName === 'INPUT') {
    const proto = box.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
    setter.call(box, question);
    box.dispatchEvent(new Event('input', { bubbles: true }));
    box.dispatchEvent(new Event('change', { bubbles: true }));
  } else {
    box.innerText = question;
    box.dispatchEvent(new InputEvent('input', { bubbles: true, data: question }));
  }
  await sleep(300);
  // 3) 发送：优先点发送按钮，兜底派发 Enter
  let sent = false;
  const btns = Array.from(document.querySelectorAll('button'));
  const sendBtn = btns.find(b => {
    const t = (b.getAttribute('aria-label') || b.textContent || '').toLowerCase();
    return t.includes('发送') || t.includes('send');
  });
  if (sendBtn) {
    sendBtn.click();
    sent = true;
  }
  if (!sent) {
    const keyOpts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true };
    box.dispatchEvent(new KeyboardEvent('keydown', keyOpts));
    box.dispatchEvent(new KeyboardEvent('keyup', keyOpts));
    sent = true;
  }
  await sleep(500);
  // 4) 轮询最后一条助手回复：抓 markdown 块；兜底抓可见正文尾部
  const pick = () => {
    const nodes = Array.from(document.querySelectorAll(
      '.ds-markdown, [class*="markdown"], [data-testid*="assistant"], [data-message-author-role="assistant"]'));
    if (nodes.length) {
      const t = nodes[nodes.length - 1].innerText.trim();
      if (t) return t;
    }
    // 兜底：对话区常见的最后一条非用户消息
    const all = Array.from(document.querySelectorAll('[class*="message"], [class*="chat-item"]'))
      .map(n => n.innerText.trim()).filter(Boolean);
    return all.length ? all[all.length - 1] : '';
  };
  const startText = pick();
  let stable = '';
  let stableSince = 0;
  const waitUntil = Date.now() + replyWaitSec * 1000 + idleSec * 1000;
  while (Date.now() < waitUntil) {
    const now = pick();
    if (now && now !== startText) {
      if (now === stable) {
        if (Date.now() - stableSince >= idleSec * 1000) {
          return { ok: true, answer: now };
        }
      } else {
        stable = now;
        stableSince = Date.now();
      }
    }
    await sleep(500);
  }
  return { ok: stable !== '', answer: stable, err: stable ? 'unstable' : 'no_reply' };
})"""


async def _cdp_ask(question: str, provider: str, cdp_port: int) -> dict[str, Any]:
    import websockets

    ws_url = _page_ws_url(cdp_port, provider)
    async with websockets.connect(ws_url, max_size=None) as ws:
        _msg = [0]

        async def cmd(method: str, params: dict) -> dict:
            _msg[0] += 1
            mid = _msg[0]
            await ws.send(json.dumps({"id": mid, "method": method, "params": params}))
            while True:
                raw = await ws.recv()
                msg = json.loads(raw)
                if msg.get("id") == mid:
                    return msg

        # 1) 等输入框并聚焦（原生输入前置条件）
        expr = "(%s)(%d)" % (_FOCUS_JS_TEMPLATE, INPUT_WAIT_SECS)
        r = await cmd("Runtime.evaluate",
                      {"expression": expr, "awaitPromise": True, "returnByValue": True})
        val = r.get("result", {}).get("result", {}).get("value")
        if not isinstance(val, dict) or not val.get("ok"):
            return {"ok": False, "err": (val or {}).get("err", "focus_failed"),
                    "detail": str((val or {}))[:500]}

        # 2) 原生输入问题文本（isTrusted=true，React/框架可感知）
        await cmd("Input.insertText", {"text": question})
        await asyncio.sleep(0.4)

        # 3) 真实 Enter 发送
        for ev_type in ("rawKeyDown", "keyUp"):
            await cmd("Input.dispatchKeyEvent", {
                "type": ev_type, "key": "Enter", "code": "Enter",
                "windowsVirtualKeyCode": 13, "nativeVirtualKeyCode": 13,
            })

        # 4) 记录发送前最后一条助手文本，轮询新回复（连续 idleSec 相同视为稳定）
        r = await cmd("Runtime.evaluate", {"expression": _PICK_JS_TEMPLATE, "returnByValue": True})
        start = r.get("result", {}).get("result", {}).get("value") or ""

        last = ""
        stable_since = 0.0
        deadline = time.time() + REPLY_WAIT_SECS + REPLY_IDLE_SECS
        while time.time() < deadline:
            r = await cmd("Runtime.evaluate", {"expression": _PICK_JS_TEMPLATE, "returnByValue": True})
            if "exceptionDetails" in r.get("result", {}):
                return {"ok": False, "err": "cdp_eval_error",
                        "detail": str(r["result"]["exceptionDetails"])[:500]}
            t = r.get("result", {}).get("result", {}).get("value") or ""
            if t and t != start:
                if t == last:
                    if time.time() - stable_since >= REPLY_IDLE_SECS:
                        return {"ok": True, "answer": t}
                else:
                    last = t
                    stable_since = time.time()
            await asyncio.sleep(0.5)
        if last:
            return {"ok": False, "err": "unstable", "answer": last}
        return {"ok": False, "err": "no_reply", "answer": ""}


def cdp_send_question(question: str, provider: str = DEFAULT_PROVIDER,
                      cdp_port: int = DEFAULT_CDP_PORT) -> str:
    """经 CDP 驱动已登录网页会话，返回回复文本（失败返回可读错误）。"""
    if not cdp_reachable(cdp_port):
        return ("[web_bridge] 未检测到调试浏览器（port=%s）。请先启动并登录网页版 AI：\n"
                "  1) 自动拉起：本服务启动时已尝试拉起 Chrome 调试实例；\n"
                "  2) 手动：chrome.exe --remote-debugging-port=%s --user-data-dir=<你的登录 profile>，"
                "然后打开 %s 完成登录。" % (cdp_port, cdp_port,
                                          LOGIN_URLS.get(provider, LOGIN_URLS[DEFAULT_PROVIDER])))
    try:
        result = asyncio.run(_cdp_ask(question, provider, cdp_port))
    except Exception as exc:  # noqa: BLE001 —— 驱动层任何异常都转可读错误
        return "[web_bridge] CDP 驱动异常：%s（浏览器可能被关闭或端口占用）" % exc
    if result.get("ok"):
        return result.get("answer") or "[web_bridge] 回复为空"
    err = result.get("err")
    if err == "no_input_box":
        return ("[web_bridge] 页面未找到输入框——请确认 %s 已打开且已完成登录（若已登录仍失败，"
                "说明页面改版，请人工在浏览器里操作一次并反馈）。" %
                LOGIN_URLS.get(provider, LOGIN_URLS[DEFAULT_PROVIDER]))
    if err == "no_reply":
        return "[web_bridge] 发送后未等到新回复（超时 %ds）——页面可能未登录或提问未发出。" % REPLY_WAIT_SECS
    return "[web_bridge] 驱动返回异常：%s（detail=%s）" % (err, result.get("detail", ""))


# ---------------------------------------------------------------------------
# 提问（P0 占位保留为 --offline 模式；默认走 P2 真实驱动）
# ---------------------------------------------------------------------------

_OFFLINE_MODE = False


def send_question(text: str, history: list[dict[str, str]] | None = None) -> str:
    """向网页版 AI 发送提问并等待回答（P2 真实驱动）。"""
    if not isinstance(text, str) or not text.strip():
        raise ValueError("send_question: text 必须是非空字符串")
    if _OFFLINE_MODE:
        return "[web_bridge P0 占位] 真实网页版会话驱动留待 P2；收到提问：%s" % text.strip()
    provider = _CURRENT_PROVIDER
    cdp_port = _CDP_PORT
    return cdp_send_question(text.strip(), provider, cdp_port)


# 运行期全局配置（--serve 参数注入）
_CURRENT_PROVIDER = DEFAULT_PROVIDER
_CDP_PORT = DEFAULT_CDP_PORT


def configure(provider: str, cdp_port: int) -> None:
    global _CURRENT_PROVIDER, _CDP_PORT
    _CURRENT_PROVIDER = provider
    _CDP_PORT = cdp_port


def _wait_answer_placeholder() -> None:
    time.sleep(0)


def _extract_answer_placeholder(raw: Any) -> str:
    return str(raw)


# ---------------------------------------------------------------------------
# MCP 工具骨架（JSON-RPC 2.0 面，供网关 /mcp 转发）
# ---------------------------------------------------------------------------

ToolHandler = Callable[[dict[str, Any]], Any]

TOOL_CONTRACT: dict[str, dict[str, Any]] = {
    "web_search": {
        "description": "网页版 AI 联网搜索：给定 query，返回筛选后的结论与来源列表（title/url/snippet）",
        "required": ["query"],
        "optional": ["max_results"],
    },
    "web_extract": {
        "description": "从目标 URL 提炼要点与来源（url 必填，question 可选）",
        "required": ["url"],
        "optional": ["question"],
    },
    "chat": {
        "description": "通用对话问答（prompt 必填，history 可选）",
        "required": ["prompt"],
        "optional": ["history"],
    },
}


def _tool_web_search(args: dict[str, Any]) -> list[dict[str, str]]:
    query = args.get("query")
    if not isinstance(query, str) or not query.strip():
        raise ValueError("web_search: 缺少必填参数 query（非空字符串）")
    max_results = args.get("max_results")
    if max_results is not None and (not isinstance(max_results, int) or max_results <= 0):
        raise ValueError("web_search: max_results 必须是正整数")
    answer = send_question(query)
    # 驱动成功 → 把回复作为结论；来源列表留空（网页版 AI 会在正文给出链接）
    if answer.startswith("[web_bridge]"):
        return [{"title": answer, "url": "", "snippet": ""}]
    snippet = answer[:300]
    return [
        {
            "title": "网页版 AI 搜索结论：%s" % query.strip(),
            "url": "",
            "snippet": snippet,
        }
    ]


def _tool_web_extract(args: dict[str, Any]) -> dict[str, Any]:
    url = args.get("url")
    if not isinstance(url, str) or not url.strip():
        raise ValueError("web_extract: 缺少必填参数 url（非空字符串）")
    question = args.get("question", "")
    prompt = "请提炼该页面的要点与来源：%s" % url.strip()
    if isinstance(question, str) and question.strip():
        prompt += "（关注：%s）" % question.strip()
    answer = send_question(prompt)
    if answer.startswith("[web_bridge]"):
        return {"points": [answer], "sources": [{"url": url.strip()}]}
    return {"points": [p for p in answer.splitlines() if p.strip()], "sources": [{"url": url.strip()}]}


def _tool_chat(args: dict[str, Any]) -> dict[str, Any]:
    prompt = args.get("prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        raise ValueError("chat: 缺少必填参数 prompt（非空字符串）")
    history = args.get("history")
    if history is not None and not isinstance(history, list):
        raise ValueError("chat: history 必须是消息数组")
    answer = send_question(prompt, history)
    return {"text": answer}


TOOL_HANDLERS: dict[str, ToolHandler] = {
    "web_search": _tool_web_search,
    "web_extract": _tool_web_extract,
    "chat": _tool_chat,
}


def tools_list() -> list[dict[str, Any]]:
    out = []
    for name, spec in TOOL_CONTRACT.items():
        props = {}
        for key in spec["required"] + spec["optional"]:
            props[key] = {"type": "string" if key != "max_results" else "integer"}
        out.append(
            {
                "name": name,
                "description": spec["description"],
                "inputSchema": {
                    "type": "object",
                    "properties": props,
                    "required": spec["required"],
                },
            }
        )
    return out


def dispatch_tool(name: str, args: dict[str, Any]) -> Any:
    if name not in TOOL_HANDLERS:
        raise KeyError("未知工具：%s（可用：%s）" % (name, ", ".join(TOOL_HANDLERS)))
    return TOOL_HANDLERS[name](args or {})


def handle_jsonrpc(payload: dict[str, Any]) -> dict[str, Any]:
    method = str(payload.get("method", ""))
    params = payload.get("params") or {}
    if method == "initialize":
        return {
            "jsonrpc": "2.0", "id": payload.get("id"),
            "result": {
                "protocolVersion": "2024-11-05",
                "serverInfo": {"name": "svc-webai", "version": "0.2.0"},
                "capabilities": {"tools": {}},
            },
        }
    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": payload.get("id"),
                "result": {"tools": tools_list()}}
    if method == "tools/call":
        name = str(params.get("name", ""))
        try:
            value = dispatch_tool(name, params.get("arguments") or {})
        except KeyError as exc:
            return {"jsonrpc": "2.0", "id": payload.get("id"),
                    "error": {"code": -32601, "message": str(exc)}}
        except ValueError as exc:
            return {"jsonrpc": "2.0", "id": payload.get("id"),
                    "error": {"code": -32602, "message": str(exc)}}
        except Exception as exc:  # noqa: BLE001
            return {"jsonrpc": "2.0", "id": payload.get("id"),
                    "error": {"code": -32603, "message": "工具执行失败：%s" % exc}}
        return {"jsonrpc": "2.0", "id": payload.get("id"),
                "result": {"content": [{"type": "text", "text": json.dumps(value, ensure_ascii=False)}]}}
    return {"jsonrpc": "2.0", "id": payload.get("id"),
            "error": {"code": -32601, "message": "未知方法：%s" % method}}


# ---------------------------------------------------------------------------
# P1 网关：/health + /mcp + /v1/models + /v1/chat/completions（fist_gateway 模式）
# ---------------------------------------------------------------------------

def ensure_api_key(path: Path = APIKEY_FILE) -> str:
    """key 明文只落 .fist-mbt/data/svc-webai.apikey（首行）；已存在则原样复用。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file():
        key = path.read_text(encoding="utf-8").strip().splitlines()[0].strip()
        if key:
            return key
    key = secrets.token_hex(12)
    path.write_text(key + "\n", encoding="utf-8")
    return key


def join_model_router(service_id: str, endpoint: str, capabilities: str,
                      router_config: Path = ROUTER_CONFIG) -> str:
    """把 svc-webai 端点登记进模型路由配置的 agent_services 数组（幂等）。"""
    cfg: dict = {}
    try:
        with open(router_config, encoding="utf-8") as f:
            loaded = json.load(f)
        if isinstance(loaded, dict):
            cfg = loaded
    except (OSError, json.JSONDecodeError):
        cfg = {}
    services = [s for s in cfg.get("agent_services", [])
                if isinstance(s, dict) and s.get("service_id") != service_id]
    services.append({
        "service_id": service_id,
        "endpoint": endpoint,
        "capabilities": capabilities,
        "joined_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    })
    cfg["agent_services"] = services
    router_config.parent.mkdir(parents=True, exist_ok=True)
    with open(router_config, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    return "已加入模型自动路由网关（%s · agent_services[%d]）" % (router_config, len(services))


def router_agent_services(router_config: Path = ROUTER_CONFIG) -> list:
    try:
        with open(router_config, encoding="utf-8") as f:
            cfg = json.load(f)
        services = cfg.get("agent_services") or []
        return services if isinstance(services, list) else []
    except (OSError, json.JSONDecodeError, AttributeError):
        return []


class WebBridgeGateway:
    """svc-webai 常驻网关：/health + /mcp + /v1/models + /v1/chat/completions。"""

    def __init__(self, args) -> None:
        self.args = args
        self.service_id = "svc-webai"
        self.host = args.host
        self.port = args.port
        self.listen_addr = "%s:%d" % (args.host, args.port)
        key = ensure_api_key(APIKEY_FILE)
        self.api_key_hash = hashlib.sha256(key.encode()).hexdigest()
        self.rate_limit = args.rate_limit
        self._req_times: dict[str, deque] = {}
        self._req_lock = threading.Lock()
        self.audit_path = args.audit_log or str(DEFAULT_AUDIT_LOG)
        self._audit_lock = threading.Lock()
        self.stop_event = threading.Event()
        configure(args.provider, args.cdp_port)

    # ---- 认证与限流（fist_gateway §4.1 同款） ----

    def _key_fingerprint(self, headers) -> str:
        key = headers.get("X-API-Key", "")
        if not key:
            auth = headers.get("Authorization", "")
            if auth.startswith("Bearer "):
                key = auth[len("Bearer "):]
        return hashlib.sha256(key.encode()).hexdigest() if key else ""

    def auth_ok(self, headers, peer_ip: str) -> bool:
        if not self.api_key_hash:
            return args_host_is_local(self.args)
        fp = self._key_fingerprint(headers)
        if fp != self.api_key_hash:
            return False
        now = time.time()
        with self._req_lock:
            dq = self._req_times.setdefault(fp, deque())
            while dq and now - dq[0] > 60.0:
                dq.popleft()
            if len(dq) >= self.rate_limit:
                return False
            dq.append(now)
        return True

    def _audit(self, event: str, detail: dict) -> None:
        try:
            line = json.dumps({
                "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "service_id": self.service_id,
                "event": event,
                **detail,
            }, ensure_ascii=False)
            with self._audit_lock:
                Path(self.audit_path).parent.mkdir(parents=True, exist_ok=True)
                with open(self.audit_path, "a", encoding="utf-8") as f:
                    f.write(line + "\n")
        except Exception as exc:  # noqa: BLE001
            log.error("审计写失败（不阻断主流程）: %s", exc)

    def heartbeat_loop(self) -> None:
        state = load_session()
        while not self.stop_event.wait(timeout=HEARTBEAT_INTERVAL_SECS):
            try:
                heartbeat(state)
            except Exception as exc:  # noqa: BLE001
                log.error("心跳写库失败: %s", exc)

    def run(self) -> None:
        log.info("API-key 已启用（sha256=%s…；明文在 %s）", self.api_key_hash[:12], APIKEY_FILE)
        # P3：自动加入模型路由（幂等）
        log.info(join_model_router(
            self.service_id,
            "http://%s/mcp" % self.listen_addr,
            json.dumps(list(TOOL_CONTRACT), ensure_ascii=False),
        ))
        # 登录态：网关常驻模式不做交互引导（后台进程无 stdin）；直接标记，
        # 真实登录在拉起调试浏览器后由用户完成（cookie 落独立 profile 复用）
        state = load_session()
        provider = state.get(FIELD_PROVIDER, self.args.provider)
        if not state.get(FIELD_LOGGED_IN):
            mark_logged_in(state, provider)
        log.info("会话状态：logged_in=%s provider=%s（文件 %s）",
                 bool(state.get(FIELD_LOGGED_IN)), provider, SESSION_FILE)
        if not cdp_reachable(self.args.cdp_port):
            msg = launch_debug_chrome(self.args.cdp_port)
            log.info("浏览器状态：%s（请在该 Chrome 窗口登录 %s，登录态会保留在 %s）",
                     msg, LOGIN_URLS.get(provider, LOGIN_URLS[DEFAULT_PROVIDER]), WEBAI_PROFILE_DIR)
        threading.Thread(target=self.heartbeat_loop, daemon=True).start()
        log.info("svc-webai 常驻：http://%s/health ｜ http://%s/mcp", self.listen_addr, self.listen_addr)
        self._http_serve()

    # ---- HTTP 面 ----

    def _http_serve(self) -> None:
        gateway = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:
                path = self.path.split("?")[0]
                if path not in ("/health", "/v1/models"):
                    self.send_response(404)
                    self.end_headers()
                    return
                if path == "/v1/models":
                    self._handle_models()
                    return
                body = json.dumps({
                    "service_id": gateway.service_id,
                    "alive": True,
                    "listen_addr": gateway.listen_addr,
                    "pid": os.getpid(),
                }).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def _handle_models(self) -> None:
                if not gateway.auth_ok(self.headers, self.client_address[0]):
                    gateway._audit("auth_fail", {"ip": self.client_address[0]})
                    self.send_response(401)
                    self.end_headers()
                    return
                models = [{
                    "id": "agent:%s" % s.get("endpoint", ""),
                    "object": "model",
                    "owned_by": "fist-agent-service",
                } for s in router_agent_services()]
                body = json.dumps({"object": "list", "data": models}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_POST(self) -> None:
                path = self.path.split("?")[0]
                if path not in ("/mcp", "/v1/chat/completions"):
                    self.send_response(404)
                    self.end_headers()
                    return
                auth_ok = gateway.api_key_hash == "" or gateway.auth_ok(
                    self.headers, self.client_address[0])
                if not auth_ok:
                    gateway._audit("auth_fail", {"ip": self.client_address[0]})
                    self.send_response(401)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                length = int(self.headers.get("Content-Length", "0"))
                try:
                    payload = json.loads(self.rfile.read(length) or b"{}")
                except json.JSONDecodeError:
                    self.send_response(400)
                    self.end_headers()
                    return
                if path == "/v1/chat/completions":
                    self._handle_chat_completions(payload)
                    return
                method = str(payload.get("method", ""))
                gateway._audit("mcp_call", {"ip": self.client_address[0], "method": method})
                resp = handle_jsonrpc(payload)
                body = json.dumps(resp).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def _handle_chat_completions(self, payload: dict) -> None:
                gateway._audit("chat_completions", {"ip": self.client_address[0]})
                msgs = payload.get("messages") or []
                prompt = ""
                for m in reversed(msgs):
                    if isinstance(m, dict) and m.get("role") == "user":
                        prompt = str(m.get("content", ""))
                        break
                if not prompt:
                    body = json.dumps({"error": {"message": "messages 里没有 user 内容"}}).encode()
                    self.send_response(400)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    return
                answer = send_question(prompt[:2000])
                content = answer
                body = json.dumps({
                    "id": "chatcmpl-webai-%d" % int(time.time() * 1000),
                    "object": "chat.completion",
                    "created": int(time.time()),
                    "model": payload.get("model", "svc-webai"),
                    "choices": [{
                        "index": 0,
                        "message": {"role": "assistant", "content": content},
                        "finish_reason": "stop",
                    }],
                    "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
                }).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, fmt, *log_args) -> None:
                log.info(fmt, *log_args)

        server = ThreadingHTTPServer((self.host, self.port), Handler)
        server.daemon_threads = True
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            self.stop_event.set()
            server.shutdown()


def args_host_is_local(args) -> bool:
    return args.host in ("127.0.0.1", "localhost")


# ---------------------------------------------------------------------------
# 自检
# ---------------------------------------------------------------------------

def selftest() -> int:
    """非交互自检：会话状态 + 工具契约 + JSON-RPC（offline 占位驱动，不依赖浏览器）。"""
    global _OFFLINE_MODE
    _OFFLINE_MODE = True
    tmp = SESSION_FILE.with_name("webai-session-selftest.json")
    try:
        # 1) 会话状态往返
        state = load_session(tmp)
        assert not state.get(FIELD_LOGGED_IN, False), "初始应为未登录"
        mark_logged_in(state, "deepseek", tmp)
        reloaded = load_session(tmp)
        assert reloaded.get(FIELD_LOGGED_IN) is True, "标记登录后应读回 True"
        assert reloaded.get(FIELD_HEARTBEAT), "应写心跳"
        # 2) 工具注册面 == 契约
        listed = {t["name"] for t in tools_list()}
        assert listed == set(TOOL_CONTRACT), "工具注册面应等于契约"
        for t in tools_list():
            assert t["inputSchema"]["required"] == TOOL_CONTRACT[t["name"]]["required"], "契约 required 一致"
        # 3) JSON-RPC 握手 + 工具调用 + 错误路径
        init = handle_jsonrpc({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
        assert init["result"]["serverInfo"]["name"] == "svc-webai", "握手服务名"
        tl = handle_jsonrpc({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        assert len(tl["result"]["tools"]) == len(TOOL_CONTRACT), "tools/list 数量"
        call = handle_jsonrpc({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                               "params": {"name": "chat", "arguments": {"prompt": "ping"}}})
        assert "占位" in call["result"]["content"][0]["text"], "chat 调用应回占位"
        bad = handle_jsonrpc({"jsonrpc": "2.0", "id": 4, "method": "tools/call",
                              "params": {"name": "nope", "arguments": {}}})
        assert bad["error"]["code"] == -32601, "未知工具 -32601"
        bad2 = handle_jsonrpc({"jsonrpc": "2.0", "id": 5, "method": "tools/call",
                               "params": {"name": "chat", "arguments": {}}})
        assert bad2["error"]["code"] == -32602, "缺参 -32602"
        print("[selftest] 全部通过：会话状态 / 工具契约 / JSON-RPC（8 项断言）")
        return 0
    finally:
        _OFFLINE_MODE = False
        try:
            tmp.unlink()
        except OSError:
            pass


# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------

def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="web-bridge：网页版 AI 常驻桥接网关（svc-webai）")
    ap.add_argument("--serve", action="store_true", help="以常驻网关模式运行（/health + /mcp）")
    ap.add_argument("--selftest", action="store_true", help="非交互自检")
    ap.add_argument("--port", type=int, default=18645, help="网关监听端口（默认 18645，避开 18640/18641/18643/18644）")
    ap.add_argument("--host", default="127.0.0.1", help="监听地址（local 档默认 127.0.0.1）")
    ap.add_argument("--provider", default=DEFAULT_PROVIDER, choices=list(LOGIN_URLS),
                    help="网页版 AI 提供方（deepseek / yuanbao）")
    ap.add_argument("--cdp-port", type=int, default=DEFAULT_CDP_PORT,
                    help="Chrome 调试端口（CDP，默认 9222）")
    ap.add_argument("--rate-limit", type=int, default=RATE_LIMIT_PER_MIN,
                    help="per-key 限流：每分钟请求数上限（默认 60）")
    ap.add_argument("--audit-log", default="", help="审计文件路径（默认 temp/gateway-svc-webai.log）")
    ap.add_argument("--offline", action="store_true", help="占位驱动模式（不连接浏览器，仅自测/演示）")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()
    if args.offline:
        global _OFFLINE_MODE
        _OFFLINE_MODE = True
    if not args.serve:
        # 无参数交互式首启（P0 行为保留）
        state = load_session()
        provider = state.get(FIELD_PROVIDER, args.provider)
        if not state.get(FIELD_LOGGED_IN):
            first_run_guide(provider)
            mark_logged_in(state, provider)
        print("svc-webai 运行中（会话状态 → %s）。心跳循环启动（Ctrl+C 退出；网关模式用 --serve）。"
              % SESSION_FILE)
        try:
            while True:
                heartbeat(state)
                time.sleep(HEARTBEAT_INTERVAL_SECS)
        except KeyboardInterrupt:
            return 0
    if args.port in (18640, 18641, 18643, 18644):
        sys.exit("FATAL: 端口 %d 属既有服务红线，请换 --port（建议 18645）" % args.port)
    WebBridgeGateway(args).run()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
