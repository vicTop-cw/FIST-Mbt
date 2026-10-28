#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_skill_inject.py — 「plan/claim 的 inject 真的能命中资产」守卫（BUG-139 同族）。

为什么需要它：`evolve_asset_register` 把外部资产注册进 DGM 档案库，plan/claim 的
`inject` 参数按关键词子串检索这些资产——**但如果匹配逻辑退化了，inject 恒空**
（注册再多资产也注入不进去），而这一步此前无人认领。本守卫补的是
「注入路径可测命中」这一格：**只做静态可测命中 + 落库资产反查**，**不黑盒真调 MCP**。

判据范围（**范围自述 == 实现**，逐条对实现核对）：

  S1 · 静态扫描注入匹配逻辑（**主判据**，真源 = `src/server/server.mbt`：
       `lookup_injected_assets_in`）。判「至少按 goal/note 子串检索」是否真的存在：
       ① 函数 `lookup_injected_assets_in` 存在；
       ② 把 inject 按 `,` 分割成关键词数组；
       ③ 对每个 Artifact，用 `.contains(k)` 子串匹配 `art.goal` **或** `art.note`。
       **匹配键是 `goal` + `note`，不含 `code`**（`code` 只在命中结果里回传，
       不作匹配键）——这是真源实况，判据如实自述，不吹成「goal/code/note 三面都配」。
       若 ①②③ 任一缺失 → 匹配逻辑退化 → **红**。
       注：`src/evolve/` 只提供 Archive/Artifact 数据模型与 `evolve_lesson_persist`，
       inject 匹配逻辑**不在** evolve 包里（在 server 层），故 S1 扫 `src/server/`，
       并顺带确认 `src/evolve/` 里不出现一份与 server 冲突的退化实现。

  S2 · 匹配逻辑有测试锁 → 静态确认 `src/server/memory_test.mbt` 里存在
       `memory_13_lookup_injected_assets_hit_and_empty`（白盒锁：命中/空关键词/无关词
       三态都有断言）。缺失 → **红**（无锁的匹配逻辑会悄无声息退化）。

  S3 · 落库资产反查（**次判据**）：DGM 资产实际持久化到 SQLite `evolve_artifacts` 表
       （`evolve_auto_wire` 明写「落库后 plan/claim 的 inject 与 dead_ends 均可直接
       检索」，不是 `memory/*.md` 文件）。判：
       · `fist-mbt.db` 或 `evolve_artifacts` 表读不到 → **自拒 exit 2**（输入面退化，
         不静默绿）；
       · 表里 **0 条 `[asset]` 条目** → **自拒 exit 2**（档案面空，roundtrip 判据
         无对象，不静默绿）；
       · ≥1 条 `[asset]` 条目 → 逐条验证：`goal` 含 `[asset]<source>` 形状、
         `note` 与 `code` 非空（可注入）→ 违规即 **红**。
       `[lesson]` 条目不算 `[asset]`（它们是失败回流教训，走同类匹配但非「外部
       资产注册」面）。

扫描面（缺关键文件 → 自拒 exit 2）：
  `src/server/server.mbt`（inject 匹配逻辑真源）
  `src/server/memory_test.mbt`（白盒锁）
  `fist-mbt.db`（`evolve_artifacts` 表）

退出码契约：0=通过；1=有违例；2=判据输入面退化/档案面空（自拒，不静默绿）。

用法：
    python scripts/check_skill_inject.py            # 全量判据
    python scripts/check_skill_inject.py --selftest # 自检判据本身没坏
"""
import json
import re
import sqlite3
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent

SERVER_MBT = "src/server/server.mbt"
MEMORY_TEST = "src/server/memory_test.mbt"
EVOLVE_DIR = "src/evolve"
DB = "fist-mbt.db"
ASSET_MARKER = "[asset]"
TEST_NAME = "memory_13_lookup_injected_assets_hit_and_empty"


# ── S1：注入匹配逻辑存在性 ──────────────────────────────────────────────────
def inject_logic_problems(server_text: str) -> list[str]:
    """判注入匹配逻辑是否真的按 goal/note 子串检索。返回违例列表。"""
    problems: list[str] = []

    # ① 函数存在
    fn = re.search(r"fn\s+lookup_injected_assets_in\s*\(", server_text)
    if not fn:
        problems.append("src/server/server.mbt 里找不到 `lookup_injected_assets_in`"
                        " → plan/claim 的 inject 无匹配逻辑")
        return problems  # 函数都没有，后面的检查无意义

    # 提取函数体（到下一个 `///|` 块或下一个 `pub fn`/`fn ` 为止）
    body = server_text[fn.start():]
    end = re.search(r"\n///\|\n|\npub fn |\nfn ", body[1:])
    if end:
        body = body[:end.start() + 1]

    # ② 按逗号分割
    if "split(\",\")" not in body:
        problems.append("`lookup_injected_assets_in` 不按 `,` 分割 inject 关键词"
                        " → 多关键词注入会退化成空")

    # ③ 子串匹配 goal / note
    if ".contains(k)" not in body:
        problems.append("`lookup_injected_assets_in` 未用子串匹配（`.contains(k)`）"
                        " → 关键词命中逻辑退化（可能退化成相等比较/恒空）")
    if "goal.contains(k)" not in body and "goal.contains" not in body:
        problems.append("`lookup_injected_assets_in` 未对 `art.goal` 做子串匹配"
                        " → 注册资产的 goal 无法被 inject 命中")
    # goal 与 note 至少一个（真源是 goal || note）
    if "goal.contains(k)" not in body and "note.contains(k)" not in body:
        problems.append("`lookup_injected_assets_in` 既不对 goal 也不对 note 做子串匹配"
                        " → 注入路径空转")

    return problems


# ── S2：白盒锁存在 ──────────────────────────────────────────────────────────
def inject_test_problems(test_text: str) -> list[str]:
    problems: list[str] = []
    if TEST_NAME not in test_text:
        problems.append("src/server/memory_test.mbt 里找不到测试 `%s`"
                        " → 匹配逻辑无白盒锁，退化无人察觉" % TEST_NAME)
    else:
        # 锁里应命中 goal（[asset]code-review）的注入关键词
        if "code-review" not in test_text:
            problems.append("白盒锁 `%s` 未用 `code-review` 这类 `[asset]<source>` "
                            "关键词做命中断言 → 锁的是别的面" % TEST_NAME)
    return problems


# ── S3：落库资产反查 ────────────────────────────────────────────────────────
def read_asset_rows(db_path: Path) -> tuple[str | None, list[dict]]:
    """读 evolve_artifacts 表里的 `[asset]` 条目。
    返回 (错误信息 或 None, 条目列表)。错误非空 = 输入面退化。"""
    if not db_path.exists():
        return "fist-mbt.db 不存在（%s）" % db_path, []
    try:
        con = sqlite3.connect(str(db_path))
        try:
            cur = con.cursor()
            cur.execute(
                "SELECT name FROM sqlite_master WHERE type='table' "
                "AND name='evolve_artifacts'"
            )
            if not cur.fetchone():
                return "fist-mbt.db 里没有 `evolve_artifacts` 表", []
            # `[asset]` 条目的判别位是 **goal**（`evolve_asset_register` 落库为
            # `[asset]<source>`，`evolve_lesson` 落库为 `[lesson]<cat>`）——只按
            # goal 匹配才与 L35-37「`[lesson]` 条目不算 `[asset]`」一致。
            # 旧实现匹配 goal/note/code 三面：一条 `[lesson]` 教训只要在 code 里
            # 提一句归档规则（讲 evolve_asset_register 怎么用）就会被误选，
            # 再因 goal 不是 `[asset]<source>` 被误报「反查问题」（实测命中
            # lesson-202610-15.05.17，goal=`[lesson] concurrent-coordination`）。
            # 且 `lookup_injected_assets_in` 只按 goal/note 子串检索、不匹配 code，
            # 匹配 code 本身就不落在判据面内。故收窄为 goal 单面。
            cur.execute(
                "SELECT id, goal, note, code FROM evolve_artifacts "
                "WHERE goal LIKE ? "
                "ORDER BY created_at ASC",
                ("%" + ASSET_MARKER + "%",),
            )
            rows = []
            for rid, goal, note, code in cur.fetchall():
                rows.append({
                    "id": rid or "",
                    "goal": goal or "",
                    "note": note or "",
                    "code": code or "",
                })
            return None, rows
        finally:
            con.close()
    except Exception as e:
        return "读 evolve_artifacts 失败：%s" % e, []


def asset_rows_problems(rows: list[dict]) -> list[str]:
    """逐条验证 `[asset]` 条目的 asset_id 能反查且可注入。"""
    problems: list[str] = []
    for r in rows:
        rid = r["id"]
        # asset_id 非空
        if not rid.strip():
            problems.append("存在无 asset_id 的 `[asset]` 条目（goal=%s）"
                            % r["goal"][:40])
        # goal 含 [asset]<source> 形状
        if not re.search(r"\[asset\]\s*\S+", r["goal"]):
            problems.append("`[asset]` 条目 %s 的 goal `%s` 不含 `[asset]<source>`"
                            " 形状 → 无法按来源名检索"
                            % (rid or "?", r["goal"][:60]))
        # note / code 非空（可注入）
        if not r["note"].strip():
            problems.append("`[asset]` 条目 %s 的 note 为空 → 可注入提示词缺失" % rid)
        if not r["code"].strip():
            problems.append("`[asset]` 条目 %s 的 code 为空 → 来源路径缺失" % rid)
    return problems


def asset_rows_surface(rows: list[dict]) -> bool:
    """档案面是否真的非空（0 条 → 自拒 exit 2）。"""
    return len(rows) > 0


# ── 关键文件缺失 → 自拒 ─────────────────────────────────────────────────────
def missing_key_files() -> list[str]:
    return [c for c in [SERVER_MBT, MEMORY_TEST] if not (ROOT / c).exists()]


# ── 自检 ─────────────────────────────────────────────────────────────────────
def selftest() -> list[str]:
    fails: list[str] = []

    # U1 含 [asset]<kw> 的档案条目 → 反查命中（绿）：造一条合规条目，判据必须不红
    good_rows = [{
        "id": "asset-code-review-x",
        "goal": "[asset]code-review 代码审查检查单",
        "note": "审查提示词：检查缺意外路径/竞态",
        "code": "docs/superpowers/checklist.md",
    }]
    if asset_rows_problems(good_rows):
        fails.append("U1 把合规 `[asset]` 条目误判成违规 → 恒红判据不可信：%s"
                     % asset_rows_problems(good_rows))

    # U1b 档案面非空识别：合规条目 → 不触发自拒
    if not asset_rows_surface(good_rows):
        fails.append("U1b 档案面非空却被识别成空 → 会把合规面误自拒 exit 2")

    # U2 匹配逻辑缺失/退化 → 红（合成文本喂给 inject_logic_problems）
    if not inject_logic_problems("pub fn foo() -> Int { 0 }\n"):
        fails.append("U2 匹配逻辑完全缺失却不红 → 判据饿死")

    # U2b 匹配逻辑从子串退化成分词/相等 → 红
    degraded = (
        "pub fn lookup_injected_assets_in(arc, inject) -> Json {\n"
        "  for art in all(arc) {\n"
        "    if art.goal == inject {  // 相等比较，非子串\n"
        "      push(hits, art)\n"
        "    }\n"
        "  }\n"
        "}\n"
    )
    if not inject_logic_problems(degraded):
        fails.append("U2b 匹配逻辑退化成分词/相等比较却不红 → 子串判据没拦住退化")

    # U2c 合规匹配逻辑 → 绿（反向对照）
    good_server = (
        "pub fn lookup_injected_assets_in(arc, inject) -> Json {\n"
        "  let ksq = []\n"
        "  for k in inject.split(\",\") {\n"
        "    let s = k.trim().to_string()\n"
        "    if s != \"\" { ksq.push(s) }\n"
        "  }\n"
        "  for art in all(arc) {\n"
        "    for k in ksq {\n"
        "      if art.goal.contains(k) || art.note.contains(k) {\n"
        "        push(hits, art)\n"
        "        break\n"
        "      }\n"
        "    }\n"
        "  }\n"
        "}\n"
    )
    if inject_logic_problems(good_server):
        fails.append("U2c 把合规匹配逻辑误判红 → 判据不可信：%s"
                     % inject_logic_problems(good_server))

    # U3 档案面空 → 自拒（不静默绿）
    if asset_rows_surface([]):
        fails.append("U3 档案面空却被识别成非空 → 空面静默绿")

    # U3b 输入面退化识别：合成缺失清单必须能触发自拒（判据不静默绿）
    if not [c for c in ["nope/server.mbt", "nope/test.mbt"] if not (ROOT / c).exists()]:
        fails.append("U3b 输入面退化时不报缺失 → 判据无输入面却照常出结论")
    # 真实现状关键文件应齐全（若缺，判据将自拒 exit 2，本轮不可判）
    if missing_key_files():
        fails.append("U3b2 真实现状面缺关键文件：%s → 本轮判据自拒 exit 2"
                     % ", ".join(missing_key_files()))

    # U4 现状真源不红（尺子自证）：当前 server.mbt 的匹配逻辑应是合规的
    p = ROOT / SERVER_MBT
    if p.exists():
        real = inject_logic_problems(p.read_text(encoding="utf-8"))
        if real:
            fails.append("U4 现状注入匹配逻辑红了（应为绿）：" + real[0])
    else:
        fails.append("U4 找不到 src/server/server.mbt → 扫描面选错了")

    # U5 现状白盒锁不红
    mp = ROOT / MEMORY_TEST
    if mp.exists():
        real = inject_test_problems(mp.read_text(encoding="utf-8"))
        if real:
            fails.append("U5 现状白盒锁红了（应为绿）：" + real[0])

    return fails


def main(argv: list[str]) -> int:
    unknown = [a for a in argv if a != "--selftest"]
    if unknown:
        print("FATAL 未知参数：%s（本尺只接受 --selftest）" % " ".join(unknown))
        sys.exit(2)
    # ↑ 严格参数面（R65）：未知旗标不再被静默忽略（拼错 --selftest 会假绿）
    if "--selftest" in argv:
        fails = selftest()
        if fails:
            print("SELFTEST FAIL 判据自身有问题：")
            for f in fails:
                print("  - " + f)
            return 1
        print("SELFTEST OK 注入路径判据可红可绿（合规 [asset] 条目不误红 / 匹配逻辑缺失或"
              "退化必红 / 档案面空与输入面退化必自拒 exit 2 / 现状真源与白盒锁不误红）")
        return 0

    # 输入面退化 → 自拒
    absent = missing_key_files()
    if absent:
        print("FATAL 判据输入面退化：缺 %s —— 拒绝出结论（不静默绿）" % ", ".join(absent))
        return 2

    server_text = (ROOT / SERVER_MBT).read_text(encoding="utf-8")
    test_text = (ROOT / MEMORY_TEST).read_text(encoding="utf-8")

    problems: list[str] = []

    # S1 主判据：匹配逻辑
    problems.extend(inject_logic_problems(server_text))
    # S2 白盒锁
    problems.extend(inject_test_problems(test_text))

    # S1/S2 红了 → 直接红（匹配逻辑退化是硬伤，不必再看档案面）
    if problems:
        print("FAIL 注入路径判据有违例：")
        for p in problems:
            print("  - " + p)
        return 1

    # S3 落库资产反查
    db = ROOT / DB
    err, rows = read_asset_rows(db)
    if err:
        print("FATAL %s —— roundtrip 判据无输入面，自拒 exit 2（不静默绿）" % err)
        return 2
    if not asset_rows_surface(rows):
        print("FATAL `evolve_artifacts` 表里 0 条 `[asset]` 条目（档案面空）—— "
              "roundtrip 判据无对象，自拒 exit 2（不静默绿）。"
              "请先 `evolve_asset_register` 注册至少一条外部资产；静态注入逻辑判据 "
              "（S1/S2）已通过，本轮不报绿是因为「真的能命中」这一格还没输入面。")
        return 2

    ap = asset_rows_problems(rows)
    if ap:
        print("FAIL 已注册 `[asset]` 资产存在反查问题（共 %d 条）：" % len(ap))
        for p in ap:
            print("  - " + p)
        return 1

    print("PASS 注入路径可测命中：`lookup_injected_assets_in` 按 goal/note 子串匹配（"
          "真源 src/server/server.mbt）；白盒锁 `%s` 在位；已注册 %d 条 `[asset]` "
          "资产全部 asset_id 可反查且 note/code 非空可注入" % (TEST_NAME, len(rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))