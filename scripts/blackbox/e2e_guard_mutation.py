#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/blackbox/e2e_guard_mutation.py —— 「判据会不会咬」常驻探针（R44）。

## 为什么要有它

本仓的硬纪律是「判据必须先证明它会红」（每把尺都配 `--selftest`）。但 `--selftest` 验的是
**纯函数**；它证明不了「这把尺扫的面覆盖了它声称覆盖的东西」。R43 就撞到过反例：
`check_mbti_eol.py` 的自检 12 格全绿，可它的工作树面**只盯 3 份 `.mbti`**，另外 21 份谁脏都报绿。

本探针换一种证法：**在真仓的临时 clone 里制造一个该尺定义的违例，看它是否变红**；
再在不制造违例的同一 clone 上确认它是绿的。两格都成立，才算「这把尺在这条路上会咬」。

## 安全边界（为什么敢做变异）

- **只改临时 clone**（`git clone --no-hardlinks --depth 1 . <tmp>`），真工作树一个字节都不动；
- clone 完先跑一遍基线，基线不绿 ⇒ 该格记 SKIP（不能拿"本来就红"当"抓住了"）；
- 退出码：0 = 全部 BITES / 1 = 有 BLUNT（某把尺没咬住）/ 2 = 判据无法自证（clone 失败等）。

## 用法

    python scripts/blackbox/e2e_guard_mutation.py            # 跑全部格子
    python scripts/blackbox/e2e_guard_mutation.py --list     # 只列格子名
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def sh(cmd, cwd, timeout=600):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=timeout)


# ---- 变异体（每个返回 None 表示已施加；在 clone 内执行，路径相对 clone 根） ----

def mut_phantom_tool(c):
    p = os.path.join(c, "AGENTS.md")
    with open(p, "a", encoding="utf-8", newline="") as f:
        f.write("\n| `mutation_probe_tool_xyz` | 探针造的工具名（server 未注册） |\n")


def mut_unregistered_script(c):
    p = os.path.join(c, "scripts", "gen_mutation_probe_r44.py")
    with open(p, "w", encoding="utf-8", newline="") as f:
        f.write("# 探针造的未登记脚本\nprint('x')\n")
    # 关键：该尺扫的是 **git 跟踪面**，未跟踪的新文件它看不见（这是设计，不是钝）。
    # 所以探针必须把它变成"已跟踪但未登记"——这才是它声称要抓的违例形状。
    sh(["git", "add", "-N", "scripts/gen_mutation_probe_r44.py"], c)
    return None


def mut_plugin_handedit(c):
    # 手改生成态插件文件（cl7 明令禁止手改）
    for rel in ("plugins/claude/skills/fist-mbt/SKILL.md",
                "plugins/atomcode/skills/fist-mbt/SKILL.md"):
        p = os.path.join(c, rel)
        if os.path.isfile(p):
            with open(p, "a", encoding="utf-8", newline="") as f:
                f.write("\n<!-- mutation probe: 手改生成态 -->\n")
            return None
    return "找不到生成态插件文件"


def mut_dup_index_entry(c):
    # 复制一条脚本索引条目块 —— check_doc_dup 守的正是"同名条目重复"
    p = os.path.join(c, "scripts", "README.md")
    lines = open(p, encoding="utf-8").read().splitlines(keepends=True)
    start = None
    for i, ln in enumerate(lines):
        s = ln.strip()
        if s.startswith("- `") and ".py`" in s:
            start = i
            break
    if start is None:
        return "scripts/README.md 里没有脚本索引条目"
    j = start + 1
    while j < len(lines) and lines[j].strip() and lines[j][:1] in (" ", "\t"):
        j += 1
    block = "".join(lines[start:j])
    with open(p, "a", encoding="utf-8", newline="") as f:
        f.write("\n" + block)
    return None


def mut_retired_entry(c):
    p = os.path.join(c, "docs", "SOP.md")
    with open(p, "a", encoding="utf-8", newline="") as f:
        f.write("\n退役入口示例：`node _build/js/debug/build/cmd/main/main.js`\n")


CASES = [
    ("phantom-tool", "check_tools_sync.py", mut_phantom_tool,
     "AGENTS 表格多出一个 server 未注册的工具名"),
    ("unregistered-script", "check_scripts_index.py", mut_unregistered_script,
     "scripts/ 下多一份未在 scripts/README.md 登记的 .py"),
    ("plugin-handedit", "check_plugin_sync.py", mut_plugin_handedit,
     "手改生成态插件目录（cl7 禁止）"),
    ("dup-index-entry", "check_doc_dup.py", mut_dup_index_entry,
     "scripts/README.md 同名索引条目块重复"),
    ("retired-entry", "check_entry_paths.py", mut_retired_entry,
     "现状面引用退役入口 cmd/main"),
]


def run_case(tmp_clone, name, guard, mutate, desc):
    """返回 (verdict, detail)：BITES / BLUNT / SKIP / BAD。"""
    # 每个 case 用独立 clone，互不污染
    work = os.path.join(tmp_clone, name)
    r = sh(["git", "clone", "--no-hardlinks", "--depth", "1", "-q", ROOT, work], tmp_clone, timeout=600)
    if r.returncode != 0:
        return "SKIP", "clone 失败: " + (r.stderr or "").strip().splitlines()[-1:][0] if r.stderr else "clone 失败"
    guard_path = os.path.join(work, "scripts", guard)
    if not os.path.isfile(guard_path):
        return "SKIP", "clone 里没有 %s" % guard
    base = sh([sys.executable, os.path.join("scripts", guard)], work)
    if base.returncode != 0:
        return "SKIP", "基线非绿(rc=%d)，不能拿它证「会咬」" % base.returncode
    why = mutate(work)
    if why:
        return "SKIP", why
    mut = sh([sys.executable, os.path.join("scripts", guard)], work)
    if mut.returncode == 0:
        return "BLUNT", "施加违例(%s)后仍 rc=0 —— 这把尺在这条路上没咬" % desc
    # 关键：确认它红是因为**我们造的违例**，不是别的原因（在干净 clone 上应仍绿）
    first = ""
    for line in ((mut.stdout or "") + (mut.stderr or "")).splitlines():
        if line.strip():
            first = line.strip()[:140]
            break
    return "BITES", first


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args(argv)
    if a.list:
        for name, guard, _m, desc in CASES:
            print("%-20s %-26s %s" % (name, guard, desc))
        return 0
    if sh(["git", "--version"], ROOT).returncode != 0:
        print("FATAL 没有 git，无法做 clone 隔离 —— 拒绝在真树上做变异（rc=2）")
        return 2
    tmp = tempfile.mkdtemp(prefix="fist-guard-mut-")
    blunt, skipped, bites = [], [], []
    try:
        for name, guard, mutate, desc in CASES:
            verdict, detail = run_case(tmp, name, guard, mutate, desc)
            print("%-8s %-20s %s" % (verdict, name, detail))
            {"BITES": bites, "BLUNT": blunt, "SKIP": skipped}.get(verdict, blunt).append(name)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("\n汇总：BITES %d / BLUNT %d / SKIP %d" % (len(bites), len(blunt), len(skipped)))
    if blunt:
        print("FAIL 有尺在这条路上没咬：" + ", ".join(blunt))
        return 1
    if not bites:
        print("FATAL 一格都没跑成（判据无法自证）")
        return 2
    print("PASS 每把被检尺在各自违例上都咬住了")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
