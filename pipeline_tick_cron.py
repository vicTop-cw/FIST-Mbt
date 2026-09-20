#!/usr/bin/env python3
"""FIST-Mbt pipeline_tick cron driver —— 无人值守流水线状态机外部驱动（currentState.txt 版）。

与 watchdog_tick_cron.py 的差异（空转根因修复）：

  watchdog_tick_cron.py 用「Gen_Prompts 提示词是否比 last_consumed 新」自行判断是否推进，
  只要出现更新的提示词就发布新根任务；上一轮任务是否真的完成不参与判断。
  于是出现：任务连续发布 17 轮、每轮都停在「待领取」无人消化的空转堆积。

  本脚本改为每次唤醒只调用 FIST-Mbt 的 pipeline_tick MCP 工具，由服务端状态机裁决，
  不在客户端做任何「要不要推进」的二次判断：

    currentState.txt   action           含义
    ---------------    ---------------  --------------------------------------------------
    absent / Creating  generate         需外部 LLM 生成任务提示词（分支 A）
    Pending            execute          发布/续轮根任务（分支 B 起点）
    Pending            wait             在途任务未完成，不重发、不堆积（幂等）
    Pending            write_report     上一轮任务已非活跃但报告缺失，先补报告（分支 C）
    Running            wait             任务未超时，本轮不动
    Running            closed           报告已落盘，状态收口为 Closed
    Running            write_report     超时且无报告，要求补报告（绝不写「Closed 无报告」）
    Closed             generate         上一轮报告已落盘，推进下一轮（分支 A）
    Closed             write_report     报告缺失，阻塞推进（报告先行）
    invalid            safe_exit        状态不可识别/读取失败，不改任何状态

  报告先行：Closed 之前 Reports/<提示词同名>.md 必须已落盘，由 pipeline_tick 校验。

用法：
    python pipeline_tick_cron.py            # 逐项目 tick 一次
建议由 schtasks 与 execute_cron.py 同频（45 分钟）调度；本脚本只做状态机裁决，
不执行任务本体（任务执行由 execute_cron.py 驱动 codearts 完成）。
"""
import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime

MCP_SERVER = r"E:\IDEProjects\AI\FIST-Mbt\_build\js\debug\build\cmd\main\main.js"
WORKDIR = r"E:\IDEProjects\AI\FIST-Mbt"
TIMEOUT_SEC = 2400

PROJECTS = [
    {"name": "pentad", "project_dir": r"E:\IDEProjects\AI\Pentad", "namespace": "cron-auto"},
    {"name": "tnr",    "project_dir": r"E:\IDEProjects\AI\Tnr",    "namespace": "cron-tnr"},
]

# action -> 元提示词里的分支名（汇报用）
BRANCH = {
    "generate": "A-生成",
    "execute": "B-领取执行",
    "wait": "B-等待",
    "closed": "B-收口",
    "write_report": "C-兜底",
    "restarted": "C-兜底",
    "safe_exit": "0-安全退出",
    "idle": "0-空闲",
}

os.chdir(os.path.dirname(os.path.abspath(__file__)))


def iso_now():
    return datetime.now().astimezone().isoformat()


class MCPClient:
    def __init__(self):
        self.proc = subprocess.Popen(
            ["node", MCP_SERVER],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            cwd=WORKDIR, encoding="utf-8", errors="replace",
        )
        self._id = 1

    def call(self, method, params=None, timeout=60):
        if params is None:
            params = {}
        params["_meta"] = {
            "io.modelcontextprotocol/protocolVersion": "2026-07-28",
            "io.modelcontextprotocol/clientCapabilities": {},
            "io.modelcontextprotocol/clientInfo": {"name": "pipeline-tick-cron", "version": "1.0.0"},
        }
        msg = {"jsonrpc": "2.0", "id": self._id, "method": method, "params": params}
        self._id += 1
        self.proc.stdin.write(json.dumps(msg, ensure_ascii=False) + "\n")
        self.proc.stdin.flush()
        deadline = time.time() + timeout
        while time.time() < deadline:
            line = self.proc.stdout.readline()
            if not line:
                return None
            try:
                resp = json.loads(line.strip())
            except json.JSONDecodeError:
                continue
            if resp.get("id") == self._id - 1:
                return resp
        return None

    def tool(self, name, arguments, timeout=60):
        resp = self.call("tools/call", {"name": name, "arguments": arguments}, timeout=timeout)
        if not resp or "error" in resp:
            return None
        content = resp.get("result", {}).get("content", [])
        if not content:
            return ""
        return content[0].get("text", "") if isinstance(content[0], dict) else str(content[0])

    def close(self):
        try:
            self.proc.terminate()
            self.proc.wait(timeout=5)
        except Exception:
            try:
                self.proc.kill()
            except Exception:
                pass


def tick_project(client, proj):
    """对单个项目执行一次 pipeline_tick，打印状态机汇报。返回退出码。"""
    name = proj["name"]
    args = {
        "project_dir": proj["project_dir"],
        "namespace": proj["namespace"],
        "now": iso_now(),
        "timeout_sec": TIMEOUT_SEC,
    }
    txt = client.tool("pipeline_tick", args, timeout=120)
    if txt is None:
        print(f"[{name}] ERROR: pipeline_tick 调用失败")
        return 1
    try:
        d = json.loads(txt)
    except json.JSONDecodeError:
        print(f"[{name}] ERROR: 返回非 JSON: {txt[:200]}")
        return 1

    action = d.get("action", "unknown")
    print(f"[cron-loop] {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ({name})")
    print(f"state_in:   {d.get('state_in')}")
    print(f"branch:     {BRANCH.get(action, action)}")
    print(f"state_out:  {d.get('state_out')}")
    print(f"generated:  {d.get('prompt_file') or '-'}")
    print(f"reported:   {d.get('report_path') or '-'}")
    print(f"result:     {d.get('task_id') or '-'}")
    print(f"note:       {d.get('note')}")
    if d.get("healed"):
        print(f"healed:     {d.get('healed')}")

    if action == "generate":
        print(f"[{name}] 需外部生成下一份提示词（Gen_Prompts/yyyyMMdd.HH.mm.ss.md），"
              f"落盘后将状态置 Pending，随后由 pipeline_tick 发布任务。")
    elif action == "execute":
        print(f"[{name}] 根任务 {d.get('task_id')} 已发布，等待 execute_cron.py 领取执行。")
    elif action == "safe_exit":
        print(f"[{name}] 状态不可识别或读取失败，本轮未修改任何状态，请人工确认 currentState.txt。")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default="all", help="pentad / tnr / all")
    opt = ap.parse_args()
    targets = PROJECTS if opt.project == "all" else [p for p in PROJECTS if p["name"] == opt.project]
    if not targets:
        print(f"ERROR: 未知项目 {opt.project}")
        return 1

    client = MCPClient()
    failures = 0
    try:
        resp = client.call("tools/list", {})
        if resp and "result" in resp:
            names = [t["name"] for t in resp["result"].get("tools", [])]
            if "pipeline_tick" not in names:
                print(f"ERROR: pipeline_tick 未注册（当前工具数 {len(names)}），请先 moon build 重建服务端")
                return 1
        for proj in targets:
            try:
                if tick_project(client, proj) != 0:
                    failures += 1
            except Exception as e:
                print(f"[{proj['name']}] EXCEPTION: {e}")
                failures += 1
        return 1 if failures else 0
    finally:
        client.close()


if __name__ == "__main__":
    sys.exit(main())
