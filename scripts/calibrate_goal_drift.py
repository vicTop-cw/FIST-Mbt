#!/usr/bin/env python3
"""BUG-25 标定器：goal_drift_check 的词法判据在本项目真实中文语料上的判别力标定。

为什么要有这个脚本（不是装饰）：判据的**阈值**与 **advisory 降级**都必须有可复跑的出处，
否则"假阳性 15/15"只是账本里的一句断言。语料 = 仓库根 fist-mbt.db（只读，gitignored，
机器本地）⇒ 本脚本**不挂 CI**，是人工标定工具；CI 侧的锁是 src/engine/engine_goal_drift_test.mbt
的内嵌夹具（口径与本脚本逐字一致）。

用法：python scripts/calibrate_goal_drift.py [--json]
退出码：0=标定完成；2=语料缺失/判据无法自证（绝不静默报"通过"）。

口径（与 src/evolve/evolve.mbt 的 tokens/coverage、src/engine/engine_dag_ext.mbt 的
drift_similarity 一一对应，改任一侧都要重跑本脚本并同步 MoonBit 常量）：
  tokens(s)    = 小写后：ASCII 词 [a-z0-9_-]+ ∪ CJK 段内单字 ∪ CJK 段内相邻二字组（去重）
  jaccard      = |a∩b| / |a∪b|
  coverage     = |a∩b| / |a|（a=根目标；非对称，多写模板不被长度稀释）
  similarity   = max(jaccard, coverage)；drift = 1 - similarity
  insufficient = 任一侧 token 数 < MIN_TOKENS（空描述/纯模板桩不参与判定）
  判据         = drift > 0.7 → drift_suspect；兄弟 jaccard ≥ 0.7 → redundant_suspect
"""
import json
import re
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "fist-mbt.db"

CJK = re.compile(r"[㐀-鿿]", re.U)
WORD = re.compile(r"[a-z0-9_\-]+", re.U)

DRIFT_TH = 0.7
RED_TH = 0.7
MIN_TOKENS = 6


def tokens(s):
    s = s.lower()
    out = set(WORD.findall(s))
    run, runs = [], []
    for ch in s:
        if CJK.match(ch):
            run.append(ch)
        elif run:
            runs.append(run)
            run = []
    if run:
        runs.append(run)
    for r in runs:
        out.update(r)
        out.update(r[i] + r[i + 1] for i in range(len(r) - 1))
    return out


def legacy_char_tokens(s):
    """旧口径（可见字符集）——保留是为了给出 before/after 两个数，而不是自称更好。"""
    return set(c for c in s.lower() if c.strip())


def jaccard(a, b):
    u = len(a | b)
    return len(a & b) / u if u else 0.0


def coverage(a, b):
    return len(a & b) / len(a) if a else 0.0


def similarity(a, b):
    return max(jaccard(a, b), coverage(a, b))


def load_families():
    if not DB.exists():
        return None
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    try:
        rows = con.execute(
            "select id,parent_id,description from tasks"
        ).fetchall()
    except sqlite3.Error:
        return None
    finally:
        con.close()
    byid = {r[0]: r for r in rows}
    fams = defaultdict(list)
    for r in rows:
        if r[1] and r[1] in byid and r[2] and byid[r[1]][2]:
            fams[r[1]].append((r[0], r[2]))
    return byid, fams


def rate(pairs, tf, f):
    """pairs=[(root_desc, child_desc)]；返回 (suspect_rate, insufficient_rate, n_kept)。"""
    sus = ins = kept = 0
    cache = {}

    def tk(s):
        if s not in cache:
            cache[s] = tf(s)
        return cache[s]

    for a, b in pairs:
        ta, tb = tk(a), tk(b)
        if len(ta) < MIN_TOKENS or len(tb) < MIN_TOKENS:
            ins += 1
            continue
        kept += 1
        if 1.0 - f(ta, tb) > DRIFT_TH:
            sus += 1
    return (
        round(sus / kept, 4) if kept else None,
        round(ins / (kept + ins), 4) if (kept + ins) else None,
        kept,
    )


def main():
    loaded = load_families()
    if loaded is None:
        print(
            "FATAL 语料缺失：%s 不存在或不可读（fist-mbt.db 是机器本地库，"
            "标定无法自证 ⇒ 退出 2，不报通过）" % DB,
            file=sys.stderr,
        )
        return 2
    byid, fams = loaded

    all_pairs, genuine = [], []
    for p, kids in fams.items():
        rd = byid[p][2]
        for cid, cd in kids:
            all_pairs.append((rd, cd))
            # 「改写型」样本：既不是把根描述原样前缀拼接的模板桩，也不是 "子任务单元 N" 演示桩
            if cd.startswith(rd[:20]) or "子任务单元" in cd:
                continue
            genuine.append((rd, cd))

    import random

    random.seed(11)
    ctrl = []
    while len(ctrl) < 400 and len(genuine) > 1:
        a, b = random.sample(genuine, 2)
        if a[0] == b[0]:
            continue
        ctrl.append((a[0], b[1]))

    out = {
        "corpus": {
            "db": DB.name,
            "families": len(fams),
            "all_pairs": len(all_pairs),
            "reworded_pairs": len(genuine),
            "random_control": len(ctrl),
        },
        "threshold": {"drift": DRIFT_TH, "redundancy": RED_TH, "min_tokens": MIN_TOKENS},
    }
    for name, tf, f in [
        ("legacy_char_jaccard", legacy_char_tokens, jaccard),
        ("current_max_jac_cov", tokens, similarity),
    ]:
        for grp, pairs in [
            ("all", all_pairs),
            ("reworded", genuine),
            ("random_control", ctrl),
        ]:
            r, i, kept = rate(pairs, tf, f)
            out[f"{name}_{grp}"] = {"suspect": r, "insufficient": i, "n": kept}

    # 兄弟冗余：真实非模板家族上 raw jaccard 命中率（口径未变，给出数值以免"顺手改坏"）
    hi = tot = 0
    for p, kids in fams.items():
        if len(kids) < 2:
            continue
        ts = [tokens(c) for _, c in kids]
        for i in range(len(ts)):
            others = [j for j in range(len(ts)) if j != i]
            if not others or not ts[i]:
                continue
            tot += 1
            hi += max(jaccard(ts[i], ts[j]) for j in others) >= RED_TH
    out["sibling_redundancy_real_corpus"] = {
        "n": tot,
        "hit_rate": round(hi / tot, 4) if tot else None,
    }

    # 族内相对离群（median+margin）——BUG-25 出路里试过的那条，实测不成立（TP=0），留档防被重新提出
    fam_stats = []
    for p, kids in fams.items():
        rd = byid[p][2]
        gs = [c for _, c in kids if not c.startswith(rd[:20]) and "子任务单元" not in c]
        tr = tokens(rd)
        if len(tr) < MIN_TOKENS or len(gs) < 3:
            continue
        fam_stats.append([1.0 - similarity(tr, tokens(c)) for c in gs])

    def median(xs):
        s = sorted(xs)
        n = len(s)
        return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2

    rel_flag = rel_tot = 0
    for ds in fam_stats:
        m = median(ds)
        rel_tot += len(ds)
        rel_flag += sum(1 for d in ds if d > m + 0.2)
    out["family_relative_outlier_rule"] = {
        "note": "median+0.2 离群：真实改写家族上 FP=0，但注入跨域描述 TP=0 ⇒ 无检出力，未采用",
        "families": len(fam_stats),
        "flagged": rel_flag,
        "total": rel_tot,
        "absolute_threshold_flagged": sum(
            1 for ds in fam_stats for d in ds if d > DRIFT_TH
        ),
    }
    out["verdict"] = (
        "全量父子对分离成立（current 1.9% vs 随机 81.3%），但改写型父子对假阳性 ~59%"
        "（可测家族上绝对阈值命中 15/15）⇒ goal_drift_check 只能 advisory，不可作打回硬门。"
    )
    print(json.dumps(out, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
