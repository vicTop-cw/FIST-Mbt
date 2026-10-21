# -*- coding: utf-8 -*-
"""通用 fist-mbt 发布版 MCP 客户端封装（stdio, 协议 2026-07-28, cwd=项目根）。

用法:
    from fist_client import FistClient
    fc = FistClient()            # 自动启动 node fist-mbt.js serve (cwd=PROJ)
    r = fc.call("store_list")
    print(r)
    fc.close()
"""
import subprocess, json, os, threading, time, sys

# BUG-381：Windows 控制台默认 cp936，打印中文结论会 UnicodeEncodeError 崩在结论行前，
# 退出码被冒用成「缺陷在场」。CI 的 check_py_stdout_encoding.py --all 以此闸为准。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

PROJ = r"E:\IDEProjects\AI\FIST-Mbt"
JS = os.path.join(os.environ["LOCALAPPDATA"], "FIST-Mbt", "fist-mbt.js")
PROTOCOL = "2026-07-28"


class FistClient:
    def __init__(self, cwd=None, debug=False):
        self.cwd = cwd or PROJ
        self.debug = debug
        # BUG-124：serve 的子进程必须拿到 FIST_DB_PATH 显式改道针，
        # 否则裸跑会写仓库根自举台账 fist-mbt.db（temp/ 已 gitignore，不污染根）。
        env = dict(os.environ)
        if not env.get("FIST_DB_PATH"):
            tmpdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "temp")
            os.makedirs(tmpdir, exist_ok=True)
            env["FIST_DB_PATH"] = os.path.join(tmpdir, "fist_mbt_mcp_client.db")
        self.p = subprocess.Popen(
            ["node", JS, "serve"],
            cwd=self.cwd, env=env,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", errors="replace", bufsize=1
        )
        self._out = []
        self._err = []
        threading.Thread(target=lambda: [self._out.append(l.rstrip()) for l in self.p.stdout], daemon=True).start()
        threading.Thread(target=lambda: [self._err.append(l.rstrip()) for l in self.p.stderr], daemon=True).start()
        self._req_id = 0
        self._init()

    def _init(self):
        self._send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                    "params": {"protocolVersion": PROTOCOL, "capabilities": {},
                               "clientInfo": {"name": "fist-client", "version": "1.0"}}})
        self._readline()
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
        self._req_id = 2

    def _send(self, obj):
        self.p.stdin.write(json.dumps(obj, ensure_ascii=False) + "\n")
        self.p.stdin.flush()

    def _readline(self, timeout=30):
        start = time.time()
        while time.time() - start < timeout:
            if self._out:
                return self._out.pop(0)
            time.sleep(0.05)
        return None

    def call(self, tool, args=None, timeout=120):
        self._req_id += 1
        req = {"jsonrpc": "2.0", "id": self._req_id, "method": "tools/call",
               "params": {"name": tool, "arguments": args or {}}}
        self._send(req)
        deadline = time.time() + timeout
        while time.time() < deadline:
            line = self._readline(timeout=timeout)
            if line is None:
                break
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if obj.get("id") == self._req_id:
                if self.debug:
                    print(f"[{tool}] =>", line[:800])
                if "error" in obj:
                    return {"error": True, "text": "JSONRPC_ERROR: " + json.dumps(obj["error"], ensure_ascii=False)}
                res = obj.get("result", {})
                if res.get("isError"):
                    return {"error": True, "content": res.get("content")}
                # 提取 text 内容
                texts = []
                for c in res.get("content", []):
                    if c.get("type") == "text":
                        texts.append(c.get("text", ""))
                return {"error": False, "text": "\n".join(texts)}
        return {"error": True, "text": "TIMEOUT"}

    def close(self):
        try:
            self.p.kill()
        except Exception:
            pass


if __name__ == "__main__":
    fc = FistClient()
    try:
        print("== store_list ==")
        print(fc.call("store_list"))
        print("== status_summary ==")
        print(fc.call("status_summary"))
        print("== project_health ==")
        print(fc.call("project_health"))
        print("== bug_list ==")
        print(fc.call("bug_list", {"project_dir": "."}))
    finally:
        fc.close()
