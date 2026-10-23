#!/usr/bin/env python3
"""每日日志重复块门（R133，由 2026-10-22 日志被整文件自我追加放大实踩立成常驻判据）。

为什么要有这把尺：`memory/YYYY-MM-DD.md` 是副机/主机 agent 手工追加的当日审计面。
R133 实测它被反复「整文件追加给自己」放大到 **91 MB / 25770 个 `## ` 块，其中只有 56 块唯一**
（同一 R70 块重复 1155 次，R106 重复 3465 次）；前一日 `2026-10-21.md` 也有 R23-R25 各 9 重的同形。
这些块逐字节相同、零信息，却把 clone/pull、检索与审阅成本整体拖垮；而没有任何机器面会红。
人工去重一次会再长回来，所以把它做成常驻门。

判据（D1/D2 判红，D3 只诊断）：
  D1 重复块：同一 `## ` 起首的块逐字节重复 ≥2 次且块长 ≥200 字符 ⇒ 违例。
     200 字符以下的短块不进 D1——短备注重复可能是有意排版，不把正常文件打红。
  D2 放大比例：重复字节占比 > 15%，或单份日志 > 2 MB ⇒ 违例（复制放大/审阅成本异常）。
  D3 只诊断：每日日志之外的 `memory/*.md`（bugs.md / thinking.md 等）不扫描；
     报告里打一行说明，不计失败——账本里 `## 根因` 这类子标题重复是合法结构。

退出码：0=PASS；1=有违例（逐条点名文件与重复块）；
        2=判据无法自证（memory 目录不存在 / 一份每日日志都没枚举到，缺样本＝没测，绝不报绿）；
        4=尺子自己坏了（未捕获异常，BUG-369 契约）。
空宇宙特例（788c5823 既成策略）：`memory/YYYY-MM-DD.md` 自该 commit 起被 `.gitignore`
（`memory/2026-*.md`）整体剔出 git 跟踪面，故干净 checkout（=CI 面）上一份日日志都没有，
**不是坏环境而是既定策略的自然结果**。此时若判据能证明「日日志缺席跟踪面」是策略
（仓库根 `.gitignore` 确有匹配 `memory/YYYY-MM-DD.md` 的规则），走 **空宇宙豁免：rc=0**，
并打一行明确说明——不判红、也不拿「没读到」当「对上了」。锚点不成立（无该规则）才
回真·无法自证（rc=2）。豁免只对「确实一份都没有」生效：`memory/` 下一旦出现任何一份
日日志，立刻退回真正的去重面，重复块照样 rc=1，绝不假绿。
用法：python scripts/check_memory_log_dedupe.py [--root <目录>] [--selftest] [--fix]
  --fix  按首次出现顺序原地去重（每块保留一份，CRLF 原样保留）；写后复验唯一块集合不变，
         任何丢失按 rc=4 自拒。只对 `YYYY-MM-DD.md` 生效，绝不碰 bugs.md 等账本。
"""
import argparse
import glob
import hashlib
import io
import os
import re
import sys
import tempfile

# BUG-58/138：本尺 print 中文读数，Windows 默认 cp936 会把「一红就炸在编码上」伪装成 rc=1。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

DAILY_RE = re.compile(r'^\d{4}-\d{2}-\d{2}\.md$')
MIN_BLOCK_CHARS = 200
RATIO_LIMIT = 0.15
SIZE_LIMIT = 2 * 1024 * 1024
MAX_REPORTED_GROUPS = 5


def list_daily(root):
    if not os.path.isdir(root):
        return None
    return sorted(os.path.basename(p) for p in glob.glob(os.path.join(root, '*.md'))
                  if DAILY_RE.match(os.path.basename(p)))


def daily_log_ignored_by_gitignore(scan_root):
    """空宇宙豁免的**策略锚点**：`.gitignore` 是否确有规则匹配 `memory/YYYY-MM-DD.md`。

    788c5823 起日日志被 `memory/2026-*.md`（及同类 `memory/20??-*.md`）剔出 git 跟踪面。
    判定规则：从**扫描根自身**向上逐层找 `.gitignore`（就近优先，直到根盘/无父目录为止）。
    这既让「干净 checkout 的默认 `memory/`」能找到仓库根那份声明，也让一个**独立临时面**
    不会被仓库根的规则误豁免——锚点必须「覆盖这个扫描面」才算成立。
    锚点不成立＝空扫描面就是真·无法自证，必须 rc=2。只读 `.gitignore`，不调 git、不写文件。
    """
    cur = os.path.abspath(scan_root)
    while True:
        gi = os.path.join(cur, '.gitignore')
        if os.path.isfile(gi):
            if _gitignore_ignores_daily(gi):
                return True
        nxt = os.path.dirname(cur)
        if nxt == cur:
            return False
        cur = nxt


def _gitignore_ignores_daily(gi_path):
    """单份 `.gitignore` 里是否有规则匹配 `memory/YYYY-MM-DD.md`。"""
    try:
        with open(gi_path, 'r', encoding='utf-8', errors='replace') as fh:
            lines = fh.read().splitlines()
    except OSError:
        return False
    probe = 'memory/2026-01-01.md'
    for raw in lines:
        line = raw.rstrip()
        if not line or line.startswith('#'):
            continue
        # 去掉未转义 `#` 起的注释（转义首字符保留）
        out, hash_esc = [], False
        for c in line:
            if c == '\\':
                hash_esc = True
                continue
            if c == '#' and not hash_esc:
                break
            out.append(c)
            hash_esc = False
        line = ''.join(out).strip()
        if not line:
            continue
        pat = line.lstrip('/')  # 忽略仓库根锚定 `/`：memory/ 本就在根下
        if pat in ('memory', 'memory/'):
            return True  # 整目录忽略 ⇒ 覆盖一切日日志
        if pat.startswith('memory/'):
            sub = pat[len('memory/'):]
            if sub == probe[len('memory/'):]:
                return True
            if '*' in sub:  # 本仓只用 `*`（如 `2026-*.md`）；`?`/`[]`/`**` 保守按字面
                if not sub.startswith('*') and not probe[len('memory/'):].startswith(sub.split('*')[0]):
                    continue
                if not sub.endswith('*') and not probe[len('memory/'):].endswith(sub.split('*')[-1]):
                    continue
                return True
    return False


def empty_universe_verdict(scan_root):
    """空宇宙三分：`broken`（目录不存在）/ `empty_policy`（策略豁免）/ `empty_unproven`（真失败）。

    返回 (kind, 说明)。有样本时调用方不该走到这里；这里只回答「为什么是空的」。
    """
    if not os.path.isdir(scan_root):
        return 'broken', '扫描目录不存在：%s' % scan_root
    if daily_log_ignored_by_gitignore(scan_root):
        return 'empty_policy', (
            '.gitignore 确有忽略 `memory/YYYY-MM-DD.md` 的规则'
            '（日日志已剔 git 跟踪，788c5823 既成策略）'
        )
    return 'empty_unproven', '扫描面为空且 .gitignore 未证明忽略日日志'


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def split_blocks(text):
    """按 `## ` 起首行切块；首块可含标题/前言。返回字节块列表（LF 归一）。"""
    data = text.replace('\r\n', '\n').encode('utf-8')
    blocks = []
    cur = []
    for ln in data.split(b'\n'):
        if ln.startswith(b'## ') and cur:
            blocks.append(b'\n'.join(cur))
            cur = [ln]
        else:
            cur.append(ln)
    if cur:
        blocks.append(b'\n'.join(cur))
    return blocks


def block_title(b):
    first = b.split(b'\n', 1)[0].decode('utf-8', 'replace')
    return first[:60]


def check_text(text):
    """返回 (violations, stats)。"""
    blocks = split_blocks(text)
    groups = {}
    for b in blocks:
        groups.setdefault(hashlib.sha256(b).hexdigest(), []).append(b)
    dup = [(h, v) for h, v in groups.items()
           if len(v) > 1 and len(v[0]) >= MIN_BLOCK_CHARS]
    total = max(1, len(text.encode('utf-8')))
    dup_bytes = sum(len(v[0]) * (len(v) - 1) for _h, v in dup)
    viol = []
    for _h, v in sorted(dup, key=lambda kv: len(kv[1]), reverse=True)[:MAX_REPORTED_GROUPS]:
        viol.append('D1 块重复 %d 次：%s' % (len(v), block_title(v[0])))
    if len(dup) > MAX_REPORTED_GROUPS:
        viol.append('D1 另有 %d 组重复块未逐条列出' % (len(dup) - MAX_REPORTED_GROUPS))
    if dup_bytes * 1.0 / total > RATIO_LIMIT:
        viol.append('D2 重复字节 %d / 总字节 %d（占比 %.1f%% > %.0f%%）'
                    % (dup_bytes, total, dup_bytes * 100.0 / total, RATIO_LIMIT * 100))
    if total > SIZE_LIMIT:
        viol.append('D2 单份日志 %d 字节 > %d（疑似复制放大/审阅成本异常）'
                    % (total, SIZE_LIMIT))
    return viol, {'blocks': len(blocks), 'unique': len(groups),
                  'dup_groups': len(dup), 'bytes': total}


def check_file(path):
    text = io.open(path, encoding='utf-8', errors='replace').read()
    return check_text(text)


def run(root):
    files = list_daily(root)
    if files is None:
        print('FATAL 扫描目录不存在：%s ⇒ 无从判定，绝不报绿' % root)
        return 2
    if not files:
        kind, why = empty_universe_verdict(root)
        if kind == 'empty_policy':
            print('MEMLOG=empty-universe 空宇宙豁免（rc=0）：%s 下一份 YYYY-MM-DD.md 都没有，'
                  '且 %s——日日志缺席跟踪面是既定策略的自然结果，'
                  '不是坏环境、也不是「缺样本＝没测」；不判红、也不拿「没读到」当「对上了」。'
                  '一旦 %s 下出现任何一份日日志，本尺立刻退回真去重面。'
                  % (root, why, root))
            return 0
        if kind == 'broken':
            print('FATAL 扫描目录不存在：%s ⇒ 无从判定，绝不报绿' % root)
            return 2
        print('FATAL 扫描面为空（%s 下一份 YYYY-MM-DD.md 都没枚举到）且 %s ⇒ 缺样本＝没测，绝不报绿'
              % (root, why))
        return 2
    viol_n = 0
    for f in files:
        viol, st = check_file(os.path.join(root, f))
        for v in viol:
            print('VIOLATION %s :: %s' % (f, v))
        print('  %s | 块 %d / 唯一 %d / 重复组 %d / %d 字节'
              % (f, st['blocks'], st['unique'], st['dup_groups'], st['bytes']))
        viol_n += len(viol)
    others = sorted(os.path.basename(p) for p in glob.glob(os.path.join(root, '*.md'))
                    if not DAILY_RE.match(os.path.basename(p)))
    if others:
        print('DIAG 非每日日志不扫描（合法子标题重复，不计失败）：%s' % ', '.join(others))
    print('扫描面=%s | 每日日志 %d 份 | 违例 %d 条' % (root, len(files), viol_n))
    if viol_n:
        print('FAIL 每日日志存在复制放大：同一块重复出现会让日志失去审计价值并拖垮 pull/检索')
        return 1
    print('PASS 每日日志无整块重复、无复制放大')
    return 0


def dedupe_file(path):
    """原地去重，保留首次出现顺序；返回 (before_blocks, after_blocks)。
    写前先复验唯一块集合不变；无重复的文件一个字节都不动。"""
    raw = io.open(path, 'rb').read()
    text = raw.replace(b'\r\n', b'\n').decode('utf-8')
    blocks = split_blocks(text)
    seen = set()
    keep = []
    for b in blocks:
        h = hashlib.sha256(b).hexdigest()
        if h not in seen:
            seen.add(h)
            keep.append(b)
    if len(keep) == len(blocks):
        return len(blocks), len(keep)
    before_hashes = set(hashlib.sha256(b).hexdigest() for b in blocks)
    out = b'\n'.join(keep)
    if b'\r\n' in raw:
        out = out.replace(b'\n', b'\r\n')
    after_hashes = set(hashlib.sha256(b).hexdigest()
                       for b in split_blocks(out.decode('utf-8')))
    if before_hashes != after_hashes:
        raise RuntimeError('去重后唯一块集合发生变化（信息丢失，未写盘）：%s' % path)
    io.open(path, 'wb').write(out)
    return len(blocks), len(keep)


def fix(root):
    files = list_daily(root)
    if files is None or not files:
        # 空宇宙与目录缺失都交给 run() 判：策略锚点成立则 rc=0 豁免，否则 rc=2 绝不报绿。
        return run(root)
    for f in files:
        p = os.path.join(root, f)
        before, after = dedupe_file(p)
        print('FIXED %s :: %d -> %d 块' % (f, before, after))
    return run(root)


def write(d, name, body):
    io.open(os.path.join(d, name), 'w', encoding='utf-8', newline='\n').write(body)


BIG = ('## R900 合成重复块\n\n'
       + ('这一行是用于触发 D1 的长块正文，长度必须超过 200 字符阈值。' * 6) + '\n')
SMALL = '## 短备注\n- 短\n'


def selftest():
    """合成对照：格子从已执行对照反解，不手写计数。"""
    done = []
    with tempfile.TemporaryDirectory() as d:
        write(d, '2026-01-01.md', '## R1 独立块\n\n' + BIG + '\n## R2 另一块\n\n正文。\n')
        assert run(d) == 0, 'C1 失败：干净日志被误判'
        done.append('C1 干净不误红')

        write(d, '2026-01-02.md', BIG + '\n' + BIG)
        assert run(d) == 1, 'C2 失败：整块重复没抓到'
        done.append('C2 整块重复必红')
        os.remove(os.path.join(d, '2026-01-02.md'))

        write(d, '2026-01-03.md', SMALL + SMALL)
        assert run(d) == 0, 'C3 失败：短块重复被误判成长块重复'
        done.append('C3 短块重复不误红')
        os.remove(os.path.join(d, '2026-01-03.md'))

        write(d, 'bugs.md', BIG + '\n' + BIG)
        assert run(d) == 0, 'C4 失败：非每日日志被纳入扫描面'
        done.append('C4 只扫每日日志')
        os.remove(os.path.join(d, 'bugs.md'))

        blocks_before = set(hashlib.sha256(b).hexdigest() for b in split_blocks(BIG + '\n' + BIG))
        write(d, '2026-01-04.md', BIG + '\n' + BIG)
        assert dedupe_file(os.path.join(d, '2026-01-04.md')) == (2, 1), 'C5 失败：--fix 没去重'
        body = io.open(os.path.join(d, '2026-01-04.md'), encoding='utf-8').read()
        blocks_after = set(hashlib.sha256(b).hexdigest() for b in split_blocks(body))
        assert blocks_before == blocks_after, 'C5 失败：--fix 丢失唯一块'
        assert run(d) == 0, 'C5 失败：--fix 后仍判红'
        done.append('C5 --fix 无损去重')
        os.remove(os.path.join(d, '2026-01-04.md'))

        write(d, '2026-01-05.md', '## R5 无尾换行\n\n正文没有结尾换行')
        p5 = os.path.join(d, '2026-01-05.md')
        raw_before = io.open(p5, 'rb').read()
        assert dedupe_file(p5) == (1, 1), 'C8 失败：干净文件块数不对'
        assert io.open(p5, 'rb').read() == raw_before, 'C8 失败：无尾换行的干净文件被改写'
        done.append('C8 无尾换行不改写')
        os.remove(p5)

    with tempfile.TemporaryDirectory() as d:
        assert run(d) == 2, 'C6 失败：空扫描面没自拒'
        done.append('C6 空面必自拒')
        assert run(os.path.join(d, 'nope')) == 2, 'C7 失败：目录不存在没自拒'
        done.append('C7 目录不存在必自拒')

    with tempfile.TemporaryDirectory() as d:
        # C9：空宇宙 ≠ 空宇宙豁免——.gitignore 若没忽略日日志（策略锚点不成立），仍 rc=2
        with open(os.path.join(d, '.gitignore'), 'w', encoding='utf-8') as fh:
            fh.write('node_modules/\n')  # 无关规则：不构成锚点
        assert run(d) == 2, 'C9 失败：锚点不成立的空面被误豁免'
        done.append('C9 锚点不成立不豁免')
        # C10：锚点成立（.gitignore 确有 memory/20??-*.md）时，空宇宙走豁免 rc=0
        with open(os.path.join(d, '.gitignore'), 'w', encoding='utf-8') as fh:
            fh.write('memory/2026-*.md\n')
        assert daily_log_ignored_by_gitignore(d) is True, 'C10 失败：锚点未识别'
        assert run(d) == 0, 'C10 失败：锚点成立的空宇宙没豁免'
        done.append('C10 锚点成立空宇宙豁免 rc=0')
        # C11：同一临时面一旦放进日日志，立刻退回真去重面——有整块重复仍必红（防假绿）
        write(d, '2026-01-01.md', BIG + '\n' + BIG)
        assert run(d) == 1, 'C11 失败：豁免后真重复被放行（假绿）'
        done.append('C11 有日志仍真去重（假绿反锁）')

    print('SELFTEST OK（格子从已执行对照反解：%s）' % ' / '.join(done))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default='memory')
    ap.add_argument('--selftest', action='store_true')
    ap.add_argument('--fix', action='store_true')
    a = ap.parse_args()
    try:
        if a.selftest:
            return selftest()
        return fix(a.root) if a.fix else run(a.root)
    except Exception as e:
        print('FATAL 判据自身异常：%r（未捕获异常不许冒用「有违例」那一档）' % (e,))
        return 4


if __name__ == '__main__':
    sys.exit(main())
