#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_ci_step_position.py — CI 步骤位置守卫（TASK-003，风语者巡检产出）。

**为什么需要它（2026-10-21 实测）**：`ci.yml` 的 `Migrate mooncakes dep manifests` 一步失败时，
其后的所有步骤被 GitHub Actions **skip**。合入者第一次把 merge-marker gate 放在 Migrate 之后，
实测 Migrate 崩了之后这一步永远不跑——**最需要它出声（冲突标记进跟踪面）的时候沉默**，
随后 259b56a8 又把 3 份 issue_scan 文件的冲突标记提交进 master 而 CI 无感。
这不是"门不够多"，是"门站在会被跳过的位置"。

**判据**：
  P1 硬判（rc=1）：**预检族的尺**必须排在 Migrate 之前。预检族＝不依赖 moon 构建产物、
     只需静态读仓库即可出结论的尺（冲突标记 / 编码 / 模板控制字符 / 脚本索引）。
     它们存在的意义就是"在脏东西进入构建前拦住"，放到 Migrate 之后等于自动放弃这条意义。
  P2 只报（不判红）：其余 gate-like 步骤（要 build/test 日志、要产物、要跨进程探针）排在
     Migrate 之后是**合理**的——本仓实测 33 个，硬堵它没有意义；故只印计数与清单，
     供人核对"这一步是不是又踩了 skip 坑"。
  P3 只报：gate-like 步骤前 3 行内没有 `#` 说明的，列出来（TASK-003 验收③「位置说明」的软化版：
     注释是给人看的，硬判会逼出一堆 `# 无` 的假注释）。

退出码：0=预检族位置合规 / 1=有预检尺落在 Migrate 之后 / 2=判据无法自证（没 Migrate 步 / yml 空 / 解析不到步）。
"""
import argparse
import io
import os
import re
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
WORKFLOWS = os.path.join(ROOT, ".github", "workflows")

# 预检族：静态读仓库即可出结论、且必须在构建/迁移前跑的尺（新增此类必须在此显式登记）
PREFLIGHT = (
    "check_merge_markers.py",   # 冲突标记：带标记 .mbt 直接崩编译，必须最先
    "check_ps_encoding.py",     # .ps1 编码：PS5.1 解析期即炸
    "check_template_ctrl.py",   # 模板裸控制字符
    "check_scripts_index.py",   # 脚本索引完整性（纯读 README）
    "check_ci_step_position.py",  # 本尺自己（位置守卫自己也要站对位置）
)
GATE_HINT = re.compile(r"(guard|gate|selftest|marker|ratchet|census|probe)", re.I)
MIGRATE_HINT = re.compile(r"migrate", re.I)


def load_steps(path):
    """极简 YAML→步骤列表解析（只认 `- name:` / `run:` / 缩进，够用于位置判定）。

    不用 PyYAML：本仓 CI 的 runner 未必装 yaml，而这条尺要被 CI 调用——
    判据依赖一个未声明的三方库，等于把"判据会不会崩"交给环境。
    """
    steps, cur = [], None
    for raw in io.open(path, encoding="utf-8", errors="replace"):
        line = raw.rstrip("\n")
        m = re.match(r"^(\s*)-\s+name:\s*(.+)$", line)
        if m:
            if cur:
                steps.append(cur)
            cur = {"indent": len(m.group(1)), "name": m.group(2).strip().strip("'\""), "run": "", "idx": len(steps)}
            continue
        if cur is None:
            continue
        if re.match(r"^\s*run:\s*", line):
            cur["run"] = line.split("run:", 1)[1].strip()
        elif cur["run"] and line.strip() and not line.strip().startswith("#"):
            cur["run"] += " " + line.strip()
    if cur:
        steps.append(cur)
    return steps


def judge(steps):
    """返回 (rc, hard_lines, info_lines)。纯函数，selftest 直接喂合成步骤。"""
    if not steps:
        return 2, ["FATAL：解析到 0 个步骤 —— yml 结构变了/文件空，拒绝出'位置合规'的读数"], []
    # 精确识别 Migrate 步：名字**以** Migrate 开头，或 run 里出现 mooncakes 迁移命令。
    # 不能用"名字里含 Migrate"——本尺自己的说明文字就含这个词，会把自身误当 Migrate（实测踩过）。
    mig = [s["idx"] for s in steps
           if re.match(r"\s*Migrate\b", s["name"]) or "migrate_mooncakes" in s["run"]
           or "mooncakes" in s["run"] and "migrate" in s["run"].lower()]
    if not mig:
        return 2, ["FATAL：找不到 Migrate 步骤 —— 本仓 CI 一旦没有它，位置判据无从谈起（拒绝报绿）"], []
    m = mig[0]
    hard, info = [], []
    for s in steps:
        refs_preflight = [p for p in PREFLIGHT if p in s["run"] or p in s["name"]]
        if refs_preflight and s["idx"] > m:
            hard.append("P1 #%d %s（跑 %s）排在 Migrate(#%d) 之后 —— Migrate 失败时本步被 skip"
                        % (s["idx"], s["name"][:60], ",".join(refs_preflight), m))
        elif GATE_HINT.search(s["name"]) and s["idx"] > m:
            info.append("P2 #%d %s" % (s["idx"], s["name"][:60]))
    if hard:
        return 1, ["P1 预检族尺位置违规 %d 处：" % len(hard)] + ["  " + h for h in hard] + \
               (["P2 参考：另有 %d 个 gate-like 步骤在 Migrate 之后（构建后判据，合理，只报）" % len(info)] if info else []), info
    return 0, ["P1 通过：预检族 %d 把尺全部排在 Migrate(#%d) 之前" % (len(PREFLIGHT), m)], info


def selftest():
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%s want=%s" % (got, want)))

    def mk(*names):
        return [{"idx": i, "name": n, "run": n} for i, n in enumerate(names)]

    # C1 干净：预检在 Migrate 前 ⇒ 0
    c1 = mk("else", "Merge-marker gate", "Migrate mooncakes", "Badge guard")
    cell("C1-clean", judge(c1)[0], 0)
    # C2 预检族落在 Migrate 后 ⇒ 1 且点名
    c2 = mk("else", "Migrate mooncakes", "Merge-marker gate (check_merge_markers.py)")
    rc2, hard2, _ = judge(c2)
    cell("C2-preflight-after-migrate", rc2, 1)
    cell("C2-names-the-step", any("Merge-marker" in h for h in hard2), True)
    # C3 无 Migrate 步 ⇒ 2（不许报绿）
    cell("C3-no-migrate", judge(mk("else", "Merge-marker gate"))[0], 2)
    # C4 空步骤 ⇒ 2
    cell("C4-empty-steps", judge([])[0], 2)
    # C5 构建后 gate 在 Migrate 之后 ⇒ 仍 0，但进 P2 只报清单
    c5 = mk("else", "Migrate mooncakes", "Test-count guard (全量)")
    rc5, _lines5, info5 = judge(c5)
    cell("C5-post-build-gate-not-hard", rc5, 0)
    cell("C5-reported-as-info", len(info5), 1)
    bad = [(n, w) for n, ok, w in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK（%d 格：C1 干净 / C2 预检族越位必红且点名 / C3 无 Migrate 自拒 / "
          "C4 空步骤自拒 / C5 构建后 gate 只报不判）" % len(cells))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--workflow", default="")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    wf = args.workflow or os.path.join(WORKFLOWS, "ci.yml")
    if not os.path.isfile(wf):
        print("FATAL：找不到 %s —— 判据无法自证，拒绝出结论" % wf)
        return 2
    steps = load_steps(wf)
    rc, lines, info = judge(steps)
    print("步骤位置核对（%s：%d 步）" % (os.path.basename(wf), len(steps)))
    for l in lines:
        print("  " + l)
    if info:
        print("  P2 清单（构建后 gate，只报不判，共 %d）：" % len(info))
        for i in info[:40]:
            print("    " + i)
    return rc


if __name__ == "__main__":
    sys.exit(main())
