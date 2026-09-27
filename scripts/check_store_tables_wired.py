#!/usr/bin/env python3
"""BUG-28 守卫：store 里每张表要么**有写入点**，要么在源码里**显式声明为预留**。

为什么不是"看一遍注释就行"：schema 是对外声明的数据模型。`runs` 建了表、注释写着
「供 Phase 2(Omega) / Phase 5(scheduler) 使用」，但全仓零写入零读取（实测
`select count(*) from runs` = 0，同库 specs=451/tasks=1147 ⇒ 不是没初始化）——
读源码的人和 AI 都会把"验收有 runs 记录可查"当成已具备的能力，规范 r1「文档即实现」
在这里断裂。光改注释只治这一次，本守卫治"再长出第二张 runs"。

判据双向（与 check_doc_surface J10 同一手法：声明滞后与幻影声明都要能发红）：
  · 无写入点且未声明预留   → 红（第二张 runs）
  · 声明了预留却有写入点   → 红（声明滞后，能力已上线还挂着"未接线"）
  · 解析不到任何表         → FATAL(2)（扫描面空转 ≠ 没有问题，绝不报绿）

用法：python scripts/check_store_tables_wired.py [--selftest]
退出码：0=PASS，1=违例，2=判据无法自证。
"""
import io
import re
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "src" / "store" / "store_sqlite.mbt"
SRC = ROOT / "src"

RE_TABLE = re.compile(r"CREATE TABLE IF NOT EXISTS (\w+)")
RE_WRITE = re.compile(r"(INSERT INTO|UPDATE|DELETE FROM|REPLACE INTO)\s+(\w+)")
# 机器可读的预留声明行（写在 store 源文件里，注释改词不影响判据）
RE_RESERVED = re.compile(r"schema-reserved\s*:\s*([A-Za-z_0-9,\s]+)")


def collect_tables(store_txt):
    return [t for t in RE_TABLE.findall(store_txt) if t != "sqlite_sequence"]


def collect_writes():
    """src/**/*.mbt 里出现过的写入目标表名集合。"""
    written = set()
    for p in SRC.rglob("*.mbt"):
        try:
            txt = io.open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for _, tbl in RE_WRITE.findall(txt):
            written.add(tbl)
    return written


def collect_reserved(store_txt):
    out = set()
    for m in RE_RESERVED.finditer(store_txt):
        for name in m.group(1).split(","):
            name = name.strip()
            if name:
                out.add(name)
    return out


def table_problems(tables, written, reserved):
    """纯判据：喂（表清单, 有写入点的表, 声明预留的表）→ 违例列表。"""
    problems = []
    for t in tables:
        has_write = t in written
        declared = t in reserved
        if not has_write and not declared:
            problems.append(
                f"{t}：无写入点且未声明预留 —— 就是 BUG-28 的 runs（恒 0 行的死 schema，"
                "读侧会把它当可用能力）；要么接线，要么在 store 源文件加 `schema-reserved: <表名>`"
            )
        if has_write and declared:
            problems.append(
                f"{t}：已声明为预留却已有写入点 —— 声明滞后（能力上线了还挂着「未接线」，"
                "比没写注释更坏）；请删掉 schema-reserved 里的这个名字"
            )
    return problems


def selftest():
    """合成违例必须发红、干净输入不得误红（否则守卫是装饰）。"""
    fails = []
    clean = table_problems(["tasks", "runs"], {"tasks"}, {"runs"})
    if clean:
        fails.append(f"干净输入误红：{clean}")
    dead = table_problems(["tasks", "runs"], {"tasks"}, set())
    if not any("runs" in p for p in dead):
        fails.append("抓不到「无写入点且未声明预留」（runs 那类死 schema 会隐身）")
    stale = table_problems(["runs"], {"runs"}, {"runs"})
    if not any("声明滞后" in p for p in stale):
        fails.append("抓不到「声明滞后」（已接线还挂预留）")
    # 扫描面空转：表清单为空时真判据必须 FATAL，而不是"零违例=PASS"
    if collect_tables("") != []:
        fails.append("表名解析器混进了非表名（CREATE TABLE 解析口径变了）")
    if fails:
        for f in fails:
            print("SELFTEST FAIL: " + f)
        return 1
    print(
        "SELFTEST OK: 判据对「死 schema」与「声明滞后」两个方向都发红，"
        "干净输入不误红，表名解析口径可证"
    )
    return 0


def main():
    args = sys.argv[1:]
    if "--selftest" in args:
        return selftest()
    if not STORE.exists():
        print(f"FATAL 找不到 store 源文件 {STORE}（判据无法自证）")
        return 2
    store_txt = io.open(STORE, encoding="utf-8", errors="replace").read()
    tables = collect_tables(store_txt)
    if not tables:
        print("FATAL 未解析到任何 CREATE TABLE（扫描面空转，拒绝出绿灯）")
        return 2
    written = collect_writes()
    reserved = collect_reserved(store_txt)
    problems = table_problems(tables, written, reserved)
    unknown = sorted(reserved - set(tables))
    if unknown:
        problems.append(
            f"schema-reserved 声明了不存在的表：{', '.join(unknown)}（声明与 schema 脱钩）"
        )
    wired = [t for t in tables if t in written]
    left = [t for t in tables if t in reserved and t not in written]
    if problems:
        print(f"FAIL store schema 接线一致性（共 {len(tables)} 张表）：")
        for p in problems:
            print("  - " + p)
        return 1
    print(
        f"PASS store schema 接线一致：{len(tables)} 张表 = "
        f"{len(wired)} 张有写入点 + {len(left)} 张显式预留"
        + (f"（{', '.join(sorted(left))}）" if left else "")
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
