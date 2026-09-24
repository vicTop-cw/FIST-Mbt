#!/usr/bin/env python3
"""FIST-Mbt watchdog_tick cron driver — round-robin over Pentad/Tnr."""
import json
import subprocess
import sys
import time
import os
from datetime import datetime
from threading import Thread
from queue import Queue, Empty

MCP_SERVER = r"E:\IDEProjects\AI\FIST-Mbt\_build\js\debug\build\cmd\main\main.js"
WORKDIR = r"E:\IDEProjects\AI\FIST-Mbt"
TIMEOUT_SEC = 2400

# Round-robin targets: one project per invocation, chosen by least-recently-advanced.
PROJECTS = [
    {"name": "pentad", "gen_prompts": r"E:\IDEProjects\AI\Pentad\Gen_Prompts", "namespace": "cron-auto", "state_file": r"E:\IDEProjects\AI\FIST-Mbt\.cron_state_pentad.json"},
    {"name": "tnr",    "gen_prompts": r"E:\IDEProjects\AI\Tnr\Gen_Prompts",    "namespace": "cron-tnr",  "state_file": r"E:\IDEProjects\AI\FIST-Mbt\.cron_state_tnr.json"},
]

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
            stderr=subprocess.DEVNULL,
            cwd=WORKDIR,
            encoding="utf-8",
            errors="replace",
        )
        self._id = 1
        # readline() 会无限阻塞；改用后台线程 + Queue.get(timeout) 让 deadline 真正生效（Windows 管道不支持 select）
        self._lines = Queue()
        self._reader = Thread(target=self._read_loop, daemon=True)
        self._reader.start()

    def _read_loop(self):
        try:
            for line in self.proc.stdout:
                if not line:
                    break
                line = line.strip()
                if not line:
                    continue
                try:
                    self._lines.put(json.loads(line))
                except json.JSONDecodeError:
                    continue  # 跳过坏行继续读，与 EOF 区分开
        except Exception:
            pass

    def send(self, method, params=None):
        msg = {"jsonrpc": "2.0", "id": self._id, "method": method}
        if params is not None:
            msg["params"] = params
        self._id += 1
        line = json.dumps(msg, ensure_ascii=False)
        self.proc.stdin.write(line + "\n")
        self.proc.stdin.flush()

    def recv(self, timeout=None):
        try:
            return self._lines.get(timeout=timeout)
        except Empty:
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
            remaining = max(0.0, deadline - time.time())
            resp = self.recv(remaining)
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


def newest_prompt(gen_prompts):
    """Find the newest yyyyMMdd.HH.mm.ss.md file in the given Gen_Prompts dir."""
    if not os.path.isdir(gen_prompts):
        return None
    best = None
    for fname in os.listdir(gen_prompts):
        if not fname.endswith(".md"):
            continue
        if fname.startswith("_"):
            continue
        base = fname[:-3]
        try:
            dt = datetime.strptime(base, "%Y%m%d.%H.%M.%S")
        except ValueError:
            continue
        full = os.path.join(gen_prompts, fname)
        mtime = os.path.getmtime(full)
        if best is None or dt > best[0]:
            best = (dt, full, mtime)
    return best


def load_state(path):
    """Consumed-state file: {"last_consumed": "yyyyMMdd.HH.mm.ss"}."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def save_state(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    os.replace(tmp, path)


def tick_project(client, proj):
    """One watchdog_tick for a single project. Returns exit code (0 ok, 1 error)."""
    gen_prompts = proj["gen_prompts"]
    namespace = proj["namespace"]
    state_file = proj["state_file"]
    name = proj["name"]

    # Newest prompt in this project's Gen_Prompts
    newest = newest_prompt(gen_prompts)
    if newest is None:
        print(f"[{name}] no prompts found, skip")
        return 0
    newest_dt, newest_path, _ = newest
    newest_key = newest_dt.strftime("%Y%m%d.%H.%M.%S")
    print(f"[{name}] newest prompt: {os.path.basename(newest_path)} ({newest_key})")

    # Unconsumed = newer than state file's last_consumed
    state = load_state(state_file)
    last_consumed = state.get("last_consumed", "")
    should_advance = newest_key > last_consumed
    print(f"[{name}] last_consumed={last_consumed or '(none)'} should_advance={should_advance}")

    # next_description = first heading line of the prompt
    # Preserve [gate:required] marker from the prompt so server gate_verify_gate can detect it
    gate_marker = ""
    next_desc = None
    if should_advance:
        try:
            with open(newest_path, "r", encoding="utf-8") as f:
                lines = f.readlines()
        except OSError:
            lines = []
        for line in lines[:5]:
            stripped = line.strip()
            if "[gate:required]" in stripped:
                gate_marker = "[gate:required] "
                break
        for line in lines[:5]:
            line = line.strip()
            if line.startswith("#"):
                next_desc = line.lstrip("#").strip()
                break
        if not next_desc:
            next_desc = lines[0].strip() if lines else "next round"
        if gate_marker:
            next_desc = gate_marker + next_desc

    args = {
        "timeout_sec": TIMEOUT_SEC,
        "namespace": namespace,
        "next_created_by": "watchdog",
        "now": iso_now(),
    }
    if should_advance:
        args["next_description"] = next_desc
        args["meta_prompt_path"] = gen_prompts
        # Cold start: namespace has no tasks yet and nothing ever consumed ->
        # watchdog_tick needs cold_start=true to publish the first root task.
        if not last_consumed:
            args["cold_start"] = True

    resp = client.call("tools/call", {"name": "watchdog_tick", "arguments": args}, timeout=TIMEOUT_SEC + 120)
    if not resp:
        print(f"[{name}] ERROR: watchdog_tick timed out")
        return 1
    err = resp.get("error")
    if err:
        print(f"[{name}] ERROR: {json.dumps(err, ensure_ascii=False)}")
        return 1

    result = resp.get("result", {})
    content = result.get("content", [])
    txt = content[0].get("text", "") if content and isinstance(content[0], dict) else json.dumps(result, ensure_ascii=False)
    try:
        data = json.loads(txt)
    except json.JSONDecodeError:
        data = {"raw": txt}

    action = data.get("action", "unknown")
    healed = data.get("healed", 0)
    new_task_id = data.get("new_task_id")
    active = data.get("active", 0)
    print(f"[{name}] action={action} active={active} healed={healed} advanced={new_task_id or '-'}")

    # Mark consumed ONLY when a task actually consumed it (advanced with new task id)
    if action == "advanced" and new_task_id:
        state["last_consumed"] = newest_key
        save_state(state_file, state)
        print(f"[{name}] state updated: last_consumed={newest_key}")
    return 0


def main():
    print(f"[watchdog-tick] {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    client = MCPClient()
    try:
        # tools/list sanity check
        resp = client.call("tools/list", {})
        if resp and "result" in resp:
            tool_names = [t["name"] for t in resp["result"].get("tools", [])]
            if "watchdog_tick" not in tool_names:
                print(f"ERROR: watchdog_tick not found in tools list: {tool_names}")
                return 1
            print(f"[ok] watchdog_tick found ({len(tool_names)} tools)")
        else:
            print("WARN: tools/list failed, proceeding anyway")

        # Round-robin: tick EVERY project that has an unconsumed prompt or needs healing.
        # watchdog_tick is idempotent: no unconsumed prompt + healthy tasks => waiting (no-op).
        failures = 0
        for proj in PROJECTS:
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
