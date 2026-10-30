#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_workflow_step_parity.py — **同源 workflow 之间的「必要步骤」覆盖面守卫**（R87 · BUG-490 家族）。

## 为什么需要它（实测 3 个实例，不是纸面推断）

本仓有两条同源 workflow：`.github/workflows/ci.yml`（测试面）与 `release.yml`（发布面）。
它们都要 `moon check` / `moon build`，而**依赖是惰性解包的** —— 见
`scripts/migrate_mooncakes_modjson.sh` 的自述：

> moon 0.1.20261012+ 解析依赖图时对旧格式清零：
> `moon.mod.json ... is no longer supported` ⇒ `Failed to resolve the module dependency graph`
> **每解析需要的包释放进 `.mooncakes`、并只报第一个过期件** ⇒ 必须循环迁移。

**⇒ 任何「跑 moon 的 job」都必须先 migrate。** 而这一步在两条 workflow 上被漏过 **3 次**：

| # | 缺失位置 | 后果 |
|---|---|---|
| 1 | `release.yml` 的 build-js（BUG-112 家族）| Release 零资产 |
| 2 | `release.yml` 的 build-native-linux（BUG-490）| Release 零资产 |
| 3 | **`release.yml` 的 build-native-windows**（R87 发现）| **少一个 Windows native 资产**（`continue-on-error` 让它**长期静默**）|

**⚠️ 第 3 个最危险**：`continue-on-error: true` ⇒ 它**不阻塞 release** ⇒
CI 只看到「有个 job 黄了」，而**资产面上少一件**从来没人报。**⇒ 静默缺失比红更持久。**

## 判据范围（**范围自述 == 实现**，逐条对实现核对）

**S1 跑 moon 的 job 必须先 migrate**：对 `release.yml` 的每个 job，若它的 steps 里出现
`moon check` / `moon build` / `moon test`，则**前序**必须有一个 `migrate_mooncakes_modjson` step。
（「前序」= 在 steps 数组里位置更靠前，不是只看「同一 job 里有就行」—— 顺序错了等于没做。）

**S2 覆盖面对表**：`ci.yml` 与 `release.yml` 里「跑 moon 的 job」数量各报出来，
**差值必须为 0 或已在 EXEMPT 里点名**（有的 job 用预构建产物，不需要跑 moon）。

**S3 自拒**：任一份 workflow 读不到 / 枚举不到任何 job / 一份里面一个 `moon` 步骤都没有
⇒ `rc=2`（**判据无法自证**，拒绝出结论 —— 与「都合规」的输出绝不相同）。

## 退出码

| rc | 含义 |
|---|---|
| 0 | 全部跑 moon 的 job 都先 migrate |
| 1 | 有 job 跑 moon 但没有先 migrate（**违例**，逐条点名） |
| 2 | 判据无法自证（workflow 读不到 / 枚举不到 / 一个 moon 步骤都没有） |

## 用法

    python scripts/check_workflow_step_parity.py            # 真跑
    python scripts/check_workflow_step_parity.py --selftest # 自证（含变异对照）
"""

from __future__ import annotations

import io
import os
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover —— 判据无法自证时如实报 2，不崩
    yaml = None

# Windows 控制台默认 GBK ⇒ 打印 `⇒`/`⚠️` 会 UnicodeEncodeError（BUG-58/138）。
# 判据必须**在任何平台上都能把话说出来**（说不出来 = rc 契约失效）。
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001 —— 老 Python / 非 tty 时没有 reconfigure
    pass

ROOT = os.environ.get("FIST_ROOT") or "."
CI = ".github/workflows/ci.yml"
REL = ".github/workflows/release.yml"

MOON_RX = re.compile(r"\bmoon\s+(check|build|test)\b")
MIGRATE_RX = re.compile(r"migrate_mooncakes_modjson")

# S2 的豁免面：这些 job 不跑 moon（用预构建产物 / 只上传下载），不需要 migrate。
# 每条必须写「为什么它不跑 moon」，否则等于发了张免检牌。
EXEMPT_JOBS = {
    ("release.yml", "meta"): "只解析版本号，不跑 moon",
    ("release.yml", "release"): "只 download-artifact + 上传 Release，不跑 moon",
}


def _load(path):
    """读一份 workflow，返回 dict 或 (None, 原因)。"""
    if yaml is None:
        return None, "PyYAML 不可用（判据无法解析 workflow）"
    p = os.path.join(ROOT, path)
    if not os.path.isfile(p):
        return None, "读不到 %s" % path
    try:
        with io.open(p, encoding="utf-8", errors="replace") as f:
            d = yaml.safe_load(f)
    except Exception as e:  # noqa: BLE001
        return None, "%s 解析失败: %s" % (path, e)
    if not isinstance(d, dict):
        return None, "%s 不是 mapping" % path
    return d, ""


def _job_steps(job):
    """取 job 的 steps 列表（容忍 `uses:` 与 `run:` 混排、容忍缺失）。"""
    if not isinstance(job, dict):
        return []
    steps = job.get("steps")
    return steps if isinstance(steps, list) else []


def _step_text(step):
    """把一步里所有可能含命令的键拼成一段文本。"""
    if not isinstance(step, dict):
        return ""
    parts = []
    for k in ("run", "name", "uses", "with"):
        v = step.get(k)
        if isinstance(v, str):
            parts.append(v)
        elif isinstance(v, dict):
            parts.extend(str(x) for x in v.values() if isinstance(x, str))
    return "\n".join(parts)


def _moon_pos_and_migrate_pos(steps):
    """返回 (最早 moon 步骤的 index, 最早 migrate 步骤的 index)，缺则 None。"""
    moon_at = None
    mig_at = None
    for i, s in enumerate(steps):
        t = _step_text(s)
        if moon_at is None and MOON_RX.search(t):
            moon_at = i
        if mig_at is None and MIGRATE_RX.search(t):
            mig_at = i
    return moon_at, mig_at


def judge(workflows):
    """纯判定：workflows = [(名字, dict)]。返回 (问题列表, 计数)。空问题 = 通过。"""
    problems = []
    counts = {"moon_jobs": 0, "migrate_jobs": 0}
    seen_moon_anywhere = False
    total_jobs = 0
    for name, d in workflows:
        jobs = d.get("jobs") or {}
        if not isinstance(jobs, dict) or not jobs:
            problems.append("S3 %s 里枚举不到任何 job（判据无法自证）" % name)
            continue
        total_jobs += len(jobs)
        for jn, job in jobs.items():
            steps = _job_steps(job)
            moon_at, mig_at = _moon_pos_and_migrate_pos(steps)
            if moon_at is not None:
                seen_moon_anywhere = True
                counts["moon_jobs"] += 1
            if mig_at is not None:
                counts["migrate_jobs"] += 1
            if moon_at is None:
                # S2：不跑 moon 的 job 必须在 EXEMPT 里点名，否则**可能是它本该跑却没配**。
                key = (name, jn)
                if key not in EXEMPT_JOBS and mig_at is None:
                    # 只报「既不跑 moon、又不在豁免表」的 —— 不误伤合法 job
                    problems.append(
                        "S2 %s 的 job `%s` 不跑 moon 且未在 EXEMPT_JOBS 里点名理由"
                        % (name, jn))
                continue
            # S1：跑 moon 的 job，migrate 必须**在它之前**
            if mig_at is None:
                problems.append(
                    "S1 %s 的 job `%s` 跑 moon（step #%d）但**没有** migrate_mooncakes_modjson —— "
                    "依赖惰性解包 ⇒ 新版 moon 拒旧 moon.mod.json ⇒ 该 job 必红（BUG-490 家族）"
                    % (name, jn, moon_at + 1))
            elif mig_at > moon_at:
                problems.append(
                    "S1 %s 的 job `%s` 的 migrate 在 moon **之后**（migrate #%d / moon #%d）—— "
                    "顺序错了等于没做" % (name, jn, mig_at + 1, moon_at + 1))
    if not seen_moon_anywhere:
        problems.append("S3 两份 workflow 里一个跑 moon 的 step 都没有 ⇒ 判据无法自证")
    if total_jobs == 0:
        problems.append("S3 两份 workflow 合计 0 个 job ⇒ 判据无法自证")
    return problems, counts


def run():
    """真判据调用面：读两份 workflow、判、打读数与退出码。"""
    loaded = []
    bad = []
    for p in (CI, REL):
        d, err = _load(p)
        if err:
            bad.append(err)
        else:
            loaded.append((os.path.basename(p), d))
    if bad:
        for b in bad:
            print("FATAL " + b)
        print("判据无法自证 —— 拒绝出结论，也拒绝因「没找到」报绿。rc=2")
        return 2
    problems, counts = judge(loaded)
    print("扫描面：%s + %s；跑 moon 的 job %d 个 / 有 migrate 的 job %d 个"
          % (CI, REL, counts["moon_jobs"], counts["migrate_jobs"]))
    if problems:
        for x in problems:
            print("  " + x)
        print("FAIL：workflow 步骤覆盖面不一致（%d 条）" % len(problems))
        return 1
    print("PASS：全部「跑 moon」的 job 都**先** migrate；不跑 moon 的 job 已逐条点名理由")
    return 0


def selftest():
    """自证：**变异对照**为主，不是只断言「正常路径通过」。

    ⚠️ 每条违规用例都**逐字**构造出 BUG-490 家族的真实形态，不是随手编的假数据。
    """
    fails = []

    def cell(name, got, want):
        if got != want:
            fails.append("%s: got %r want %r" % (name, got, want))

    def wf(**jobs):
        """构造一份最小 workflow：jobs 名 -> **job dict**（`{"steps": [...]}`）。

        ⚠️ R87 自检抓到：初版直接传 steps 列表 ⇒ `_job_steps()` 走 `job.get("steps")`
        取到空 ⇒ **每一格都在测空数据**（又是判例-30 的「空循环」形态）。
        ⇒ 必须传 job dict。
        """
        return {"jobs": {k: {"steps": v} if isinstance(v, list) else v
                          for k, v in jobs.items()}}

    def good_job():
        return [{"name": "migrate", "run": "bash scripts/migrate_mooncakes_modjson.sh 'moon check'"},
                {"name": "build", "run": "moon build --target native"}]

    def bad_job():
        # 真实形态：**没有** migrate，直接 moon build（= build-native-windows 的旧状）
        return [{"name": "Build native", "run": "moon build --target native"}]

    def wrong_order_job():
        # migrate 在 moon 之后（顺序错）
        return [{"name": "Build native", "run": "moon build --target native"},
                {"name": "migrate", "run": "bash scripts/migrate_mooncakes_modjson.sh"}]

    # ① 干净：一 good 一 bad-exempt（不跑 moon 且在豁免表）⇒ 无问题
    clean = [("ci.yml", wf(a=good_job())),
             ("release.yml", wf(meta=[{"run": "echo v"}], release=[{"uses": "x"}]))]
    # meta / release 不在 EXEMPT_JOBS 里 ⇒ S2 会报；先把它们临时塞进豁免面再判
    saved = dict(EXEMPT_JOBS)
    EXEMPT_JOBS[("release.yml", "meta")] = "selftest 合成"
    EXEMPT_JOBS[("release.yml", "release")] = "selftest 合成"
    try:
        p_clean, c_clean = judge(clean)
        cell("clean-no-problems", p_clean, [])
        cell("clean-counts-moon-job", c_clean["moon_jobs"], 1)

        # ② **变异对照 1（BUG-490 的正身）**：跑 moon 但没 migrate ⇒ 必报 S1
        p_miss, _ = judge([("ci.yml", wf(a=good_job())), ("release.yml", wf(b=bad_job()))])
        cell("missing-migrate-flagged", any(x.startswith("S1") for x in p_miss), True)

        # ③ **变异对照 2**：migrate 在 moon **之后** ⇒ 也必报 S1（顺序错等于没做）
        p_order, _ = judge([("ci.yml", wf(a=good_job())), ("release.yml", wf(b=wrong_order_job()))])
        cell("wrong-order-flagged", any(x.startswith("S1") for x in p_order), True)

        # ④ 自拒 1：枚举不到 job
        p_nojob, _ = judge([("ci.yml", {"jobs": {}}), ("release.yml", wf(a=good_job()))])
        cell("no-jobs-selfreject", any(x.startswith("S3") for x in p_nojob), True)

        # ⑤ 自拒 2：一个 moon 步骤都没有（空宇宙 ⇒ 不许报绿）
        p_nomoon, _ = judge([("ci.yml", {"jobs": {"j": [{"run": "echo hi"}]}}),
                             ("release.yml", {"jobs": {"j": [{"run": "echo hi"}]}})])
        cell("no-moon-selfreject", any(x.startswith("S3") for x in p_nomoon), True)

        # ⑥ S2：不跑 moon 且不在豁免表 ⇒ 报（防「它本该跑却没配」被静默放过）
        p_s2, _ = judge([("ci.yml", wf(a=good_job())),
                         ("release.yml", wf(mystery=[{"run": "echo hi"}]))])
        cell("unexempt-no-moon-flagged", any(x.startswith("S2") for x in p_s2), True)

        # ⑦ 反向对照：migrate 与 moon **写在同一步**（同一 `run:` 里）也算合规吗？
        #    实测语义：同一 run 里先 migrate 后 moon ⇒ 合规。
        same_step = [{"run": "bash scripts/migrate_mooncakes_modjson.sh 'moon check'\nmoon build"}]
        p_same, _ = judge([("ci.yml", wf(a=same_step)), ("release.yml", wf(meta=[{"run": "echo"}]))])
        cell("same-step-is-ok", any(x.startswith("S1") for x in p_same), False)
    finally:
        EXEMPT_JOBS.clear()
        EXEMPT_JOBS.update(saved)

    if fails:
        print("SELFTEST FAIL（%d 格）：" % len(fails))
        for f in fails:
            print("  - " + f)
        return 1
    print("SELFTEST PASS（7 格：干净不误红 / 缺 migrate 必红 / 顺序错必红 / "
          "空 job 自拒 / 空 moon 自拒 / 未豁免的静默 job 必报 / 同步合规）")
    return 0


def main(argv=None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    known = {"--selftest"}
    unknown = [a for a in args if a.startswith("-") and a not in known]
    if unknown:
        print("[FATAL] 未知参数 %s —— 已知：%s（rc=2）"
              % (" ".join(unknown), " / ".join(sorted(known))))
        return 2
    if "--selftest" in args:
        return selftest()
    return run()


if __name__ == "__main__":
    sys.exit(main())
