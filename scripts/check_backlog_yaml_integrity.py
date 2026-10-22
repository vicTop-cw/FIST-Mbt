#!/usr/bin/env python3
"""backlog 台账完整性门（R110，由 R109 手工去重那一发实踩立成常驻判据）。

为什么要有这把尺：`docs/tasks/backlog/TASK-*.yaml` 是主机派给副机的任务面，而本仓对它的消费方式
是**逐行正则反解**，不是 YAML 解析（这批文件里 acceptance 用 `- [ ]` 复选框，PyYAML 会在第 23 列
抛 ParserError ⇒ 「load 成 dict 再取 status」这种自检根本跑不起来）。既然是逐行反解，
「同一份文件里整块任务被写两遍」就不是排版问题而是**读数问题**：后一份若是截断抄本，
任何「取最后一次出现」的读法都会读到没有验收结论的旧状态——R109 实测 TASK-001（P0）正是这个形状
（14 个顶层键各 2 次，第二份停在 `open_item`，缺 `result`/`acceptance_met`/`status_note`）。
人工去重一次会再长回来，所以把它变成常驻门。

判据（四条：R1/R2/R4 判红，R3 只诊断）：
  R1 顶层键唯一：同一文件里 `^[a-z_][a-z0-9_]*:` 反解出的键出现 >1 次 ⇒ 违例（整块重复的形状）。
  R2 抬头齐全：必须有 `id` / `title` / `priority` / `status` 四个键（缺任一 = 消费面读不到任务身份）。
  R3 只诊断不判红：`acceptance_met` 在场却仍写 `status: backlog` 时打一行 DIAG——这是「状态等 owner
     盖章」，不是文件坏了；把别人的裁决写成我的红，下一位只会把整把尺关掉。
  R4 无控制字符：正文里出现 C0 控制字符（`\x00`-`\x08` / `\x0b` / `\x0c` / `\x0e`-`\x1f`）⇒ 违例。
      TASK-023 实测：两处正则里的 `\b` 被写成 0x08 退格字节，grep/正则照跑但永远命不中——人眼看着是 `\b`，机器读的是退格。
      `\t` 与 `\r\n` 是合法排版空白，不进判据面（把正常文件打红只会让尺子被关掉）。

退出码：0=PASS；1=有违例（逐条点名文件与键名）；2=判据无法自证（扫描目录不存在/扫描面为空，
        缺样本＝没测，绝不报绿）；4=尺子自己坏了（未捕获异常，BUG-369 契约）。
用法：python scripts/check_backlog_yaml_integrity.py [--root <目录>] [--selftest]
"""
import argparse
import io
import os
import re
import shutil
import sys
import tempfile

# BUG-58/138：本尺 print 中文读数，Windows 默认 cp936 会把「一红就炸在编码上」伪装成 rc=1，
# 而 `check_py_stdout_encoding.py --all` 正是专门挡这一形的门（E1 条）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

TOP_KEY = re.compile(r'^([a-z_][a-z0-9_]*):', re.M)
CTRL_RE = re.compile(r'[\x00-\x08\x0b\x0c\x0e-\x1f]')
REQUIRED = ('id', 'title', 'priority', 'status')

GOOD = 'id: TASK-900\ntitle: "x"\npriority: P1\nstatus: backlog\nacceptance:\n  - [ ] 一条\n'


def list_files(root):
    if not os.path.isdir(root):
        return None
    return sorted(f for f in os.listdir(root) if f.startswith('TASK-') and f.endswith('.yaml'))


def check_text(text):
    """返回 (violations, diagnostics)。"""
    keys = TOP_KEY.findall(text)
    viol = []
    dup = sorted({k for k in keys if keys.count(k) > 1})
    if dup:
        viol.append('R1 顶层键重复 %d 个：%s' % (len(dup), ', '.join(dup)))
    missing = [k for k in REQUIRED if k not in keys]
    if missing:
        viol.append('R2 抬头缺键：%s' % ', '.join(missing))
    ctrl = CTRL_RE.findall(text)
    if ctrl:
        first = CTRL_RE.search(text)
        line_no = text.count('\n', 0, first.start()) + 1
        viol.append('R4 含 %d 个控制字符（首个 0x%02x 在第 %d 行）'
                    % (len(ctrl), ord(ctrl[0]), line_no))
    diag = []
    if 'acceptance_met' in keys and re.search(r'^status:[ \t]*backlog[ \t]*$', text, re.M):
        diag.append('acceptance_met 已在却仍写 status=backlog（待 owner 盖章，不计失败）')
    return viol, diag


def run(root):
    files = list_files(root)
    if files is None:
        print('FATAL 扫描目录不存在：%s ⇒ 无从判定，绝不报绿' % root)
        return 2
    if not files:
        print('FATAL 扫描面为空（%s 下一份 TASK-*.yaml 都没枚举到）⇒ 缺样本＝没测' % root)
        return 2
    viol_n = diag_n = 0
    for f in files:
        text = io.open(os.path.join(root, f), encoding='utf-8', errors='replace').read()
        viol, diag = check_text(text)
        for v in viol:
            print('VIOLATION %s :: %s' % (f, v))
        for d in diag:
            print('DIAG %s :: %s' % (f, d))
        viol_n += len(viol)
        diag_n += len(diag)
    print('扫描面=%s | 台账 %d 份 | 违例 %d 条 | 诊断 %d 条（诊断不计失败）'
          % (root, len(files), viol_n, diag_n))
    if viol_n:
        print('FAIL 台账完整性不成立：整块重复会让逐行反解的读法拿到截断抄本（R109 实锤形状）')
        return 1
    print('PASS backlog 顶层键唯一、抬头齐全且无控制字符')
    return 0


def write(d, name, body):
    io.open(os.path.join(d, name), 'w', encoding='utf-8', newline='\n').write(body)


def selftest():
    """合成对照：格子从已执行对照反解，不手写计数。"""
    done = []
    with tempfile.TemporaryDirectory() as d:
        write(d, 'TASK-900-good.yaml', GOOD)
        assert run(d) == 0, 'C1 失败：干净台账被误判'
        done.append('C1 干净不误红')

        write(d, 'TASK-901-dup.yaml', GOOD + GOOD.replace('TASK-900', 'TASK-901'))
        assert run(d) == 1, 'C2 失败：整块重复没抓到'
        done.append('C2 整块重复必红')
        os.remove(os.path.join(d, 'TASK-901-dup.yaml'))

        write(d, 'TASK-902-half.yaml', GOOD + 'id: TASK-902\npriority: P2\n')
        assert run(d) == 1, 'C3 失败：半截追加（只重复 id/priority）没抓到'
        done.append('C3 半截重复也必红')
        os.remove(os.path.join(d, 'TASK-902-half.yaml'))

        write(d, 'TASK-903-nohead.yaml', 'id: TASK-903\ntitle: "x"\n')
        assert run(d) == 1, 'C4 失败：抬头缺键没抓到'
        done.append('C4 抬头缺键必红')
        os.remove(os.path.join(d, 'TASK-903-nohead.yaml'))

        write(d, 'TASK-904-indent.yaml',
              GOOD + 'problem: >\n  id: 缩进正文不该当顶层键\nnested:\n  - status: 列表项不该当顶层键\n')
        assert run(d) == 0, 'C5 失败：缩进/列表行被误判成顶层键'
        done.append('C5 缩进与列表行不误判')
        os.remove(os.path.join(d, 'TASK-904-indent.yaml'))

        write(d, 'TASK-905-diag.yaml', GOOD + 'acceptance_met:\n  - "① 已落地"\n')
        assert run(d) == 0, 'C6 失败：诊断行被当成失败'
        done.append('C6 诊断不计失败')

    with tempfile.TemporaryDirectory() as d:
        assert run(d) == 2, 'C7 失败：空扫描面没自拒'
        done.append('C7 空面必自拒')
        assert run(os.path.join(d, 'nope')) == 2, 'C8 失败：目录不存在没自拒'
        done.append('C8 目录不存在必自拒')

    stale = 'docs/tasks/backlog/TASK-001-conflict-markers-no-commit.yaml'
    if os.path.isfile(stale):
        backup = stale + '.r110bak'
        shutil.copyfile(stale, backup)
        try:
            body = io.open(stale, encoding='utf-8', errors='replace').read()
            write('.', os.path.abspath(stale), body + body[:600])
            assert run('docs/tasks/backlog') == 1, 'C9 失败：真台账面上人造整块重复没抓到'
            done.append('C9 真面变异必红')
        finally:
            shutil.move(backup, stale)

    with tempfile.TemporaryDirectory() as d:
        write(d, 'TASK-906-ctrl.yaml',
              GOOD + "evidence: |\n  grep '^## BUG-(1|2)" + chr(8) + "' 命不中\n")
        assert run(d) == 1, 'C10 失败：控制字符没抓到'
        done.append('C10 控制字符必红')
        os.remove(os.path.join(d, 'TASK-906-ctrl.yaml'))

        write(d, 'TASK-907-tab.yaml', GOOD + 'evidence: |\n\t制表符与换行是合法空白\n')
        assert run(d) == 0, 'C11 失败：制表/换行被误判成控制字符'
        done.append('C11 制表/换行不误红')
        os.remove(os.path.join(d, 'TASK-907-tab.yaml'))
    print('SELFTEST OK（格子从已执行对照反解：%s）' % ' / '.join(done))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default='docs/tasks/backlog')
    ap.add_argument('--selftest', action='store_true')
    a = ap.parse_args()
    try:
        return selftest() if a.selftest else run(a.root)
    except Exception as e:
        print('FATAL 判据自身异常：%r（未捕获异常不许冒用「有违例」那一档）' % (e,))
        return 4


if __name__ == '__main__':
    sys.exit(main())
