#!/usr/bin/env python3
"""notify_agent_service_up —— mcp-watcher 触发钩子：fist-agent 服务上线 → 告知 laya。

由 mcp-watcher 的 command 动作拉起（监控 model-router-default.json 的 modify 事件）。
语义：把路由配置里**尚未登记进收件箱**的 agent_services 条目追加到
`.fist-mbt/data/laya-inbox.jsonl`（append-only，与 task_events 同纪律：只增不改不删），
laya 侧读收件箱即知「有哪些免费高优模型端点可用」。

用法：python scripts/notify_agent_service_up.py [router_config_json]
缺省读 .fist-mbt/data/model-router-default.json（cwd 须为 FIST-Mbt 仓根）。
"""

import json
import sys
import time
from pathlib import Path
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
INBOX = ROOT / ".fist-mbt" / "data" / "laya-inbox.jsonl"


def main() -> None:
    if "--selftest" in sys.argv:
        selftest()
        return
    cfg_path = Path(sys.argv[1]) if len(sys.argv) > 1 else (
        ROOT / ".fist-mbt" / "data" / "model-router-default.json")
    process(cfg_path, INBOX)


def process(cfg_path, inbox_path) -> None:
    """读路由配置 → 未登记条目追加进收件箱（幂等去重）。"""
    try:
        cfg = json.loads(Path(cfg_path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        print(f"读路由配置失败（静默退出，watcher 不重试）: {e}")
        return
    services = cfg.get("agent_services") or []
    if not isinstance(services, list):
        return
    # 幂等去重：已登记的 service_id 不重复通知
    seen = set()
    if Path(inbox_path).exists():
        for line in Path(inbox_path).read_text(encoding="utf-8").splitlines():
            try:
                seen.add(json.loads(line).get("service_id"))
            except json.JSONDecodeError:
                continue
    Path(inbox_path).parent.mkdir(parents=True, exist_ok=True)
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    appended = 0
    with Path(inbox_path).open("a", encoding="utf-8") as f:
        for s in services:
            if not isinstance(s, dict):
                continue
            sid = s.get("service_id", "")
            if not sid or sid in seen:
                continue
            seen.add(sid)  # 单轮内也去重：同一配置里的重复条目只通知一次
            f.write(json.dumps({
                "type": "agent_service_up",
                "service_id": sid,
                "endpoint": s.get("endpoint", ""),
                "capabilities": s.get("capabilities", []),
                "note": "fist-agent 常驻服务上线，免费高优，可加入自动路由",
                "at": now,
            }, ensure_ascii=False) + "\n")
            appended += 1
    print(f"notify_agent_service_up: 新增 {appended} 条（收件箱 {Path(inbox_path).name}）")


def selftest() -> None:
    """判据自证：拆解/追加/幂等去重三格（合成配置 + 临时收件箱，零网络）。"""
    import tempfile
    td = Path(tempfile.mkdtemp())
    cfg = td / "cfg.json"
    cfg.write_text(json.dumps({"agent_services": [
        {"service_id": "svc-x", "endpoint": "http://127.0.0.1:1/mcp"},
        {"service_id": "svc-x", "endpoint": "http://127.0.0.1:1/mcp"},
    ]}), encoding="utf-8")
    inbox = td / "inbox.jsonl"
    process(str(cfg), inbox)
    first = len(inbox.read_text(encoding="utf-8").splitlines())
    process(str(cfg), inbox)
    second = len(inbox.read_text(encoding="utf-8").splitlines())
    assert first == 1 and second == 1, f"幂等去重失效: 首跑 {first} 行 / 二跑 {second} 行"
    print("selftest OK：追加 1 条 + 二次 0 新增（幂等去重自证成立）")


if __name__ == "__main__":
    main()
