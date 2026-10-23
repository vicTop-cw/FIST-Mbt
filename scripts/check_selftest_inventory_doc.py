#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""scripts/check_selftest_inventory_doc.py — 「格子计数自述 ↔ 已执行格子反解」对表守卫（R104）。

**为什么要有它**（实测驱动，2026-10-22）：本仓的自证纪律是「`--selftest` 的格子清单从**已执行格子反解**，
不手写计数」——`check_release_asset_names.py` 就把自己的清单打成 `清单从已执行格子反解：R1×2 / R2 / … / R14×5`。
可是**文档抄的是另一份手数字**。本轮 R103 给它的 R9 加了三格（`R9×2` → `R9×5`），实现面自己改了读数，
而 `scripts/README.md` 里那行是我**手工记得**去改的——改之前它写着 `十九格（R9×2）`，与真源差三格。
实现会自证，文档不会。文档落后之后，下一位读者按「十九格」判断覆盖面，多出来的三格（新 workflow 摘导出行 /
合成 workflow 不误红 / 空面必自拒）就永远没人知道存在。
这与 `check_doc_surface` 的 J10 同族但**不是同一条尺**：J10 比「J1-JN 判据编号范围」（族在不在），
本尺比「每族几格 + 一共几格」（量对不对），判据面互不重叠（J9 的歧义键分工口径）。

**判定面（逐条点名）**：
  X1 计数漂移 = 文档写 `R族×n`，实现清单同族不是 n。
  X2 幻影族   = 文档写了某族的格数，实现清单里这一族一格都没跑。
  X3 总数滞后 = 文档在清单前自述「N 格 / N 支」（阿拉伯或中文数字），而 N != 该脚本被对表族数的合计
                —— 逼的是「一份文档只留一份权威清单」：分批写的读数（十七格 / 二十一格）必然落后于已执行格子。
  X4 自述失联 = 文档对该脚本有族计数自述，但跑它的 `--selftest` 拿不到「反解」清单（脚本不在 / 旗标不认 /
                超时 / 清单文法改了 / 自检本身红）⇒ 判据**无法自证**，走 2 号档，不冒用 1。
  X5 抄本打架 = 同一把尺在 README 里有两份**读数不同**的同族自述（实测 `scripts/README.md` 把整份条目列表
                重复了 7 遍，R104 只改了其中一份 ⇒ 6 份仍写 `十七格（R9×2)`. 逐份并入才有这一眼）。
**口径为什么这么窄（三条都是实测逼出来的，不是偷懒）**：
  ① 判定面只取 `scripts/README.md` 的 `- \`xxx.py\` — …` 条目语法：族名到脚本的归属必须机械可定。
     `AGENTS.md` 里 `十四格 R1×2/R2/…` 写在一条几百字的散文行中间，一行点了十几把尺的名字，
     「最近的前一个反引号文件名」这类启发式会把账记到错的尺上——**假红比漏红更坏**，AGENTS 面本轮不入
     （后续建议：先把归属做成机械可定再扩）。
  ② 只认**带「格/支」计数单位的那一行**里、ASCII 斜杠分隔、**至少两族**、每族名 ≤3 个大写字母、且至少一族
     带 `×数` 的清单。实测 `scripts/README.md:85` 的 `R42 记的 R1×1+R2×7` 是**校准读数**（每族找到几条违例，
     `+` 分隔、单族）；`（R9×5：release.yml 两支变异…）`这种**单族**写法同样不算清单（一份权威清单就该是一份
     斜杠名单）；`cli_flag_probe.py` 的 `（R1 版本旗被当未知 / R2 未知回 0 …）` 是裸族名单没有 `×`。三类都必须
     解析成 0 条自述，否则文档写「某族找到 7 条」就被当格数判红。
     族名从 `R\d+` 泛到 `[A-Z]{1,3}\d*`（R105）是因为 `check_backlog_status_staleness.py` 的格子族叫
     `V/R/M/P`（按已执行格子名的首段首字母反解），不是 `R族`；泛化带来的形状必须被挡：`PASS / FAIL×2 / OK`
     这类大写词组靠**词界**（前后不接字母数字）+ **名长 ≤3** 挡掉，`P0×2 / P1` 这类优先级缩写靠 `NOISE` 挡掉。
  ③ 实现面必须自带「反解」锚点。没锚点的守卫不进判定面——本尺不逼所有尺改成反解格式（那是另一件事），
     只锁「写了反解清单的尺 ↔ 抄了那份清单的文档」。
  ④ **本尺不自判**（R105）：判定面里出现自己 ⇒ `run_inventory` 会 `python 本文件 --selftest`，而它的自检行里
     就带着自己的清单 ⇒ 尺子查自己 = 每次跑都递归生一 subprocess 层。README 里本尺的条目**永不进判定面**，
     自锁跳过份数写进判定面读数（藏起来不算锁）。

用法：
  python scripts/check_selftest_inventory_doc.py                 # 对表（裸跑即可进电池）
  python scripts/check_selftest_inventory_doc.py --selftest      # 尺子先证明自己会红
  python scripts/check_selftest_inventory_doc.py --show-face     # 只打印判定面（哪把尺、几条自述）
退出码：0=判定面全部对表通过 / 1=X1|X2|X3 违例在场（逐条点名）/ 2=判据无法自证（X4 失联、README 读不到、
判定面为空＝什么都没测到）/ 4=尺子自己坏了（未捕获异常，绝不冒用 1）。
"""
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join("scripts", "README.md")
SELF = os.path.basename(os.path.abspath(__file__))
# 一条「族计数自述」= 带「格/支」的那一行里、ASCII 斜杠分隔、至少两族、每族名 ≤3 大写字母、且至少一族带 ×数。
UNIT_RE = re.compile(r"[格支]")
CLAIM_RE = re.compile(r"(?<![A-Za-z0-9])([A-Z]{1,3}\d*(?:×\d+)?(?:\s*/\s*[A-Z]{1,3}\d*(?:×\d+)?)+)(?![A-Za-z0-9])")
TOKEN_RE = re.compile(r"^([A-Z]{1,3})(\d*)(?:×(\d+))?$")
# 不是格子族名的大写缩写（优先级/技术名）——名字落在这里的整条清单不算自述。
NOISE = {"AI", "API", "CI", "CD", "CPU", "DB", "DNS", "ID", "IO", "JS", "KB", "LLM", "LRU", "MD",
         "MR", "OS", "P0", "P1", "P2", "P3", "PS", "SDK", "SLA", "TTL", "UI", "UX", "WC", "OK"}
TOTAL_RE = re.compile(r"([0-9]+|[零一二两三四五六七八九十百]+)\s*[格支][^0-9R]{0,8}$")
CN_DIGITS = {"零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5,
             "六": 6, "七": 7, "八": 8, "九": 9, "十": 10, "百": 100}
BULLET_RE = re.compile(r"(?m)^- `([A-Za-z0-9_.\-]+\.py)`")
ANCHOR = "反解"
TIMEOUT = 180


def fam_sort(key):
    """族名排序键：先按字母段再按数字段（`R2` 在 `R10` 前，`V` 与 `R1` 混排也稳）。"""
    m = re.match(r"([A-Z]+)(\d*)$", key)
    return (m.group(1), int(m.group(2) or 0)) if m else (key, 0)


def cn_num(text):
    """中文数字 -> int（够用档：十/十四/二十一/三十八/一百零五）。解析不出返回 None。"""
    if text.isdigit():
        return int(text)
    if not all(ch in CN_DIGITS for ch in text):
        return None
    if len(text) == 1:
        return CN_DIGITS[text]
    if "百" in text:
        head, rest = text.split("百", 1)
        val = CN_DIGITS.get(head, 1) * 100
        if not rest:
            return val
        if rest.startswith("零"):
            return val + (CN_DIGITS.get(rest[1:], 0) if len(rest) > 1 else 0)
        tail = cn_num(rest)
        return val + (tail if tail is not None else 0)
    if text.startswith("十"):
        return 10 + (CN_DIGITS.get(text[1:], 0) if len(text) > 1 else 0)
    if "十" in text:
        hi, lo = text.split("十", 1)
        return CN_DIGITS.get(hi, 1) * 10 + (CN_DIGITS.get(lo, 0) if lo else 0)
    return None


def parse_claims(text):
    """抽「族计数自述」：返回 ({族: 格数}, [(族, 格数, 原文)], [(总数, 原文)])。

    裸族（清单里不带 ×数）按 1 格计，但**只有**同一清单里出现了 ×数才算清单；全裸名单返回空。
    单位门在**行级**生效：一行没有「格/支」就不可能在这行里抽到清单。
    """
    claims = {}
    detail = []
    totals = []
    for line in (text or "").splitlines():
        if not UNIT_RE.search(line):
            continue
        for m in CLAIM_RE.finditer(line):
            run = m.group(1)
            parsed = []
            noisy = False
            for piece in run.split("/"):
                tm = TOKEN_RE.match(piece.strip())
                if not tm:
                    parsed = []
                    break
                fam = tm.group(1) + tm.group(2)
                if fam in NOISE:
                    noisy = True
                    break
                parsed.append((fam, None if tm.group(3) is None else int(tm.group(3))))
            if noisy or not parsed or all(n is None for _, n in parsed):
                continue
            for fam, n in parsed:
                cnt = 1 if n is None else n
                claims[fam] = cnt
                detail.append((fam, cnt, run))
            tm = TOTAL_RE.search(line[:m.start()][-24:])
            if tm:
                val = cn_num(tm.group(1))
                if val is not None:
                    totals.append((val, run))
    return claims, detail, totals


def doc_face(root=None):
    """判定面：README 里带族计数自述的条目 -> ({脚本: {claims, totals, missing}}, 说明, 自锁跳过名单)。"""
    path = os.path.join(root or ROOT, DOC)
    if not os.path.isfile(path):
        return None, "%s 读不到" % DOC, []
    text = io.open(path, encoding="utf-8-sig", errors="replace").read()
    marks = list(BULLET_RE.finditer(text))
    if not marks:
        return None, "%s 里一条 `- \\`xxx.py\\` —` 条目都没解析到（扫描面空转）" % DOC, []
    face = {}
    skipped = []
    for i, m in enumerate(marks):
        end = marks[i + 1].start() if i + 1 < len(marks) else len(text)
        if m.group(1) == SELF:
            # 自锁在解析之前：本尺的条目无论写没写清单都不进判定面，否则 run_inventory 会 spawn 自己。
            skipped.append(m.group(1))
            continue
        claims, _, totals = parse_claims(text[m.start():end])
        if not claims:
            continue
        script = os.path.join("scripts", m.group(1))
        rec = face.get(script)
        if rec is None:
            face[script] = {"claims": claims, "totals": totals, "dups": {},
                            "missing": not os.path.isfile(os.path.join(root or ROOT, script))}
            continue
        # 同名条目在本仓 README 里有 7 份抄本（实测）：逐份并入，族内出现两个不同读数就是「两份账」。
        for fam, cnt in claims.items():
            seen = rec["claims"].setdefault(fam, cnt)
            if seen != cnt:
                rec["dups"].setdefault(fam, [seen]).append(cnt)
        rec["totals"].extend(totals)
    return face, "条目 %d 份 / 带族计数自述 %d 份 / 自锁跳过本尺 %d 份" % (
        len(marks), len(face), len(skipped)), skipped


def run_inventory(script, root=None):
    """跑被对表尺的 `--selftest`，从「反解」锚点行抽实现清单。返回 (claims|None, 为什么)。"""
    path = os.path.join(root or ROOT, script)
    if not os.path.isfile(path):
        return None, "脚本不存在"
    try:
        r = subprocess.run([sys.executable, path, "--selftest"], capture_output=True,
                           text=True, encoding="utf-8", errors="replace",
                           cwd=root or ROOT, timeout=TIMEOUT)
    except Exception as e:  # noqa: BLE001 — 跑不动 = 无法自证，不外抛
        return None, "跑 --selftest 抛异常 %r" % e
    out = (r.stdout or "") + (r.stderr or "")
    if r.returncode != 0:
        return None, "--selftest 实回 rc=%d（自检本身红，清单无从对表）" % r.returncode
    anchor = [ln for ln in out.splitlines() if ANCHOR in ln]
    if not anchor:
        return None, "输出里没有「%s」锚点行（清单文法改了或从未反解）" % ANCHOR
    claims, _, _ = parse_claims(chr(10).join(anchor))
    if not claims:
        return None, "锚点行解析不出族计数：%s" % anchor[0][:60]
    return claims, ""


def judge(face, invs, whys=None):
    """核心对表。返回 (problems, unverifiable, notes)。"""
    problems = []
    unverifiable = []
    notes = []
    whys = whys or {}
    for script in sorted(face):
        rec = face[script]
        if rec.get("missing"):
            unverifiable.append("X4 %s 文档条目点名它，盘上没有这份脚本" % script)
            continue
        inv = invs.get(script)
        if inv is None:
            unverifiable.append("X4 %s 文档有 %d 条族计数自述，实现清单拿不到：%s"
                                % (script, len(rec["claims"]), whys.get(script, "未跑")))
            continue
        total = 0
        for fam in sorted(rec["claims"], key=fam_sort):
            dups = rec.get("dups", {}).get(fam)
            if dups:
                problems.append("X5 %s %s 族在文档里有 %s 两份不一致抄本（一份权威清单只该有一份）"
                                % (script, fam, " / ".join(str(v) for v in sorted(set(dups)))))
                continue
            want = rec["claims"][fam]
            got = inv.get(fam)
            if got is None:
                problems.append("X2 %s %s 文档自述 %d 格，实现清单里这一族一格都没跑（幻影族）"
                                % (script, fam, want))
            elif got != want:
                problems.append("X1 %s %s 文档自述 %d 格 != 实现反解 %d 格（计数漂移）"
                                % (script, fam, want, got))
            else:
                total += got
        if rec["totals"]:
            stated = sorted(set(v for v, _ in rec["totals"]))
            if len(stated) > 1 or stated[0] != total:
                problems.append("X3 %s 总数自述 %s 与实现反解合计 %d 格不符（一份文档只留一份权威清单）"
                                % (script, "/".join(str(v) for v in stated), total))
        notes.append("%s 判定族 %d / 实现反解族 %d / 对表合计 %d 格"
                     % (script, len(rec["claims"]), len(inv), sum(inv.values())))
    return problems, unverifiable, notes


def clean_fixture():
    """干净夹具：文档三族自述 + 总数 8，实现清单同数。"""
    claims = {"R1": 2, "R2": 1, "R9": 5}
    return {
        "face": {"scripts/x.py": {"claims": dict(claims),
                                  "totals": [(sum(claims.values()), "R1×2 / R2 / R9×5")],
                                  "missing": False}},
        "invs": {"scripts/x.py": dict(claims)},
    }


def selftest():
    """合成夹具：四类违例各有格抓住、两类文档形状不误判、失联/空面必自拒、真实现状面必须绿。"""
    fails = []
    executed = []

    def check(name, cond):
        executed.append(name)
        if not cond:
            fails.append(name)

    fx = clean_fixture()
    inv = dict(fx["invs"]["scripts/x.py"])

    p, u, _ = judge(fx["face"], fx["invs"])
    check("G1", not p and not u)

    face = {"scripts/x.py": {"claims": {"R1": 2, "R2": 1, "R9": 2},
                             "totals": [(5, "R1×2 / R2 / R9×2")], "missing": False}}
    p, _, _ = judge(face, {"scripts/x.py": inv})
    check("M1", any(x.startswith("X1") and "R9" in x for x in p))

    face = {"scripts/x.py": {"claims": {"R1": 2, "R2": 1, "R9": 5, "R15": 3},
                             "totals": [(11, "x")], "missing": False}}
    p, _, _ = judge(face, {"scripts/x.py": inv})
    check("M2", any(x.startswith("X2") and "R15" in x for x in p))

    face = {"scripts/x.py": {"claims": dict(inv), "totals": [(3, "x"), (9, "y")], "missing": False}}
    p, _, _ = judge(face, {"scripts/x.py": inv})
    check("M3", any(x.startswith("X3") for x in p))

    claims, _, totals = parse_claims("--selftest 八格（R1×2 / R2 / R9×5）")
    check("M3b", claims == inv and totals and totals[0][0] == 8)

    claims, _, _ = parse_claims("`check_mbti_sync` R42 记的 R1×1+R2×7 已由 R43 修真")
    check("M4", claims == {})

    claims, _, _ = parse_claims("--selftest 二十一格（R9×5：release.yml 两支变异 + 空面必自拒）")
    check("M4b", claims == {})

    claims, _, _ = parse_claims("--selftest 七格（R1 版本旗被当未知 / R2 未知回 0 / R4 缺臂）")
    check("M5", claims == {})

    claims, _, _ = parse_claims("SELFTEST FAIL: 4 格红 -> PASS / FAIL×2 / OK")
    check("M4c", claims == {})

    claims, _, _ = parse_claims("反解：十一格（V×3 / R×4 / M×2 / P×2）")
    check("M4d", claims == {"V": 3, "R": 4, "M": 2, "P": 2})

    claims, _, _ = parse_claims("优先级 P0×2 / P1 一共三格")
    check("M4e", claims == {})

    claims, _, _ = parse_claims("（R1×2 / R2 / R9×5）")
    check("M16", claims == {})

    tmp = tempfile.mkdtemp(prefix="inv-self-")
    try:
        os.makedirs(os.path.join(tmp, "scripts"))
        io.open(os.path.join(tmp, DOC), "w", encoding="utf-8").write(
            "- `%s` — 本尺条目自述：三格（Q1×2 / Q2）\n- `check_other.py` — 四格（Q1×2 / Q3×2）\n" % SELF)
        f2, why2, sk2 = doc_face(tmp)
        check("M15", list(f2) == [os.path.join("scripts", "check_other.py")]
              and sk2 == [SELF] and "自锁跳过" in why2)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    face = {"scripts/x.py": {"claims": dict(inv), "totals": [(8, "x")], "missing": False}}
    _, u, _ = judge(face, {"scripts/x.py": None}, {"scripts/x.py": "没有锚点行"})
    check("M6", any(x.startswith("X4") and "锚点" in x for x in u))

    face = {"scripts/x.py": {"claims": dict(inv), "totals": [(8, "x")], "missing": True}}
    _, u, _ = judge(face, {})
    check("M7", any(x.startswith("X4") for x in u))

    rc = main([], fixture=({}, {}, {}))
    check("M8", rc == 2)

    rc = main([], fixture=({"scripts/x.py": {"claims": {}, "totals": [], "missing": False}}, {}, {}))
    check("M9", rc == 2)

    face = {"scripts/x.py": {"claims": {"R9": 2}, "totals": [(2, "x")], "missing": False}}
    rc = main([], fixture=(face, {"scripts/x.py": inv}, {}))
    check("M10", rc == 1)

    face = {"scripts/x.py": {"claims": dict(inv), "totals": [(99, "x")], "missing": False}}
    _, u, _ = judge(face, {"scripts/x.py": None}, {"scripts/x.py": "没有锚点行"})
    check("M11", u and u[0].startswith("X4"))

    face = {"scripts/x.py": {"claims": dict(inv), "totals": [(8, "x")], "missing": False}}
    rc = main([], fixture=(face, {"scripts/x.py": None}, {"scripts/x.py": "跑不动"}))
    check("M12", rc == 2)

    face = {"scripts/x.py": {"claims": {"R1": 2, "R9": 5}, "totals": [(8, "x")], "missing": False,
                             "dups": {"R9": [2, 5]}}}
    p, _, _ = judge(face, {"scripts/x.py": inv})
    check("M18", any(x.startswith("X5") and "R9" in x for x in p))

    face = {"scripts/x.py": {"claims": {"R1": 2, "R9": 5}, "totals": [(7, "x")], "missing": False,
                             "dups": {}}}
    p, _, _ = judge(face, {"scripts/x.py": inv})
    check("M19", not any(x.startswith("X5") for x in p))

    real, why, skipped_real = doc_face()
    if not real:
        check("M13", False)
        fails.append("M13 真 README 解析不出判定面：%s" % why)
    else:
        check("M13", bool(real))
        check("M17", SELF not in [os.path.basename(p) for p in real] and SELF in skipped_real)
        rc = main([])
        check("M14", rc == 0)
        if rc != 0:
            fails.append("M14 真实现状面不绿：rc=%d（判定面 %s）" % (rc, sorted(real)))

    return fails, executed


def fatal(msg):
    """判据无法自证 -> **真给 2**（写 stderr，由 `sys.exit(main())` 落成；串式 SystemExit 实给 1，BUG-369）。"""
    sys.stderr.write("FATAL: %s\n" % msg)
    return 2


def main(argv=None, fixture=None):
    args = list(argv if argv is not None else sys.argv[1:])
    if "--selftest" in args:
        fails, executed = selftest()
        fam = {}
        for name in executed:
            key = re.match(r"[A-Za-z]+", name)
            fam[key.group(0) if key else name] = fam.get(key.group(0) if key else name, 0) + 1
        inv = " / ".join("%s×%d" % (k, v) if v > 1 else k
                         for k, v in sorted(fam.items(), key=lambda kv: (kv[0][0], kv[0])))
        if fails:
            print("SELFTEST FAIL: %d/%d 格红 -> %s" % (len(fails), len(executed), " | ".join(fails)))
            return 1
        print("SELFTEST OK: %d 格（清单从已执行格子反解：%s）" % (len(executed), inv))
        return 0

    if fixture is not None:
        face, invs, whys = fixture
        why = "夹具"
    else:
        face, why, _ = doc_face()
        invs = None

    if face is None:
        return fatal(why)
    if "--show-face" in args and fixture is None:
        print("判定面：%s" % why)
        for script in sorted(face):
            print("  %s :: %d 条族计数自述" % (script, len(face[script]["claims"])))
        return 0
    if not face or not any(v["claims"] for v in face.values()):
        return fatal("判定面里一条族计数自述都没有（%s）——判据空转不报绿" % why)

    if invs is None:
        invs = {}
        whys = {}
        for script in sorted(face):
            if face[script]["missing"]:
                invs[script] = None
                continue
            claims, note = run_inventory(script)
            invs[script] = claims
            whys[script] = note

    problems, unverifiable, notes = judge(face, invs, whys)
    print("判定面=%s | 待对表尺 %d 份" % (DOC if fixture is None else "夹具", len(face)))
    for line in notes:
        print("  对表 %s" % line)
    for line in problems:
        print("  违例 %s" % line)
    for line in unverifiable:
        print("  无法自证 %s" % line)
    if unverifiable:
        return fatal("X4 自述失联 %d 处（文档抄着数、实现给不出清单）：" % len(unverifiable)
                     + " || ".join(unverifiable))
    if problems:
        print("INVENTORY_SYNC=violate 违例 %d 条" % len(problems))
        return 1
    print("INVENTORY_SYNC=clean 判定族 %d 条逐一对表通过"
          % sum(len(v["claims"]) for v in face.values()))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001 — 尺子自己坏了 -> 真给 4，绝不冒用 1（判据红）
        sys.stderr.write("RULER BROKEN: %r\n" % e)
        sys.exit(4)
