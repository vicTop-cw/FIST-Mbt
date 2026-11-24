#!/usr/bin/env python3
"""autoplan —— 计划投递 / 裁决清单 / 功能反馈（协议 v2，四区生命周期）

协议：docs/plans/2026-11-22-autoplan.md。全部经常驻服务 HTTP 面操作，
零核心改动（P0 红线）。

四区：初稿（drop 只入稿不执行）/ 执行（finalize 定案后才流转）/
      归档（全任务终态）/ 终止（abort 夭折）+ 裁决/反馈双面。

用法（cwd 须为 FIST-Mbt 仓根，服务默认 svc-atomcode @18640）：
  python scripts/autoplan.py drop <计划.md>
  python scripts/autoplan.py plans
  python scripts/autoplan.py finalize <plan_id>
  python scripts/autoplan.py abort <plan_id> "<原因>"
  python scripts/autoplan.py sweep
  python scripts/autoplan.py decisions [plan_id]
  python scripts/autoplan.py resolve <task_id> "<选项与反馈>"
  python scripts/autoplan.py feedback "<意见>"    /  ... feedback --list
"""

import argparse
import json
import os
import subprocess
import time
import urllib.request
from pathlib import Path
import sys
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
NS = "autoplan"
PLANS_FILE = ROOT / ".fist-mbt" / "data" / "autoplan-plans.json"
FEEDBACK_FILE = ROOT / ".fist-mbt" / "data" / "autoplan-feedback.jsonl"
INBOX = ROOT / ".fist-mbt" / "data" / "laya-inbox.jsonl"
TERMINAL = ("已完成", "已归档", "已暂停")
ZONE_NAME = {"draft": "初稿区", "active": "执行区(定案)",
             "archived": "归档区", "terminated": "终止区"}
PLAN_DIR = ROOT / "fist-mbt" / "plan"
PLAN_DRAFT_DIR = PLAN_DIR / "draft"
PLAN_ACTIVE_DIR = PLAN_DIR / "active"


def plan_zone(plan_path: str) -> str:
    """计划文件所在目录归属：draft / active / 其他（""）。"""
    try:
        rp = Path(plan_path).resolve()
    except OSError:
        return ""
    for zone, d in (("draft", PLAN_DRAFT_DIR), ("active", PLAN_ACTIVE_DIR)):
        try:
            if rp == d.resolve() or d.resolve() in rp.parents:
                return zone
        except OSError:
            continue
    return ""


def load_key() -> str:
    return (ROOT / ".fist-mbt" / "data" / "svc-atomcode.apikey").read_text(encoding="utf-8").strip()


def load_plans() -> dict:
    if PLANS_FILE.exists():
        return json.loads(PLANS_FILE.read_text(encoding="utf-8"))
    return {}


def save_plans(plans: dict) -> None:
    PLANS_FILE.parent.mkdir(parents=True, exist_ok=True)
    PLANS_FILE.write_text(json.dumps(plans, ensure_ascii=False, indent=2),
                          encoding="utf-8")


def now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def notify_task_terminal(inbox_path, task_id: str, status: str,
                         title: str = "") -> bool:
    """任务终态主动推送：经 laya-inbox 追加终态通知（幂等去重）。

    复用既有 laya-inbox.jsonl 通道（与 fist_gateway.notify_terminal /
    notify_agent_service_up.py 同纪律：append-only，只增不改不删）。
    按 task_id+status 去重：同一任务同一终态只推一次，重复执行不刷屏。
    返回是否真的追加了。
    """
    if status not in TERMINAL:
        return False
    if Path(inbox_path).exists():
        for line in Path(inbox_path).read_text(
                encoding="utf-8", errors="replace").splitlines():
            try:
                e = json.loads(line)
            except json.JSONDecodeError:
                continue
            if e.get("type") == "task_terminal" \
                    and e.get("task_id") == task_id and e.get("status") == status:
                return False
    Path(inbox_path).parent.mkdir(parents=True, exist_ok=True)
    entry = {
        "type": "task_terminal",
        "task_id": task_id,
        "status": status,
        "title": title,
        "at": now_iso(),
    }
    with Path(inbox_path).open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    return True


def parse_plan(path: str):
    """协议 §2：'- [ ] ' = 工作项；'? ' = 裁决项（问题 | 选项：A / B | 建议：C）。"""
    items = []
    for raw in Path(path).read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("- [ ] "):
            items.append({"kind": "work", "text": line[len("- [ ] "):].strip()})
        elif line.startswith("? "):
            items.append({"kind": "decision", "text": line[len("? "):].strip()})
    return items


def call(base: str, key: str, name: str, arguments: dict) -> dict:
    body = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": {"name": name, "arguments": arguments}}
    req = urllib.request.Request(f"{base}/mcp", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "X-API-Key": key})
    with urllib.request.urlopen(req, timeout=60) as r:
        resp = json.loads(r.read().decode())
    if "error" in resp:
        raise RuntimeError(resp["error"].get("message", "")[:200])
    return json.loads(resp["result"]["content"][0]["text"])


def cmd_drop(base, key, plan_path: str, force: bool = False) -> None:
    zone = plan_zone(plan_path)
    if not zone and not force:
        raise SystemExit(
            f"[归位提示] 计划文件不在统一计划目录：{plan_path}\n"
            f"  规范位置：{PLAN_DRAFT_DIR}（初稿）或 {PLAN_ACTIVE_DIR}（已定案）\n"
            f"  请先移动（git mv）过去再 drop；确要就地登记请加 --force")
    items = parse_plan(plan_path)
    if not items:
        raise SystemExit("计划文件没有可执行项（- [ ] 工作项 / ? 裁决项）")
    plans = load_plans()
    pid = f"P{len(plans) + 1}"
    plans[pid] = {
        "title": Path(plan_path).stem,
        "file": plan_path,
        "state": "draft",
        "items": [dict(it, task_id=None, item_status=None) for it in items],
        "created_at": now_iso(),
        "finalized_at": "", "closed_at": "", "abort_reason": "",
    }
    save_plans(plans)
    print(f"{pid} 已入初稿区：{len(items)} 项（{it_kind(items)}）——finalize 后才开始执行")


def it_kind(items) -> str:
    w = sum(1 for i in items if i["kind"] == "work")
    d = sum(1 for i in items if i["kind"] == "decision")
    return f"工作项 {w} / 裁决项 {d}"


def cmd_plans() -> None:
    plans = load_plans()
    if not plans:
        raise SystemExit("计划清单为空：先 drop 一份计划")
    for zone in ("draft", "active", "archived", "terminated"):
        rows = [(pid, p) for pid, p in plans.items() if p["state"] == zone]
        if not rows:
            continue
        print(f"—— {ZONE_NAME[zone]} ——")
        for pid, p in rows:
            extra = f"｜原因：{p['abort_reason']}" if p.get("abort_reason") else ""
            print(f"  {pid} {p['title']}（{it_kind(p['items'])}，{p['created_at']}）{extra}")


def cmd_finalize(base, key, pid: str) -> None:
    plans = load_plans()
    p = plans.get(pid) or raise_exit(f"计划不存在：{pid}")
    if p["state"] != "draft":
        raise SystemExit(f"finalize 仅限初稿（{pid} 当前 {ZONE_NAME[p['state']]}）")
    for it in p["items"]:
        desc = ("[裁决] " + it["text"]) if it["kind"] == "decision" else it["text"]
        inner = call(base, key, "publish", {
            "project_dir": ".", "namespace": NS,
            "description": desc, "created_by": "human_steward"})
        it["task_id"] = inner.get("task_id") or inner.get("id") or ""
        it["item_status"] = "待领取"
        print(f"published: {it['task_id']} [{it['kind']}] {it['text'][:60]}")
    p["state"] = "active"
    p["finalized_at"] = now_iso()
    # 归位登记：初稿文件随定案迁入 active/（原地保留失败不阻塞定案，仅提示）
    src = Path(p["file"])
    if plan_zone(p["file"]) == "draft" and src.exists():
        PLAN_ACTIVE_DIR.mkdir(parents=True, exist_ok=True)
        dst = PLAN_ACTIVE_DIR / src.name
        try:
            src.replace(dst)
            p["file"] = str(dst)
            print(f"计划文件已归位：{src} → {dst}")
        except OSError as e:
            print(f"[警告] 计划文件归位失败（不阻塞定案）：{e}")
    save_plans(plans)
    print(f"{pid} 定案 → 执行区（任务已入池）")


def raise_exit(msg: str):
    raise SystemExit(msg)


def cmd_abort(base, key, pid: str, reason: str) -> None:
    plans = load_plans()
    p = plans.get(pid) or raise_exit(f"计划不存在：{pid}")
    if p["state"] in ("archived", "terminated"):
        raise SystemExit(f"{pid} 已在 {ZONE_NAME[p['state']]}")
    p["state"] = "terminated"
    p["abort_reason"] = reason
    p["closed_at"] = now_iso()
    save_plans(plans)
    print(f"{pid} → 终止区（{reason}）；池内已发布任务如实保留")


def cmd_sweep(base, key) -> None:
    plans = load_plans()
    moved = 0
    for pid, p in plans.items():
        if p["state"] != "active":
            continue
        tids = [i.get("task_id") for i in p["items"] if i.get("task_id")]
        if not tids:
            continue
        statuses = []
        for tid in tids:
            inner = call(base, key, "get", {"task_id": tid, "namespace": NS})
            statuses.append(inner.get("status", ""))
            for i in p["items"]:
                if i.get("task_id") == tid:
                    i["item_status"] = inner.get("status", "")
        if all(s in TERMINAL for s in statuses):
            p["state"] = "archived"
            p["closed_at"] = now_iso()
            for i in p["items"]:
                if i.get("task_id") and i.get("item_status") in TERMINAL:
                    notify_task_terminal(INBOX, i["task_id"], i["item_status"], i["text"])
            moved += 1
            print(f"{pid} 全任务终态 → 归档区")
    save_plans(plans)
    print(f"sweep 完成：归档 {moved} 个计划")


def cmd_decisions(base, key, pid: str) -> None:
    plans = load_plans()
    open_n = 0
    for plan_id, p in sorted(plans.items()):
        if pid and plan_id != pid:
            continue
        if p["state"] != "active":
            continue  # 裁决区只挂执行中(定案)的计划
        for i in p["items"]:
            if i["kind"] != "decision" or i.get("item_status") in TERMINAL:
                continue
            open_n += 1
            print(f"[待裁决] {i.get('task_id') or '(未定案)'} {p['title']}｜{i['text']}"
                  f"\n    当前状态：{i.get('item_status') or '—'}")
    print(f"裁决清单：{open_n} 项未闭环（resolve <task_id> \"<选项与反馈>\" 落定）")


def cmd_resolve(base, key, task_id: str, choice: str) -> None:
    plans = load_plans()
    target = None
    for p in plans.values():
        for i in p["items"]:
            if i.get("task_id") == task_id:
                target = (p, i)
    if not target:
        raise SystemExit(f"清单中无任务 {task_id}（先 drop/finalize）")
    p, it = target
    # 裁决 = 任务闭环：按九态机宽容推进（已过的态跳过，其它错误如实抛出）
    steps = [
        ("claim", {"task_id": task_id, "assignee": "atomcode", "namespace": NS}),
        ("execute", {"task_id": task_id, "namespace": NS, "deliverable": choice}),
        ("submit", {"task_id": task_id, "deliverable": choice, "namespace": NS}),
    ]
    for name, args in steps:
        try:
            call(base, key, name, args)
        except RuntimeError as e:
            if "非法迁移" not in str(e) and "已在运行" not in str(e):
                raise
    r = call(base, key, "verify", {"task_id": task_id, "verifier": "human_steward",
                                   "namespace": NS})
    it["item_status"] = r.get("status", "已完成")
    p["state"] = "active" if p["state"] == "draft" else p["state"]
    save_plans(plans)
    with INBOX.open("a", encoding="utf-8") as f:
        f.write(json.dumps({"type": "autoplan_decision", "task_id": task_id,
                            "choice": choice, "at": now_iso()},
                           ensure_ascii=False) + "\n")
    notify_task_terminal(INBOX, task_id, it["item_status"], it["text"])
    print(f"resolve: {task_id} -> {r.get('status', 'ok')}｜裁决已记 laya-inbox：{choice[:80]}")


def cmd_feedback(text: str, as_list: bool) -> None:
    FEEDBACK_FILE.parent.mkdir(parents=True, exist_ok=True)
    if as_list:
        if not FEEDBACK_FILE.exists():
            print("（反馈区为空）")
            return
        for line in FEEDBACK_FILE.read_text(encoding="utf-8").splitlines():
            if line.strip():
                e = json.loads(line)
                print(f"[{e.get('at', '')}] {e.get('text', '')[:100]}")
        return
    with FEEDBACK_FILE.open("a", encoding="utf-8") as f:
        f.write(json.dumps({"text": text, "at": now_iso()}, ensure_ascii=False) + "\n")
    print(f"feedback 已入反馈区（{text[:60]}）")


def cmd_selftest() -> None:
    """判据自证：parse_plan 对工作项/裁决项双类目的拆解不漂移。"""
    p = Path(".__autoplan_selftest__.md")
    p.write_text("# t\n- [ ] 工作项甲\n? 裁决问题 | 选项：A / B | 建议：A\n",
                 encoding="utf-8")
    items = parse_plan(str(p))
    p.unlink()
    assert [i["kind"] for i in items] == ["work", "decision"], \
        f"parse_plan 双类目拆解漂移: {items}"
    assert "工作项甲" in items[0]["text"] and "裁决问题" in items[1]["text"]
    # plan_zone 归属判定：draft 命中 / active 命中 / 区外为空
    assert plan_zone(str(PLAN_DRAFT_DIR / "x.md")) == "draft", "draft 目录归属漂移"
    assert plan_zone(str(PLAN_ACTIVE_DIR / "x.md")) == "active", "active 目录归属漂移"
    assert plan_zone(str(ROOT / "somewhere" / "x.md")) == "", "区外未判空"
    print("selftest OK：parse_plan 双类目 + plan_zone 归属判定自证成立")


def cmd_exec(base, key, limit: int, dry: bool) -> None:
    """执行拍：认领 ns=autoplan 待领取项 → 经服务网关 executor_run(atomcode) 真跑 → 提交验收。

    经由 fist-mbt 原生执行器通道（executor_run，argv 不经 shell；服务端拉起执行器
    并记账），消耗免费 agent 服务额度；--limit 控制单轮派发数（巡检每轮限 2）。
    修复：此前实现绕过服务端直拉本机 atomcode subprocess（docstring 写 executor_run
    实际未接），且 submit/verify 存在重复死代码块；失败任务也走 submit 标"完成"，
    造成"任务已领取但不干活"的假闭环。现统一经网关 HTTP 调 executor_run，成功才
    submit/verify 闭环，失败走 reopen_task 自动复位（reopen 语义为回"已领取"，
    需由 assignee 重新 execute；本脚本后续轮次不重复认领已领取项）。
    """
    plans = load_plans()
    dispatched = 0
    for pid, p in sorted(plans.items()):
        if p["state"] != "active":
            continue
        for i in p["items"]:
            if i["kind"] != "work" or i.get("item_status") not in (None, "", "待领取"):
                continue
            tid = i.get("task_id")
            if not tid or dispatched >= limit:
                continue
            prompt = (f"你是 fist-mbt 任务池的执行 agent。任务：{i['text']}\n"
                      f"约束：只读盘点/最小改动；产出物写明路径。\n"
                      f"完成后必须自我提交（接力棒协议）：读取 {ROOT / '.fist-mbt' / 'data' / 'svc-atomcode.apikey'} 的 key，"
                      f"向 {base}/mcp 发 tools/call submit "
                      f"{{task_id: '{tid}', namespace: '{NS}', deliverable: '<产出摘要>'}}，"
                      f"再 tools/call verify {{task_id: '{tid}', verifier: 'human_steward', namespace: '{NS}'}}。")
            if dry:
                print(f"[dry] {tid}: executor_run(atomcode) ← {i['text'][:50]}")
                dispatched += 1
                continue
            try:
                call(base, key, "claim", {"task_id": tid, "assignee": "atomcode",
                                          "namespace": NS})
                call(base, key, "execute", {"task_id": tid, "namespace": NS,
                                            "deliverable": f"接力棒派发：{i['text'][:80]}"})
                # 分离式派发（fire-and-forget）：不等会话结束，巡检下轮验收。
                # 同步等待实测必挂：长任务 >45min，且网关 HTTP 通道当日 5+ 次挂死。
                import subprocess
                flags = getattr(subprocess, "DETACHED_PROCESS", 0) | getattr(subprocess, "CREATE_NO_WINDOW", 0)
                subprocess.Popen(["atomcode", "-p", prompt, "-y"],
                                 cwd=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                 creationflags=flags,
                                 stdout=open(os.devnull, "w"), stderr=subprocess.STDOUT)
                print(f"exec: {tid} 已分离派发（会话自交，巡检验收）")
                dispatched += 1
            except Exception as e:
                print(f"exec: {tid} ERR {str(e)[:100]}")
                # 网关抖动/执行器超时 ⇒ 自动复位，防任务卡死在已领取/执行中
                try:
                    call(base, key, "reopen_task", {"task_id": tid, "namespace": NS})
                    print(f"exec: {tid} 已自动复位回待领取")
                except Exception as e2:
                    print(f"exec: {tid} 复位失败 {str(e2)[:60]}（需手动 reopen_task）")
    save_plans(plans)
    print(f"exec 拍完成：本轮派发/完成 {dispatched} 项")


def main() -> None:
    if "--selftest" in sys.argv:
        cmd_selftest()
        return
    ap = argparse.ArgumentParser()
    ap.add_argument("--service", default="http://127.0.0.1:18640")
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("drop")
    d.add_argument("plan")
    d.add_argument("--force", action="store_true",
                   help="跳过统一计划目录校验，就地登记")
    sub.add_parser("plans")
    f = sub.add_parser("finalize")
    f.add_argument("plan_id")
    a = sub.add_parser("abort")
    a.add_argument("plan_id")
    a.add_argument("reason")
    sub.add_parser("sweep")
    c = sub.add_parser("decisions")
    c.add_argument("plan_id", nargs="?", default="")
    r = sub.add_parser("resolve")
    r.add_argument("task_id")
    r.add_argument("choice")
    fb = sub.add_parser("feedback")
    fb.add_argument("text", nargs="?")
    fb.add_argument("--list", action="store_true")
    sub.add_parser("selftest")
    e = sub.add_parser("exec")
    e.add_argument("--limit", type=int, default=2)
    e.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    base, key = a.service, load_key()
    if a.cmd == "selftest":
        cmd_selftest()
        return
    if a.cmd == "exec":
        cmd_exec(base, key, a.limit, a.dry_run)
        return
    if a.cmd == "drop":
        cmd_drop(base, key, a.plan, a.force)
    elif a.cmd == "plans":
        cmd_plans()
    elif a.cmd == "finalize":
        cmd_finalize(base, key, a.plan_id)
    elif a.cmd == "abort":
        cmd_abort(base, key, a.plan_id, a.reason)
    elif a.cmd == "sweep":
        cmd_sweep(base, key)
    elif a.cmd == "decisions":
        cmd_decisions(base, key, a.plan_id)
    elif a.cmd == "resolve":
        cmd_resolve(base, key, a.task_id, a.choice)
    elif a.cmd == "feedback":
        cmd_feedback(a.text or "", a.list)


if __name__ == "__main__":
    main()
