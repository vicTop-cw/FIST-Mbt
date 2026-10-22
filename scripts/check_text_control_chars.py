#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""文本面 C0 控制字符门（R121）。

为什么要有它：R119/R120 实测同一形状连中三份制品——写 `\b` 时被转义吃成 0x08、`\e` 吃成 0x1b、
`\f` 吃成 0x0c，人眼看着文本正常，grep/正则却永远命不中（退格/ESC/换页是控制字符，不是反斜杠+字母）。
工具不会报错：文件照样能读、能提交、能发布，只是读它的人/程序拿到的不是作者以为的那段字。
本仓已有 `check_backlog_yaml_integrity.py` 的 R4 管任务池，但 memory/reports/docs/scripts 面没有守卫；
本尺把整个文本面做成零容忍门。

判据（两条，都判红）：
  R1 C0 控制字符：0x00-0x08 / 0x0b / 0x0c / 0x0e-0x1f（制表 0x09、换行 0x0a、回车 0x0d 是合法排版空白，允许）。
  R2 DEL：0x7f（终端里常被吞掉，同样是「看不见的字节」）。
扫描面：仓根递归，按文本扩展名白名单（.md/.py/.ps1/.sh/.yaml/.yml/.json/.txt/.mbt/.mbti/.cmd/.pkg）
+ `moon.mod`/`.gitignore`/`.gitattributes`；跳过 .git/.mooncakes/node_modules/_build/target/temp/dist 等生成与本地目录。
空扫描面（一份文本都没枚举到）或根目录不存在 ⇒ rc=2 自拒；未捕获异常走 4 号档（BUG-369 契约）。

用法：
  python scripts/check_text_control_chars.py [--root <目录>]
  python scripts/check_text_control_chars.py --selftest
退出码：0=文本面干净 / 1=有控制字符（逐文件点名行号与字节）/ 2=判据无法自证 / 4=尺子自己坏了
"""
import argparse
import io
import os
import re
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {".git", ".mooncakes", "node_modules", "_build", "target", "temp", "dist",
             ".qoder", ".vscode"}
TEXT_EXTS = {".md", ".py", ".ps1", ".sh", ".yaml", ".yml", ".json", ".txt", ".mbt",
             ".mbti", ".cmd", ".pkg"}
EXTRA_NAMES = {"moon.mod", ".gitignore", ".gitattributes"}


def text_files(root):
    for dp, dn, fn in os.walk(root):
        dn[:] = sorted(d for d in dn if d not in SKIP_DIRS)
        for f in sorted(fn):
            if f in EXTRA_NAMES or os.path.splitext(f)[1].lower() in TEXT_EXTS:
                p = os.path.join(dp, f)
                if os.path.islink(p):
                    continue
                yield p


def scan_file(path):
    """返回 [(行号, 字节列, 字节)]；制表/换行/回车不在判据面内。"""
    b = io.open(path, "rb").read()
    hits = []
    line = 1
    last_nl = -1
    for i, x in enumerate(b):
        if x == 10:
            line += 1
            last_nl = i
        elif (x < 32 and x not in (9, 13)) or x == 127:
            hits.append((line, i - last_nl, x))
    return hits


def run(root):
    if not os.path.isdir(root):
        print("FATAL 扫描目录不存在：%s ⇒ 无从判定，绝不报绿" % root)
        return 2
    files = list(text_files(root))
    if not files:
        print("FATAL 扫描面为空（%s 下一份文本都没枚举到）⇒ 缺样本＝没测" % root)
        return 2
    n_files = 0
    n_hits = 0
    for p in files:
        n_files += 1
        try:
            hits = scan_file(p)
        except OSError as e:
            print("FATAL 读不到 %s：%r ⇒ 判据无法自证" % (p, e))
            return 2
        if not hits:
            continue
        n_hits += len(hits)
        line, col, byte = hits[0]
        print("VIOLATION %s :: 共 %d 处，首个 0x%02x 在第 %d 行第 %d 字节列"
              % (os.path.relpath(p, root), len(hits), byte, line, col))
    print("扫描面=%s | 文本 %d 份 | 违例 %d 处" % (root, n_files, n_hits))
    if n_hits:
        print("FAIL 文本面含控制字符：读它的人/程序拿到的不是作者以为的那段字（R119/R120 实锤形状）")
        return 1
    print("PASS 文本面无 C0/DEL 控制字符")
    return 0


def write(d, name, data):
    p = os.path.join(d, name)
    parent = os.path.dirname(p)
    if parent and not os.path.isdir(parent):
        os.makedirs(parent)
    io.open(p, "wb").write(data)


def selftest():
    """合成对照：格子从已执行对照反解，不手写计数。"""
    done = []
    with tempfile.TemporaryDirectory() as d:
        write(d, "ok.md", b"# clean\n\t tab\r\nCRLF\n")
        assert run(d) == 0, "G1 失败：干净文本被误判"
        done.append("G1 干净不误红")

        write(d, "ignored.bin", bytes([8, 27]))
        assert run(d) == 0, "G2 失败：非文本扩展被误扫"
        done.append("G2 非文本扩展不误扫")

        write(d, "bad.md", b"grep ^## BUG-(1|2)" + bytes([8]) + b"\n")
        assert run(d) == 1, "M1 失败：0x08 没抓到"
        done.append("M1 0x08 必红")
        os.remove(os.path.join(d, "bad.md"))

        write(d, "del.txt", b"x" + bytes([127]) + b"\n")
        assert run(d) == 1, "M2 失败：DEL 没抓到"
        done.append("M2 DEL 必红")
        os.remove(os.path.join(d, "del.txt"))

        write(d, "nested/deep.md", b"\x1b[0m\n")
        assert run(d) == 1, "M3 失败：嵌套目录的 ESC 没抓到"
        done.append("M3 嵌套目录也扫描")
        os.remove(os.path.join(d, "nested", "deep.md"))

        assert run(d) == 0, "G3 失败：清场后仍有残留"
        done.append("G3 清场后回绿")

    with tempfile.TemporaryDirectory() as d:
        assert run(d) == 2, "R1 失败：空扫描面没自拒"
        done.append("R1 空面必自拒")

    assert run(os.path.join(tempfile.gettempdir(), "r121-no-such-dir")) == 2, \
        "R2 失败：目录不存在没自拒"
    done.append("R2 目录不存在必自拒")
    assert run(ROOT) == 0, "G4 失败：真现状面仍有控制字符"
    done.append("G4 真现状面必绿")
    counts = {}
    for name in done:
        fam = re.match(r"[A-Z]+", name).group(0)
        counts[fam] = counts.get(fam, 0) + 1
    inv = " / ".join("%s\u00d7%d" % (k, counts[k]) for k in sorted(counts))
    print("SELFTEST OK: %d 格（清单从已执行格子反解：%s）" % (len(done), inv))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    try:
        return selftest() if a.selftest else run(a.root)
    except Exception as e:
        print("FATAL 判据自身异常：%r（未捕获异常不许冒用「有违例」那一档）" % (e,))
        return 4


if __name__ == "__main__":
    sys.exit(main())
