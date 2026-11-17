#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""scripts/check_mcpcf_db_isolation.py — BUG-583 方向④：mcpcf 沙箱库路径 ≠ 主库路径，从路径约定变成可核断言。

为什么需要它（BUG-583）：mcpcf 嵌入式引擎（src/server/mcpcf_embed.mbt）自带一套 SQLite 库
（默认 %LOCALAPPDATA%\mcpconftest\data\mcpconftest-ops.db），与主 MCP 路径的库
（.fist-mbt/data/<ns>.db，或 FIST_DB_PATH 指定）是两条路径家族。两边共用 circuit_breakers
表形状但时基不同（mcpcf 裸 Unix 秒 vs 主路 ops_ts，相差约 1.7e9 秒）；一旦 FIST_DB_PATH
指到沙箱库，熔断状态跨时基混写 ⇒ 永久 Open / 随机 Half-Open。「两条路径不相交」此前只是
注释里的约定，没有尺子看着 —— 本判据把它变成机器断言。

判据面（真源现读，不抄副本）：
  基线：mcpcf 库名 / 目录优先级 / 回退目录 从 mcpcf_embed.mbt 的 ops_data_dir() 与三处库名
        拼接现解析；主库 data_dir 默认与 ns 库形状从 multi_store.mbt 现解析；主库默认库名 /
        env 键 / trim 事实从 store_sqlite.mbt 现解析。任一份读不到 / 为空 / 解析不出 ⇒
        自拒 rc=2，绝不给绿。
  A1-A4 静态断言（默认配置下两条路径家族不相交）：
    A1 mcpcf 默认目录后缀（LOCALAPPDATA 之后的段族）与主库 data_dir 段族不相交（不等、互不包含）；
    A2 mcpcf 回退目录（cwd 相对）与主库 data_dir 段族不相交；
    A3 mcpcf 库名 ≠ 主库默认库名；
    A4 mcpcf 的两个 env 键与主库 env 键互不相同。
  C1 碰撞格（env 面）：FIST_DB_PATH 已设置且（按真源 trim 事实处理后）与 mcpcf 沙箱库路径
     归一后同文件 ⇒ 红，点名两条路径；未设置 ⇒ 格空过，但输出明说「FIST_DB_PATH 未设置，
     碰撞格空过」，不许静默。沙箱路径按真源的**字面拼接**镜像计算（覆盖键原样采用不 trim ——
     真源 Some(d) => d；库名拼接的反斜杠在 MoonBit 源码里是 "\\" 转义，解码后是单个 '\'）。

覆盖面盲点（如实标注，不冒充已覆盖）：
  · 只管路径面，不管时基面（裸 Unix 秒 vs ops_ts 的混写机理是方向①②③，owner 裁决项）；
  · 碰撞格读的是**本检查进程**的 env，不是 server 运行时 env —— 部署侧设了而检查进程没设 ⇒ 空过；
  · 归一只做 normcase/normpath + cwd 拼接，不做 symlink/hardlink 的 samefile 判定；
  · 对称面（MCPCONFTEST_DATA_DIR 指进主库 data_dir）不在碰撞格口径内 —— 静态 A1/A2 只钉默认配置；
  · 静态断言是段族级的：LOCALAPPDATA 本身被设成主库目录一类极端 env 不在静态面内。

用法：
  python scripts/check_mcpcf_db_isolation.py             # 主面（电池常驻）
  python scripts/check_mcpcf_db_isolation.py --selftest  # 合成夹具自检（含变异对照，不读仓库现状）
退出码：0=隔离成立（含碰撞格空过） / 1=真实违例（静态断言被破或碰撞命中） / 2=判据无法自证（真源读不到/为空/解析不出） / 4=尺子自己坏了（未捕获异常，绝不冒用 1）
"""

import argparse
import contextlib
import io
import os
import re
import shutil
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ---------------------------------------------------------------- 真源解析（纯函数）

def _fn_body(text, header_re):
    """从函数头正则匹配处起做花括号计数，取函数体文本；取不到返回 None。
    口径：只用于 ops_data_dir / default_db_path / db_path_from_env 这三个小函数，
    它们的字符串字面量里没有花括号；形状漂移到解析不出 ⇒ 上层自拒 rc=2，不硬猜。"""
    m = re.search(header_re, text)
    if not m:
        return None
    i = m.end() - 1  # 指向 '{'
    depth = 0
    start = i
    while i < len(text):
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:i]
        i += 1
    return None


def parse_mcpcf(text):
    """从 mcpcf_embed.mbt 现读：库名（所有 `+ "\\xxx.db"` 拼接点必须一致）、
    ops_data_dir 的覆盖键 / 基底键 / 基底后缀（MoonBit 转义解码后）/ 回退目录。"""
    if not text or not text.strip():
        return None
    hits = re.findall(r'\+\s*"\\\\([^"\\]+\.db)"', text)
    if not hits or len(set(hits)) != 1:
        return None
    db_name = hits[0]
    body = _fn_body(text, r'fn\s+ops_data_dir\s*\(\s*\)\s*->\s*String\s*\{')
    if body is None:
        return None
    keys = re.findall(r'get_env_var\("([A-Z_][A-Z0-9_]*)"\)', body)
    if len(keys) < 2:
        return None
    m = re.search(r'\w+\s*\+\s*"((?:\\\\[^"\\]+)+)"', body)
    if not m:
        return None
    base_suffix = m.group(1).replace("\\\\", "\\")
    m = re.search(r'"(\./[^"]+)"', body)
    if not m:
        return None
    return {"db_name": db_name, "db_suffix": "\\" + db_name,
            "override_key": keys[0], "base_key": keys[1],
            "base_suffix": base_suffix, "fallback": m.group(1),
            "db_sites": len(hits)}


def parse_multi(text):
    """从 multi_store.mbt 现读：MultiStore::new 的 data_dir 默认值 + ns 库路径形状。"""
    if not text or not text.strip():
        return None
    m = re.search(r'MultiStore::new\(data_dir~\s*:\s*String\s*=\s*"([^"]+)"', text)
    if not m:
        return None
    data_dir = m.group(1)
    m = re.search(r'let path = "\\\{self\.data_dir\}/\\\{(\w+)\}\.db"', text)
    if not m:
        return None
    return {"data_dir": data_dir, "ns_var": m.group(1)}


def parse_sqlite(text):
    """从 store_sqlite.mbt 现读：默认库名、default_db_path() 用的 env 键、
    db_path_from_env 是否 trim（r197/r241 尾随空格事故后的真源事实）。"""
    if not text or not text.strip():
        return None
    m = re.search(r'let default_db_path\s*:\s*String\s*=\s*"([^"]+)"', text)
    if not m:
        return None
    default_db = m.group(1)
    body = _fn_body(text, r'pub fn SqliteStore::default_db_path\(\)\s*->\s*String\s*\{')
    if body is None:
        return None
    keys = re.findall(r'get_env_var\("([A-Z_][A-Z0-9_]*)"\)', body)
    if len(keys) != 1:
        return None
    env_body = _fn_body(
        text, r'pub fn SqliteStore::db_path_from_env\(env_value\s*:\s*String\?\)\s*->\s*String\s*\{')
    if env_body is None:
        return None
    return {"default_db": default_db, "env_key": keys[0], "trim": ".trim()" in env_body}


# ---------------------------------------------------------------- 静态断言（纯函数）

def segments(p):
    """路径段族：两种分隔符都切（mcpcf 真源用字面反斜杠拼接，Linux 上它是文件名字符，
    但段族比较只关心「目录家族的尾巴」，切开后跨平台同形）。"""
    return [s for s in re.split(r"[\\/]+", p) if s and s != "."]


def is_suffix(short, long):
    return len(short) <= len(long) and long[len(long) - len(short):] == short


def families_disjoint(a, b):
    """两个目录家族不相交 = 段族既不相等、也互不为后缀（包含）。空段族证不出不相交 ⇒ False。"""
    sa, sb = segments(a), segments(b)
    if not sa or not sb:
        return False
    return not (sa == sb or is_suffix(sa, sb) or is_suffix(sb, sa))


def static_cells(m, mu, s):
    """A1-A4：返回 [(格号, 是否过, 事实描述)]。断言被破时描述里的两个值就是违例证据。"""
    cells = []
    cells.append(("A1", families_disjoint(m["base_suffix"], mu["data_dir"]),
                  "mcpcf 默认目录后缀（%s）与主库 data_dir（%s）段族不相交"
                  % (m["base_suffix"], mu["data_dir"])))
    cells.append(("A2", families_disjoint(m["fallback"], mu["data_dir"]),
                  "mcpcf 回退目录（%s）与主库 data_dir（%s）段族不相交"
                  % (m["fallback"], mu["data_dir"])))
    cells.append(("A3", m["db_name"] != s["default_db"],
                  "mcpcf 库名（%s）≠ 主库默认库名（%s）" % (m["db_name"], s["default_db"])))
    cells.append(("A4", m["override_key"] != s["env_key"] and m["base_key"] != s["env_key"],
                  "mcpcf env 键（%s/%s）与主库 env 键（%s）互不相同"
                  % (m["override_key"], m["base_key"], s["env_key"])))
    return cells


# ---------------------------------------------------------------- 碰撞格（纯函数）

def sandbox_db_path(m, env):
    """按 mcpcf_embed.mbt 的字面拼接镜像沙箱库路径：
    覆盖键原样采用（真源 Some(d) => d，不 trim）> 基底键 + 基底后缀 > 回退目录；再拼库名后缀。"""
    if m["override_key"] in env:
        d = env[m["override_key"]]
    elif m["base_key"] in env:
        d = env[m["base_key"]] + m["base_suffix"]
    else:
        d = m["fallback"]
    return d + m["db_suffix"]


def normalize_path(p, cwd):
    return os.path.normcase(os.path.normpath(os.path.join(cwd, p)))


def collision_cell(m, s, env, cwd):
    """返回 (status, detail)，status ∈ skip/clean/hit。
    未设置 ⇒ 空过但明说（不许静默）；trim 按真源事实；命中 ⇒ 点名两条路径。"""
    key = s["env_key"]
    raw = env.get(key)
    if raw is None:
        return ("skip", "%s 未设置，碰撞格空过" % key)
    val = raw.strip() if s["trim"] else raw
    if not val:
        return ("skip", "%s 为空/纯空白，视同未设置，碰撞格空过" % key)
    sandbox = sandbox_db_path(m, env)
    a = normalize_path(val, cwd)
    b = normalize_path(sandbox, cwd)
    if a == b:
        return ("hit", "碰撞：%s=%r 与 mcpcf 沙箱库 %r 归一后同为 %s —— 两条路径家族相交，熔断状态会跨时基混写"
                % (key, raw, sandbox, a))
    return ("clean", "%s=%r → %s；mcpcf 沙箱库 %r → %s；不同文件" % (key, raw, a, sandbox, b))


# ---------------------------------------------------------------- 主面

def run(root, env, cwd):
    """现读三份真源 → 基线事实 → A1-A4 静态断言 + C1 碰撞格。逐格打印 verdict，返回 rc。
    root/env/cwd 全部显式传入（自检用 temp 夹具驱动同一调用面，不读仓库现状）。"""
    specs = [
        ("mcpcf", os.path.join(root, "src", "server", "mcpcf_embed.mbt"), parse_mcpcf),
        ("multi", os.path.join(root, "src", "store", "multi_store.mbt"), parse_multi),
        ("sqlite", os.path.join(root, "src", "store", "store_sqlite.mbt"), parse_sqlite),
    ]
    facts = {}
    for _label, path, parser in specs:
        try:
            with io.open(path, encoding="utf-8-sig") as fh:
                text = fh.read()
        except (OSError, ValueError) as e:
            print("REFUSE 真源读不到：%s（%s）⇒ 基线不可读，无法自证，不给绿（rc=2）" % (path, e))
            return 2
        if not text.strip():
            print("REFUSE 真源为空：%s ⇒ 基线不可读，无法自证，不给绿（rc=2）" % path)
            return 2
        parsed = parser(text)
        if parsed is None:
            print("REFUSE 真源解析不出关键事实：%s（形状漂移或键缺失）⇒ 无法自证，不给绿（rc=2）" % path)
            return 2
        facts[_label] = parsed
    m, mu, s = facts["mcpcf"], facts["multi"], facts["sqlite"]
    print("基线事实（现读真源，不抄副本）：")
    print("  mcpcf 库名 = %s（%d 处拼接一致）" % (m["db_name"], m["db_sites"]))
    print("  mcpcf 目录 = %s 覆盖 > %s + %s > %s"
          % (m["override_key"], m["base_key"], m["base_suffix"], m["fallback"]))
    print("  主库 data_dir 默认 = %s；ns 库形状 = <data_dir>/<%s>.db" % (mu["data_dir"], mu["ns_var"]))
    print("  主库默认库名 = %s；主库 env 键 = %s（首尾 trim = %s）"
          % (s["default_db"], s["env_key"], s["trim"]))
    bad = 0
    cells = static_cells(m, mu, s)
    for cid, ok, detail in cells:
        print("[%s] %s %s" % (cid, "PASS" if ok else "FAIL 断言被破", detail))
        if not ok:
            bad += 1
    status, detail = collision_cell(m, s, env, cwd)
    if status == "skip":
        print("[C1] SKIP %s" % detail)
    elif status == "clean":
        print("[C1] PASS %s" % detail)
    else:
        print("[C1] FAIL %s" % detail)
        bad += 1
    if bad:
        print("FAIL 汇总：%d 格红 —— mcpcf 沙箱库与主库路径隔离被破（BUG-583 方向④）" % bad)
        return 1
    note = "碰撞格空过" if status == "skip" else "碰撞格过（两路径不同文件）"
    print("PASS 汇总：静态 %d/%d 过，%s —— mcpcf 沙箱库与主库默认路径隔离成立（BUG-583 方向④）"
          % (len(cells), len(cells), note))
    return 0


# ---------------------------------------------------------------- 自检（全合成夹具）

# 夹具镜像真源形状（MoonBit 源码里的 "\\" 是转义，文件文本就是两个反斜杠字符）。
MCPCF_FIX = r'''
fn ops_data_dir() -> String {
  match @env.get_env_var("MCPCONFTEST_DATA_DIR") {
    Some(d) => d
    None =>
      match @env.get_env_var("LOCALAPPDATA") {
        Some(base) => base + "\\mcpconftest\\data"
        None => "./mcpconftest-data"
      }
  }
}
fn ensure_engine() {
  let dir = ops_data_dir()
  let db_path = dir + "\\mcpconftest-ops.db"
  ()
}
fn elsewhere(d : String) {
  let db_path = d + "\\mcpconftest-ops.db"
  m.set("db", Json::string(ops_data_dir() + "\\mcpconftest-ops.db"))
}
'''

MULTI_FIX = r'''
pub fn MultiStore::new(data_dir~ : String = ".fist-mbt/data") -> MultiStore {
  ()
}
pub fn MultiStore::get(self : MultiStore, ns : String) {
  let safe = ns
  let path = "\{self.data_dir}/\{safe}.db"
  ()
}
'''

SQLITE_FIX = r'''
let default_db_path : String = "fist-mbt.db"
pub fn SqliteStore::db_path_from_env(env_value : String?) -> String {
  match env_value {
    Some(p) => {
      let t = p.trim().to_owned()
      if t.is_empty() { default_db_path } else { t }
    }
    None => default_db_path
  }
}
pub fn SqliteStore::default_db_path() -> String {
  SqliteStore::db_path_from_env(@env.get_env_var("FIST_DB_PATH"))
}
'''


def _write_fixture(path, text):
    with io.open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def _make_tree(d, mcpcf=MCPCF_FIX, multi=MULTI_FIX, sqlite=SQLITE_FIX):
    """在 temp 根下铺三份真源夹具；某份传 None = 不落盘（考读不到自拒）。"""
    os.makedirs(os.path.join(d, "src", "server"), exist_ok=True)
    os.makedirs(os.path.join(d, "src", "store"), exist_ok=True)
    if mcpcf is not None:
        _write_fixture(os.path.join(d, "src", "server", "mcpcf_embed.mbt"), mcpcf)
    if multi is not None:
        _write_fixture(os.path.join(d, "src", "store", "multi_store.mbt"), multi)
    if sqlite is not None:
        _write_fixture(os.path.join(d, "src", "store", "store_sqlite.mbt"), sqlite)


def _capture_run(d, env):
    """驱动真调用面 run()（判例-29：机制格必须走实现路径，不是另写一份判定）。"""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = run(d, env, d)
    return rc, buf.getvalue()


def build_parser():
    """argparse：未知旗标天生拒绝（SystemExit 2）。已知旗标只有 --selftest。"""
    ap = argparse.ArgumentParser(
        description="BUG-583 方向④：mcpcf 沙箱库路径与主库路径隔离断言（真源现读）")
    ap.add_argument("--selftest", action="store_true",
                    help="合成夹具自检（含变异对照），不读仓库现状")
    return ap


def print_selftest(fails, executed):
    if fails:
        print("SELFTEST FAIL: %d/%d 格红" % (len(fails), len(executed)))
        for n, det in fails:
            print("  - %s%s" % (n, ("：%s" % det)[:400] if det else ""))
        return 1
    fams = {}
    for n in executed:
        head = n.split("-")[0].rstrip("0123456789")
        fams[head] = fams.get(head, 0) + 1
    desc = " / ".join("%s×%d" % (k, v) for k, v in sorted(fams.items()))
    print("SELFTEST OK: %d 格（反解：%s，族名取自已执行格子名首段的字母，不手写计数）"
          % (len(executed), desc))
    return 0


def selftest():
    """全合成：P 解析 / S 静态变异 / C 碰撞 / E 端到端（temp 树驱动真 run()）/ A 旗标面。
    不读仓库现状面 —— 现状对表归主面（hermetic 纪律）。"""
    fails, executed, made = [], [], []

    def cell(name, ok, detail=""):
        executed.append(name)
        if not ok:
            fails.append((name, detail))

    def tmp():
        d = tempfile.mkdtemp(prefix="g191p-")
        made.append(d)
        return d

    m = parse_mcpcf(MCPCF_FIX)
    mu = parse_multi(MULTI_FIX)
    s = parse_sqlite(SQLITE_FIX)

    # ── P 族：解析器从夹具形状里读出的事实必须与真源同构 ──
    cell("P1-mcpcf-facts-live-parsed",
         m == {"db_name": "mcpconftest-ops.db", "db_suffix": "\\mcpconftest-ops.db",
               "override_key": "MCPCONFTEST_DATA_DIR", "base_key": "LOCALAPPDATA",
               "base_suffix": "\\mcpconftest\\data", "fallback": "./mcpconftest-data",
               "db_sites": 3}, repr(m))
    cell("P2-multi-facts-live-parsed",
         mu == {"data_dir": ".fist-mbt/data", "ns_var": "safe"}, repr(mu))
    cell("P3-sqlite-facts-live-parsed",
         s == {"default_db": "fist-mbt.db", "env_key": "FIST_DB_PATH", "trim": True}, repr(s))
    cell("P4-mcpcf-empty-or-garbage-refused",
         parse_mcpcf("") is None and parse_mcpcf("not moonbit") is None)
    cell("P5-multi-empty-or-garbage-refused",
         parse_multi("") is None and parse_multi("not moonbit") is None)
    cell("P6-sqlite-empty-or-garbage-refused",
         parse_sqlite("") is None and parse_sqlite("not moonbit") is None)

    # ── S 族：静态断言的变异对照 —— 每格改一个判据真在读的键，必须红 ──
    base = static_cells(m, mu, s)
    cell("S1-clean-facts-all-static-green", all(ok for _, ok, _ in base), repr(base))

    def only_red(cells, cid):
        return [c for c, ok, _ in cells if not ok] == [cid]

    m2 = dict(m, db_name="fist-mbt.db")
    cell("S2-mutated-db-name-equals-main-red",
         only_red(static_cells(m2, mu, s), "A3"), repr(static_cells(m2, mu, s)))
    m3 = dict(m, fallback=".fist-mbt/data")
    cell("S3-mutated-fallback-into-main-red",
         only_red(static_cells(m3, mu, s), "A2"), repr(static_cells(m3, mu, s)))
    m4 = dict(m, base_suffix=".fist-mbt/data")
    cell("S4-mutated-base-suffix-equals-main-red",
         only_red(static_cells(m4, mu, s), "A1"), repr(static_cells(m4, mu, s)))
    m5 = dict(m, override_key="FIST_DB_PATH")
    cell("S5-mutated-env-key-collision-red",
         only_red(static_cells(m5, mu, s), "A4"), repr(static_cells(m5, mu, s)))
    m6 = dict(m, base_suffix="sub\\.fist-mbt\\data")
    cell("S6-mutated-base-suffix-contains-main-red",
         only_red(static_cells(m6, mu, s), "A1"), repr(static_cells(m6, mu, s)))

    # ── C 族：碰撞格（纯函数面）。路径用字面反斜杠拼接，跨平台同形 ──
    st, det = collision_cell(m, s, {}, "cwd")
    cell("C1-unset-skip-explicit-message",
         st == "skip" and det == "FIST_DB_PATH 未设置，碰撞格空过", repr((st, det)))
    st, det = collision_cell(m, s, {"FIST_DB_PATH": "   "}, "cwd")
    cell("C2-whitespace-skip-explicit-message",
         st == "skip" and "视同未设置" in det, repr((st, det)))
    env_hit = {"LOCALAPPDATA": "C:\\base",
               "FIST_DB_PATH": "C:\\base\\mcpconftest\\data\\mcpconftest-ops.db"}
    st, det = collision_cell(m, s, env_hit, "cwd")
    # 消息按 %r 点名两条路径（repr 转义反斜杠、让尾随空白可见 —— 与 trim 事实同源，
    # C4 的尾随空格证据靠它）⇒ 断言必须按 repr 形逐字匹配，拿裸串做子串永远失配
    # （R192 修：旧断言用裸串，是夹具期望与消息文法不一致，不是判据松）。
    # 两条路径各独立取：一条是 env 原值，一条按 mcpcf 事实镜像拼接；再独立重算归一路径，
    # 锁「归一后同文件」这一事实 —— 比旧断言更严，不是更松。
    sandbox_mirror = env_hit["LOCALAPPDATA"] + m["base_suffix"] + m["db_suffix"]
    norm_hit = os.path.normcase(os.path.normpath(os.path.join("cwd", env_hit["FIST_DB_PATH"])))
    cell("C3-exact-collision-hit-names-both",
         st == "hit" and repr(env_hit["FIST_DB_PATH"]) in det
         and repr(sandbox_mirror) in det and norm_hit in det and "碰撞" in det,
         repr((st, det)))
    env_sp = dict(env_hit, FIST_DB_PATH=env_hit["FIST_DB_PATH"] + "  ")
    st, det = collision_cell(m, s, env_sp, "cwd")
    cell("C4-trailing-space-collision-hit", st == "hit", repr((st, det)))
    st, det = collision_cell(m, s, {"FIST_DB_PATH": "C:\\other\\main.db"}, "cwd")
    cell("C5-different-file-clean", st == "clean", repr((st, det)))

    # ── E 族：端到端 —— temp 树驱动真 run()，锁接线（判例-29）与四档退出码 ──
    d1 = tmp()
    _make_tree(d1)
    rc, out = _capture_run(d1, {})
    cell("E1-clean-tree-green-with-skip-message",
         rc == 0 and "FIST_DB_PATH 未设置，碰撞格空过" in out and "PASS 汇总" in out,
         repr((rc, out[-200:])))

    d2 = tmp()
    _make_tree(d2)
    rc, out = _capture_run(d2, env_hit)
    # 与 C3 同口径：run() 透传碰撞消息的 %r 形点名 ⇒ 按 repr 形匹配；
    # 另钉 [C1] FAIL —— 红必须落在碰撞格本尊，不是别的格借来的红（R192 收紧）。
    cell("E2-collision-env-red-through-run",
         rc == 1 and repr(env_hit["FIST_DB_PATH"]) in out
         and "[C1] FAIL" in out and "FAIL 汇总" in out,
         repr((rc, out[-200:])))

    d3 = tmp()
    _make_tree(d3, mcpcf=MCPCF_FIX.replace("mcpconftest-ops.db", "fist-mbt.db"))
    rc, out = _capture_run(d3, {})
    cell("E3-db-name-mutated-tree-red", rc == 1 and "[A3] FAIL" in out, repr((rc, out[-200:])))

    d4 = tmp()
    # 变异必须保住 "./" 形状锚（parse_mcpcf 的回退正则只认 ./ 前缀字面量）：
    # "./.fist-mbt/data" 仍可解析，但段族与主库 data_dir 相等 ⇒ A2 必红（rc=1）。
    # R192 修：旧变异 '".fist-mbt/data"' 剥掉前缀 ⇒ 真源解析不出 ⇒ 判据正确自拒 rc=2 ——
    # 那是 E8 的领地（不可解析 ⇒ REFUSE）；本格的职责是「可解析但违例 ⇒ 红」，
    # 两档不许混。变异点落在夹具代码行（该字面量全文仅 1 处，非注释，判例-30）。
    _make_tree(d4, mcpcf=MCPCF_FIX.replace('"./mcpconftest-data"', '"./.fist-mbt/data"'))
    rc, out = _capture_run(d4, {})
    cell("E4-fallback-mutated-tree-red", rc == 1 and "[A2] FAIL" in out, repr((rc, out[-200:])))

    d5 = tmp()
    _make_tree(d5, multi=None)
    rc, out = _capture_run(d5, {})
    cell("E5-missing-source-self-refuse", rc == 2 and "REFUSE" in out, repr((rc, out[-200:])))

    d6 = tmp()
    _make_tree(d6, mcpcf="")
    rc, out = _capture_run(d6, {})
    cell("E6-empty-source-self-refuse", rc == 2 and "REFUSE" in out, repr((rc, out[-200:])))

    d7 = tmp()
    _make_tree(d7)
    env_ov = {"MCPCONFTEST_DATA_DIR": d7, "FIST_DB_PATH": d7 + "\\mcpconftest-ops.db"}
    rc, out = _capture_run(d7, env_ov)
    cell("E7-override-dir-collision-red", rc == 1 and "[C1] FAIL" in out, repr((rc, out[-200:])))

    d8 = tmp()
    _make_tree(d8, mcpcf="this is not moonbit source")
    rc, out = _capture_run(d8, {})
    cell("E8-garbage-source-self-refuse", rc == 2 and "REFUSE" in out, repr((rc, out[-200:])))

    # ── A 族：旗标面（argparse 天生拒绝未知旗标）──
    try:
        build_parser().parse_args(["--bogus"])
        cell("A1-unknown-flag-rejected", False, "未知旗标没有被拒")
    except SystemExit as e:
        cell("A1-unknown-flag-rejected", e.code == 2, repr(e.code))
    a = build_parser().parse_args([])
    b = build_parser().parse_args(["--selftest"])
    cell("A2-known-flags-parsed", a.selftest is False and b.selftest is True)

    for d in made:
        shutil.rmtree(d, ignore_errors=True)
    return print_selftest(fails, executed)


def main(argv=None):
    a = build_parser().parse_args(argv)
    if a.selftest:
        return selftest()
    return run(ROOT, dict(os.environ), os.getcwd())


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001 — 尺子自己坏了走 4 号档，绝不冒用 1
        print("FATAL 尺子自己坏了：%r" % e)
        sys.exit(4)