#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_fist_list_tools_sync.py — CLI 入口 `fist.py list-tools` 计数 ↔ 真源对表（2026-10-25 新增）。

**为什么需要它（实测缺口）**
工具注册真源已收口到 `scripts/_tool_registry.real_tools()`（读 `src/server/*.mbt`，
`instrumented_tool` + 链式 `.tool()` 两种形态的并集 = **170**）。
但 `scripts/fist.py` 的 `list-tools` 曾**自写一份正则**、只扫 `src/server/server.mbt` 一个文件，
且名字类 `[a-z_]+` 不认点号 ⇒ 实测只报 **152**，漏 18 个：

    · supervisor_*  ×8   （supervisor_tools.mbt）
    · mcpcf.*       ×7   （mcpcf_embed.mbt，名字带 `.` ⇒ `[a-z_]+` 不匹配）
    · hat_run / hat_debate / hat_merge ×3（hat_hexa_tools.mbt）

**这个缺口的危害形状特别隐蔽**：六支文档/插件守卫全部走 `real_tools()`（读 170）⇒ **永远绿**；
只有人手动敲 `fist.py list-tools` 才看到 152。**判据绿、入口少** ⇒ 属于判例-16 家族
（判据面/实现面不一致），本仓已为同族返工过（`_tool_registry.py` 注释记录的 5 消费者之乱）。

**判据**（三条，任一不满足即红）：
  C1 `fist.py list-tools` 的 **stdout 行数** == `len(real_tools())`
     —— stdout 契约是「一行一个工具名，纯清单」，汇总行走 stderr。
        旧实现把汇总行打在 stdout ⇒ `wc -l` = 工具数+2，是与真源对表时的经典陷阱（判例-43 同族）。
  C2 stdout 的**集合** == `set(real_tools())`（不只比数量——数量对而名字错同样是缺陷）；
  C3 `fist.py list-tools` 的 stderr 汇总行明确写出 `共 N 个工具` 且 N == 真源
     —— 人类读数面也要对得上，否则「机器对、人读错」。

**rc**：0 = 三面一致 / 1 = 有违例（逐条点名）/ 2 = 判据无法自证（真源读不到 / 命令跑不起来）/
       4 = 尺子自己坏了（`--selftest` 未过，不冒用 1）。

**--selftest**（含判例-29/30 要求的**变异对照**）：
  格 1 干净现状不误红
  格 2 **变异①**：把 `_tool_registry.real_tools()` 换成一个「只扫 server.mbt」的旧口径 ⇒ 必须红
        （证明本尺量的确实是"入口 vs 真源"的分叉，不是恒绿装饰）
  格 3 **变异②**：真源正常但 CLI 输出被截断一名 ⇒ C2 集合格必须红（不只 C1 数量格红）
  格 4 **变异③**：stdout 里混入汇总行（旧形状）⇒ C1 必须红（锁住"stdout 必须纯清单"这个契约）
  格 5 空扫描自拒：真源为空 ⇒ 自拒，不报绿

用法：
    python scripts/check_fist_list_tools_sync.py              # 0/1/2/4
    python scripts/check_fist_list_tools_sync.py --selftest   # 0=全过 / 4=有格未过
"""
import os
import subprocess
import sys
from pathlib import Path

# BUG-58：Windows GBK 控制台下中文结论会 UnicodeEncodeError ⇒ 拿到 traceback 而不是 verdict。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

SCRIPTS = Path(__file__).resolve().parent
ROOT = SCRIPTS.parent
FIST = SCRIPTS / "fist.py"
sys.path.insert(0, str(SCRIPTS))


def _registry():
    """取真源模块与 real_tools()。import 失败 ⇒ 判据无法自证（rc=2），不报绿。"""
    try:
        import _tool_registry as reg
    except ImportError as e:
        print(f"FATAL 取不到真源模块 _tool_registry（{e}）⇒ 判据无法自证")
        return None
    return reg


def run_list_tools(timeout=180):
    """跑 `fist.py list-tools`，返回 (names_list, stderr_text) 或 None（跑不起来）。"""
    env = dict(os.environ)
    env.setdefault("PYTHONIOENCODING", "utf-8")
    try:
        p = subprocess.run(
            [sys.executable, str(FIST), "list-tools"],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            cwd=str(ROOT), timeout=timeout, env=env,
        )
    except (OSError, subprocess.SubprocessError) as e:
        print(f"FATAL 跑不起 fist.py list-tools（{e}）⇒ 判据无法自证")
        return None
    names = [ln.strip() for ln in (p.stdout or "").splitlines() if ln.strip()]
    return names, (p.stderr or "")


def judge(names, stderr_text, truth):
    """三条判据。抽成纯函数，便于变异对照直接喂合成输入（不 spawn、不 sleep）。"""
    problems = []
    truth_set = set(truth)

    # C1 行数 == 真源数（stdout 必须纯清单）
    if len(names) != len(truth_set):
        problems.append(
            f"C1 `fist.py list-tools` stdout {len(names)} 行 != 真源 {len(truth_set)} 个工具"
            + ("（stdout 混入非清单行？汇总行必须走 stderr）" if len(names) > len(truth_set) else ""))

    # C2 集合相等（不只比数量）
    got, want = set(names), truth_set
    missing = sorted(want - got)
    extra = sorted(got - want)
    if missing:
        problems.append(f"C2 真源有 / list-tools 缺 {len(missing)} 个: " + ", ".join(missing[:20])
                        + (" …" if len(missing) > 20 else ""))
    if extra:
        problems.append(f"C2 list-tools 有 / 真源无 {len(extra)} 个（幽灵）: " + ", ".join(extra[:20])
                        + (" …" if len(extra) > 20 else ""))

    # C3 stderr 汇总行与真源一致（人类读数面）
    import re
    m = re.search(r"共\s*(\d+)\s*个工具", stderr_text or "")
    if not m:
        problems.append("C3 stderr 没有『共 N 个工具』汇总行 ⇒ 人类读数面缺失")
    elif int(m.group(1)) != len(truth_set):
        problems.append(f"C3 stderr 汇总写 {m.group(1)} 个 != 真源 {len(truth_set)} 个")
    return problems


def run_all():
    reg = _registry()
    if reg is None:
        return 2
    truth = reg.real_tools()
    # 反幻影：真源都读不出来就别判
    if len(truth) <= getattr(reg, "MIN_EXPECTED", 100):
        print(f"FATAL 真源只解析到 {len(truth)} 个工具 ⇒ 扫描面失效，判据无法自证")
        return 2
    r = run_list_tools()
    if r is None:
        return 2
    names, err = r
    problems = judge(names, err, truth)
    for p in problems:
        print("  - " + p)
    if problems:
        print(f"FAIL CLI list-tools 与真源不一致：真源 {len(truth)} 个 / list-tools 报 {len(names)} 行"
              f"（差 {len(names) - len(truth)}）")
        return 1
    print(f"PASS CLI list-tools ↔ 真源一致：{len(truth)} 个工具，stdout 纯清单 {len(names)} 行，"
          f"集合逐名相等，stderr 汇总行 = {len(truth)}")
    return 0


def selftest():
    """自证：干净不误红 + 三个变异必红 + 空扫描自拒（判例-29/30：变异必须落在代码面）。"""
    reg = _registry()
    if reg is None:
        return 4
    truth = reg.real_tools()
    if len(truth) <= getattr(reg, "MIN_EXPECTED", 100):
        print(f"SELFTEST FAIL 真源只解析到 {len(truth)} 个工具 ⇒ 无法自证")
        return 4

    executed, fails = [], []

    def cell(label, problems, want_red):
        is_red = bool(problems)
        executed.append(f"{label}(red={is_red})")
        if is_red != want_red:
            fails.append(f"{label}: want_red={want_red} got_red={is_red} :: {problems[:2]}")

    good_err = f"共 {len(truth)} 个工具"

    # 格 1：干净现状不误红（用真源自身当 CLI 输出）
    cell("S1-干净不误红", judge(list(truth), good_err, truth), False)

    # 格 2：变异① —— 真源被换成「只扫 server.mbt」的旧口径 ⇒ 必须红
    #       这是**判例-16 的核心**：证明本尺量的就是"入口 vs 真源"的分叉。
    #       用真源里确实来自别的文件的工具做旧口径（不猜：直接取一个链式注册的 mcpcf.*）。
    old_style = [t for t in truth if not t.startswith(("mcpcf.", "supervisor_", "hat_"))]
    cell("S2-变异①旧口径真源必红", judge(list(truth), good_err, old_style), True)

    # 格 3：变异② —— CLI 截断一名 ⇒ C2 集合格必须红（证明不只比数量）
    cell("S3-变异②CLI缺一名必红", judge(list(truth)[:-1], f"共 {len(truth) - 1} 个工具", truth), True)

    # 格 4：变异③ —— stdout 混入汇总行（旧形状）⇒ C1 必须红
    dirty = list(truth) + [good_err]
    cell("S4-变异③stdout混汇总行必红", judge(dirty, good_err, truth), True)

    # 格 5：空扫描自拒
    cell("S5-空真源必红", judge([], "", []), True)

    print("SELFTEST %s (grid: %s)" % ("OK" if not fails else "FAIL", " / ".join(executed)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 4


if __name__ == "__main__":
    if "--selftest" in sys.argv[1:]:
        sys.exit(selftest())
    sys.exit(run_all())
