#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_ps_encoding.py —— PowerShell 脚本编码守卫（2026-09-28 irm 安装面事故）。

为什么要有：`scripts/blackbox/install_onecmd.ps1` 是无 BOM 的 UTF-8，Windows PowerShell 5.1
（本机 `powershell` = 5.1.26100，也正是 README 那条 `irm … | iex` 默认落到的 shell）
按 ANSI(cp936) 读它 ⇒ 一个 UTF-8 多字节序列会**吞掉紧随其后的收尾 `\"`**，
整份脚本在解析期就炸（实测 8 处 ParserError），用户一条命令都跑不到下载那步。
pwsh 7 不会犯（默认 UTF-8），所以这台守卫测的是"两代 shell 里较弱的那一代"。

判据（任一不满足即红）：
  P1  scripts/ 下每个 *.ps1 要么以 UTF-8 BOM 开头，要么整文件纯 ASCII——两者都不满足即红。
      豁免形状是"纯 ASCII"而不是"我保证不用中文"：ASCII 文件在任何代码页下字节等同，天然安全。
  P2  扫描面为空（一个 .ps1 都没抓到）即红——没抓到声明 ≠ 没有问题，先判枚举器坏。
  P3  --selftest 必须在合成违例上发红，并且对两类合规输入（BOM / 纯 ASCII）不误红。

用法：
    python scripts/check_ps_encoding.py            # 全量判据
    python scripts/check_ps_encoding.py --selftest # 判据自己会不会红
退出码：0=PASS，1=违例，2=无法自证（枚举失效）。
"""
import re
import shutil
import sys
import tempfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"
BOM = b"\xef\xbb\xbf"


def ps_surfaces(root=None):
    """扫描面 = scripts/ 下全部 .ps1（递归：blackbox/ 也在射程内，事故就出在那儿）。"""
    base = root or SCRIPTS
    return sorted(str(p) for p in Path(base).rglob("*.ps1"))


def ps_encoding_problems(paths):
    """纯判据：喂 .ps1 路径清单，出违例列表。空清单 ⇒ 判据自己红（P2）。"""
    if not paths:
        return ["扫描面为空：一个 .ps1 都没抓到 ≠ 没有问题，先判枚举器坏"]
    problems = []
    for p in paths:
        try:
            raw = Path(p).read_bytes()
        except OSError as e:
            problems.append(f"{p}：读不到字节（{e}）")
            continue
        if raw.startswith(BOM):
            continue
        non_ascii = sum(1 for b in raw if b > 0x7F)
        if non_ascii == 0:
            continue  # 纯 ASCII 在任何代码页下等价，无需 BOM
        problems.append(
            f"{p}：无 UTF-8 BOM 且含 {non_ascii} 个非 ASCII 字节"
            " ⇒ Windows PowerShell 5.1 按 ANSI 读：中文文案必乱码，多字节序列落在引号前时"
            "吞掉收尾引号、解析期即炸（2026-09-28 用 PS5.1 的 Parser::ParseFile 实测：修复前 "
            "native-env.ps1 12 处 / showcase.ps1 5 处 / demo.ps1 0 处，补 BOM 后三档全部 0 处）")
    return problems


def j_selftest():
    """合成违例必红 + 两类合规不误红 + 空扫描必红 + 真实现状面不误红。"""
    fails = []
    tmp = Path(tempfile.mkdtemp(prefix="ps-enc-selftest-"))
    try:
        bad = tmp / "bad.ps1"
        bad.write_bytes('Write-Host "下载成功 ✅"'.encode("utf-8"))
        ok_bom = tmp / "bom.ps1"
        ok_bom.write_bytes(BOM + 'Write-Host "下载成功 ✅"'.encode("utf-8"))
        ok_ascii = tmp / "ascii.ps1"
        ok_ascii.write_bytes(b'Write-Host "download ok"')

        if not ps_encoding_problems([str(bad)]):
            fails.append("P1 对『无 BOM 且含非 ASCII』不敏感 → 判据是装饰")
        if ps_encoding_problems([str(ok_bom), str(ok_ascii)]):
            fails.append("P1 对合规输入误红（恒红判据不可信）")
        if not ps_encoding_problems([]):
            fails.append("P2 空扫描面不红（枚举器坏了会以全绿通过）")
        # 变异对照：同一文件加/去 BOM 必须翻转判定，否则判据数的是文件名而不是字节
        bad.write_bytes(BOM + bad.read_bytes())
        if ps_encoding_problems([str(bad)]):
            fails.append("P1 加了 BOM 仍判红 → 它没在读字节")
        ok_ascii.write_bytes('Write-Host "中文"'.encode("utf-8"))
        if not ps_encoding_problems([str(ok_ascii)]):
            fails.append("P1 对『ASCII 文件被改成非 ASCII 且仍无 BOM』不敏感")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    real = ps_encoding_problems(ps_surfaces())
    if real:
        fails.append("P1 在真实现状面上就红了（先判判据，再判产品）：" + real[0])
    if not ps_surfaces():
        fails.append("现状扫描面为空：scripts/ 下没有 .ps1？那这台守卫测不到东西")
    return fails


def main(argv):
    selftest = "--selftest" in argv
    if selftest:
        fails = j_selftest()
        if fails:
            print("SELFTEST FAIL: 编码判据抓不到合成违例（判据自己坏了）：")
            for f in fails:
                print("  - " + f)
            return 2
        print(f"SELFTEST OK: P1/P2 对『无 BOM+非 ASCII』『空扫描』都发红，"
              f"对『带 BOM』『纯 ASCII』不误红；加/去 BOM 能翻转判定（数的是字节不是文件名）；"
              f"现状面 {len(ps_surfaces())} 个 .ps1 全合规")
        return 0

    paths = ps_surfaces()
    if not paths:
        print("FATAL: 扫描面为空，本次判定不可信")
        return 2
    problems = ps_encoding_problems(paths)
    if problems:
        print(f"FAIL PowerShell 编码守卫：{len(problems)} 处违例（共扫 {len(paths)} 个 .ps1）")
        for p in problems:
            print("  - " + p)
        print("修法：另存为「UTF-8 with BOM」，或把非 ASCII 文案换成 ASCII（守卫认这两种形状）")
        return 1
    print(f"PASS PowerShell 编码守卫：{len(paths)} 个 .ps1 全部带 BOM 或纯 ASCII"
          "（Windows PowerShell 5.1 按 ANSI 读也不会吞引号）")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
