#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_arg_face_strict.py —— 「参数面必须严格」的元判据（R64）。

## 为什么要有这把自己

本仓的判据大量用**手动 argv 扫描**（`if "--selftest" in sys.argv[1:]`、`if "--repo" in args`）。
这个写法有个隐蔽后果：**未知参数被静默忽略**。

于是把 `--selftest` 拼成 `--self-test` / `--selftst`，判据**照常跑真检查并报 PASS**——
调用方（CI、电池、人）以为自检跑过了，实际**一次都没跑**。
这和判例-32「版本号 PASS ≠ 代码新鲜」、R63「空扫描面报绿」是同一族：
**判据看起来在工作，实际没在守。**

## 判据面（实证，不读源码）

对每把 `scripts/check_*.py`：`python <尺> --definitely-not-a-real-flag`

| 结果 | 判定 |
|---|---|
| `rc != 0` | **合格**（明确拒绝：argparse 报错 / 自己 FATAL） |
| `rc == 0` | **违例**（吃下未知参数仍报绿 ⇒ 参数面没兜住） |

> 用「未知旗标」而不是「语法错误的参数」：前者正是「拼错自检开关」那个真实形状。

## 退出码

- `0` = 全部合格（且至少有 1 个候选）
- `1` = 存在违例（逐条点名）
- `2` = 判据无法自证（一个候选都没有）
- `4` = 尺子自己坏了（未捕获异常，绝不冒用 1）

## 已知债（2026-10-28 首次登记）

现读 **27 把**吃下未知参数仍 rc=0（占 75 把的 36%），其 **26 把是手动 argv 扫描**。
本判据先以 `kind="known-red"` 登记在电池里（本仓惯例：预存红照写期望值 + 依据，
被检面修到 0 之后这一格自己翻红，逼下一位把期望改回 0）。
出路：给这些尺加一张**允许旗标白名单**，未知旗标 ⇒ FATAL + rc=2；
或改用 `argparse`（它天生拒绝未知参数）。

## 变异对照（判例-29/30）

`--selftest` 在临时目录造两把合成尺：
- `check_bad_arg.py`：吃下未知参数仍 `sys.exit(0)` ⇒ 本尺**必须报 1 条违例**
- `check_good_arg.py`：未知参数 `sys.exit(2)` ⇒ 本尺**必须 0 条违例**
"""
import argparse
import glob
import os
import subprocess
from concurrent.futures import ThreadPoolExecutor
import sys
import tempfile
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")


ROOT = os.path.normpath(os.path.dirname(os.path.abspath(__file__)) + "/..")
SCRIPTS_DIR = os.path.join(ROOT, "scripts")
BAD_FLAG = "--definitely-not-a-real-flag"
CASE_TIMEOUT = 25
PRINT_CAP = 12
SELF_NAME = "check_arg_face_strict.py"


def candidates(scripts_dir=None):
    """被测面：scripts/check_*.py（排除本尺自己）。"""
    d = scripts_dir or "."      # R96：不默认 ROOT（自检链不得触及真仓）
    out = []
    for p in sorted(glob.glob(os.path.join(d, "check_*.py"))):
        if os.path.basename(p) == SELF_NAME:
            continue
        out.append(p)
    return out


def probe_one(script, timeout=CASE_TIMEOUT, cwd=None):
    # R96：`cwd` 自检时传合成目录（原来无条件 ROOT ⇒ hermetic 判据记 G 档）。
    """返回 ("ok"|"green"|"unknown", rc, 尾部读数)。"""
    try:
        r = subprocess.run([sys.executable, script, BAD_FLAG],
                           capture_output=True, text=True, timeout=timeout,
                           encoding="utf-8", errors="replace", cwd=cwd or os.path.dirname(script))
        rc = r.returncode
    except subprocess.TimeoutExpired:
        return "unknown", None, "超时 %ds" % timeout
    except OSError as e:  # noqa: BLE001
        return "unknown", None, "起不来：%s" % e
    txt = ((r.stdout or "") + (r.stderr or "")).strip().splitlines()
    tail = txt[-1][:100] if txt else ""
    if rc == 0:
        return "green", rc, tail
    return "ok", rc, tail


def judge(scripts_dir=None, timeout=CASE_TIMEOUT, cwd=None):
    cands = candidates(scripts_dir)
    if not cands:
        return [], [], 0
    # 并发探测：每个候选都是一次独立子进程，纯等待 ⇒ 并发不改变判定，只改变墙钟。
    # 结果按脚本名排序后再分桶，保证输出顺序与串行一致（可复现）。
    workers = min(8, max(1, len(cands)))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        results = list(pool.map(lambda p: (p, probe_one(p, timeout, cwd)), cands))
    verdicts, unknown = [], []
    for p, (kind, rc, tail) in sorted(results, key=lambda x: os.path.basename(x[0])):
        name = os.path.basename(p)
        if kind == "unknown":
            unknown.append((name, tail))
        elif kind == "green":
            verdicts.append((name, rc, tail))
    return verdicts, unknown, len(cands)


def run(argv=None):
    ap = argparse.ArgumentParser(
        description="参数面元判据：未知旗标必须被拒绝（吃到未知旗标还报绿 = 参数面没兜住）")
    ap.add_argument("--selftest", action="store_true", help="自证（合成坏尺/好尺，判例-29/30）")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()

    # R96：显式传真仓面（默认已改成 `.`，避免自检链触及真仓）
    verdicts, unknown, n = judge(scripts_dir=SCRIPTS_DIR, cwd=ROOT)
    if n == 0:
        print("FATAL 判据无法自证：scripts/ 下没有 check_*.py（扫描面为空）⇒ 拒绝出绿")
        return 2
    print("扫描面：%d 把 check_*.py；探测旗标 `%s`" % (n, BAD_FLAG))
    if unknown:
        print("  无法判定 %d 把（超时/起不来）—— 如实点名，不静默略过：" % len(unknown))
        for name, tail in unknown[:PRINT_CAP]:
            print("    ？%s：%s" % (name, tail))
    if verdicts:
        print("FAIL 参数面没兜住 %d 把（吃下未知旗标仍 rc=0 ⇒ 拼错自检开关会静默跑真检查）："
              % len(verdicts))
        for name, rc, tail in verdicts[:PRINT_CAP]:
            print("  - %s（rc=%d）%s" % (name, rc, tail))
        print("处置：加允许旗标白名单，未知旗标 ⇒ FATAL + rc=2；或改用 argparse（它天生拒绝未知参数）。")
        return 1
    print("PASS 参数面全部严格：%d 把判据遇到未知旗标都拒绝出绿（rc≠0）" % n)
    return 0


def selftest():
    cells, fails = [], []

    def cell(name, ok):
        cells.append(name)
        if not ok:
            fails.append(name)

    tmp = tempfile.mkdtemp(prefix="arg-face-st-")
    d = os.path.join(tmp, "scripts")
    os.makedirs(d)

    bad = (
        "import sys\n"
        "if '%s' in sys.argv[1:]:\n"
        "    pass\n"
        "print('PASS 我读到了未知旗标但我很快乐')\n"
        "sys.exit(0)\n" % BAD_FLAG
    )
    good = (
        "import argparse\n"
        "ap = argparse.ArgumentParser()\n"
        "ap.parse_args()\n"
        "print('PASS 参数面严格')\n"
    )
    import io
    io.open(os.path.join(d, "check_bad_arg.py"), "w", encoding="utf-8").write(bad)
    io.open(os.path.join(d, "check_good_arg.py"), "w", encoding="utf-8").write(good)

    v, u, n = judge(scripts_dir=d, timeout=20, cwd=tmp)
    cell("bad-arg-guard-is-flagged", n == 2 and len(v) == 1 and v[0][0] == "check_bad_arg.py")
    cell("good-arg-guard-not-flagged", not any(x[0] == "check_good_arg.py" for x in v))
    v2, _u2, n2 = judge(scripts_dir=os.path.join(tmp, "nonexist"), timeout=20)
    cell("empty-candidate-face-returns-zero-count", n2 == 0 and v2 == [])

    import shutil
    shutil.rmtree(tmp, ignore_errors=True)

    print("SELFTEST %s（%d 格：%s）" % ("OK" if not fails else "FAIL", len(cells), " ".join(cells)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 1


def main(argv):
    return run(argv)


def _purge_probe_artifacts():
    """删掉「探针旗标被当落盘路径」留下的同名产物。

    R75 实测事故：某脚本把 `--definitely-not-a-real-flag` 当**输出路径**，在仓库根
    写出 **56KB PDF**，文件名就是该旗标 ⇒ 未跟踪污染 ⇒ 连带 `check_publish_payload`
    报 P1「未跟踪又未被忽略」（电池红）。

    ⇒ **审计必须证明自己只跑不改**：跑前清残留（防上一发影响判定）、跑后清产物
      （否则这一格自己会把工作树弄脏）。
    """
    removed = []
    for path in (os.path.join(ROOT, BAD_FLAG), os.path.join(ROOT, BAD_FLAG + ".db")):
        try:
            if os.path.isfile(path):
                os.remove(path)
                removed.append(path)
            elif os.path.isdir(path):
                import shutil as _sh
                _sh.rmtree(path, ignore_errors=True)
                removed.append(path)
        except OSError:
            pass
    return removed


if __name__ == "__main__":
    _purge_probe_artifacts()      # 跑前清残留
    try:
        try:
            _rc = main(sys.argv[1:])
        finally:
            _left = _purge_probe_artifacts()   # 跑后清产物
            if _left:
                print("WARN 探针产物已清理：%s ⇒ 有脚本把未知旗标当落盘路径"
                      % ", ".join(os.path.basename(p) for p in _left))
        sys.exit(_rc)
    except SystemExit:
        raise
    except Exception as exc:  # 尺子自己坏了：4，绝不冒用 1
        print("FATAL 判据未捕获异常：%r" % (exc,))
        sys.exit(4)
