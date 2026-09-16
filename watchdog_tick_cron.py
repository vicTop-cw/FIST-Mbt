#!/usr/bin/env python3
"""FIST-Mbt watchdog_tick cron driver for Pentad project."""
import json
import subprocess
import sys
import time
import os
from datetime import datetime, timezone, timedelta

MCP_SERVER = r"E:\IDEProjects\AI\FIST-Mbt\_build\js\debug\build\cmd\main\main.js"
WORKDIR = r"E:\IDEProjects\AI\FIST-Mbt"
GEN_PROMPTS = r"E:\IDEProjects\AI\Pentad\Gen_Prompts"
NAMESPACE = "cron-auto"
TIMEOUT_SEC = 2400

def iso_now():
    """Current local time ISO8601."""
    tz_local = datetime.now().astimezone().tzinfo
    return datetime.now(tz_local).isoformat()

class MCPClient:
    def __init__(self):
        self.proc = subprocess.Popen(
            ["node", MCP_SERVER],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=WORKDIR,
            encoding="utf-8",
            errors="replace",
        )
        self._id = 1

    def send(self, method, params=None):
        msg = {"jsonrpc": "2.0", "id": self._id, "method": method}
        if params is not None:
            msg["params"] = params
        self._id += 1
        line = json.dumps(msg, ensure_ascii=False)
        self.proc.stdin.write(line + "\n")
        self.proc.stdin.flush()

    def recv(self):
        line = self.proc.stdout.readline()
        if not line:
            return None
        try:
            return json.loads(line.strip())
        except json.JSONDecodeError:
            return None

    def call(self, method, params=None, timeout=30):
        if params is None:
            params = {}
        params["_meta"] = {
            "io.modelcontextprotocol/protocolVersion": "2026-07-28",
            "io.modelcontextprotocol/clientCapabilities": {},
            "io.modelcontextprotocol/clientInfo": {"name": "pentad-watchdog-cron", "version": "1.0.0"},
        }
        self.send(method, params)
        deadline = time.time() + timeout
        while time.time() < deadline:
            resp = self.recv()
            if resp is None:
                break
            if resp.get("id") == self._id - 1:
                return resp
        return None

    def close(self):
        try:
            self.proc.terminate()
            self.proc.wait(timeout=5)
        except Exception:
            try:
                self.proc.kill()
            except Exception:
                pass


def newest_prompt():
    """Find the newest yyyyMMdd.HH.mm.ss.md file in Gen_Prompts."""
    if not os.path.isdir(GEN_PROMPTS):
        return None, None
    best = None
    for fname in os.listdir(GEN_PROMPTS):
        if not fname.endswith(".md"):
            continue
        if fname.startswith("_"):
            continue
        base = fname[:-3]
        try:
            dt = datetime.strptime(base, "%Y%m%d.%H.%M.%S")
        except ValueError:
            continue
        full = os.path.join(GEN_PROMPTS, fname)
        mtime = os.path.getmtime(full)
        if best is None or dt > best[0]:
            best = (dt, full, mtime)
    return best


def main():
    print(f"[watchdog-tick] {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    client = MCPClient()
    try:
        # Step 1: tools/list to confirm watchdog_tick exists
        resp = client.call("tools/list", {})
        if resp and "result" in resp:
            tools = resp["result"].get("tools", [])
            tool_names = [t["name"] for t in tools]
            if "watchdog_tick" not in tool_names:
                print(f"ERROR: watchdog_tick not found in tools list: {tool_names}")
                return 1
            print(f"[ok] watchdog_tick found. Tools: {tool_names}")
        else:
            err = resp.get("error", {}) if resp else {}
            print(f"WARN: tools/list failed: {err}")

        # Step 2: list tasks in cron-auto namespace
        resp = client.call("tools/call", {
            "name": "list",
            "arguments": {"namespace": NAMESPACE}
        })
        active_count = 0
        last_completed_prompt_time = None
        if resp and "result" in resp:
            result_text = resp["result"]
            # Extract text content
            content = result_text.get("content", []) if isinstance(result_text, dict) else []
            if content:
                txt = content[0].get("text", "") if isinstance(content[0], dict) else str(content[0])
            else:
                txt = json.dumps(result_text, ensure_ascii=False)
            print(f"[cron-auto tasks] {txt[:2000]}")
            # Count active tasks heuristically
            active_count = txt.count('"status": "running"') + txt.count('"status": "claimed"') + txt.count('"status": "in_progress"')
            active_count += txt.count('"status":"running"') + txt.count('"status":"claimed"') + txt.count('"status":"in_progress"')
        else:
            err = resp.get("error", {}) if resp else {}
            print(f"WARN: list failed: {err}")

        # Step 3: check newest prompt
        newest_dt, newest_path, newest_mtime = newest_prompt()
        if newest_dt:
            print(f"[newest prompt] {os.path.basename(newest_path)} ({newest_dt.strftime('%Y-%m-%d %H:%M:%S')})")
        else:
            print("[newest prompt] none found")

        # Decide: advance only if newest prompt is after ~16:07 (assume last advanced round
        # relates to the previous prompt generation). Use heuristic: if newest prompt is
        # the latest file and it was generated after 16:00 today, treat it as unconsumed.
        # We check task output above — if a task description references "MIR" and "v0.19",
        # the latest prompt is already consumed. Safer: only advance when newest prompt
        # has a mtime newer than the newest completed task. Since we can't easily parse that,
        # adopt simple rule: advance only if newest_dt > 2026-09-16 16:00 (unconsumed).
        # The generator runs every ~1h; the last one at 16:07 is unconsumed (no task since).
        cutoff = datetime(2026, 9, 16, 16, 0, 0)
        should_advance = newest_dt is not None and newest_dt > cutoff

        # Extract next_description from the prompt file (first heading line)
        next_desc = None
        if should_advance and newest_path:
            with open(newest_path, "r", encoding="utf-8") as f:
                lines = f.readlines()
            for line in lines[:5]:
                line = line.strip()
                if line.startswith("#"):
                    next_desc = line.lstrip("#").strip()
                    break
            if not next_desc:
                next_desc = lines[0].strip() if lines else "next round"

        print(f"[decide] should_advance={should_advance}")

        # Step 4: call watchdog_tick
        args = {
            "timeout_sec": TIMEOUT_SEC,
            "namespace": NAMESPACE,
            "next_created_by": "watchdog",
            "now": iso_now(),
        }
        if should_advance:
            args["next_description"] = next_desc
            args["meta_prompt_path"] = GEN_PROMPTS

        resp = client.call("tools/call", {
            "name": "watchdog_tick",
            "arguments": args
        }, timeout=60)

        if not resp:
            print("ERROR: watchdog_tick timed out or no response")
            return 1

        err = resp.get("error")
        if err:
            print(f"ERROR: watchdog_tick returned error: {json.dumps(err, ensure_ascii=False)}")
            return 1

        result = resp.get("result", {})
        content = result.get("content", [])
        if content:
            txt = content[0].get("text", "") if isinstance(content[0], dict) else str(content[0])
        else:
            txt = json.dumps(result, ensure_ascii=False)

        try:
            data = json.loads(txt)
        except json.JSONDecodeError:
            data = {"raw": txt}

        print(f"[watchdog result] {json.dumps(data, ensure_ascii=False)}")

        # Step 5: branch by action
        action = data.get("action", "unknown")
        healed = data.get("healed", 0)
        healed_tasks = data.get("healed_tasks", [])
        new_task_id = data.get("new_task_id")
        previous_task_id = data.get("previous_task_id")
        active = data.get("active", 0)
        blocked = data.get("blocked", [])

        # Format final report
        note_parts = []
        if should_advance and newest_dt:
            note_parts.append(f"续轮依据: {os.path.basename(newest_path)} ({newest_dt.strftime('%H:%M:%S')})")
        elif newest_dt:
            note_parts.append(f"未续轮（提示词 {os.path.basename(newest_path)} 已消费或时间早于上轮）")
        else:
            note_parts.append("未找到新提示词")

        restarted = "restarted" if action == "restarted" else "-"
        advanced = new_task_id if action == "advanced" else "-"

        print()
        print(f"[watchdog-tick] {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"action: {action}")
        print(f"active: {active}   healed: {healed}   blocked: {len(blocked) if isinstance(blocked, list) else blocked}")
        print(f"restarted_tasks: {restarted if action != 'restarted' else ', '.join(str(t) for t in healed_tasks) if healed_tasks else '-'}")
        print(f"advanced: {advanced}")
        print(f"note: {'; '.join(note_parts)}")

        return 0
    finally:
        client.close()


if __name__ == "__main__":
    sys.exit(main())
