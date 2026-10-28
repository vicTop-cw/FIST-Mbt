import sys
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/cleanup_artifacts.py — 项目整洁：清理 gitignore 的代码生成物/临时脚本残留。

背景（目标 pillar：项目整洁干净《临时脚本任务完清理策略、代码生成物清理》）。
测试与自驱脚本会在仓库根留下大量被 gitignore 的 SQLite 生成物（watchdog_*.db、wal-*.db、
smoke_*.db、decompose_persist.db、alpha.db 等 .db / -shm / -wal），并在 temp/ 留下 scratch 库。
这些不进 git，但污染任意检出的工作树，干扰"任意机器结果可复现"。

本脚本（幂等、安全）：
  - 删除仓库根"除 fist-mbt.db（唯一被 git 跟踪的交付 数据库快照）之外"的全部 *.db / *.db-shm / *.db-wal；
  - 清空 temp/（scratch 临时库区）；
  - 把 scripts/ 下 `_` 前缀的**未跟踪**临时脚本（任务完即清策略）移入 temp/，使正式工具目录干净；
  - **BUG-334：git 跟踪的 `_` 脚本是正式资产**（如 `scripts/_tool_registry.py` 工具注册单一真源，
    被 check_tools_sync / check_plugin_sync / gen_plugins / check_doc_surface / mcp_smoke 等 7 处导入），
    一律不动——只清 `git ls-files --others`（untracked），从根上避免误删已跟踪临时文件；
  - --check 模式只报告残留数量（0 = 干净），不删任何文件。

`--selftest`（R179 起改打合成夹具）：S1/S2/S3 全部打在 temp 下一份**真 git 仓**沙箱上
（里面有已跟踪的 `scripts/_tool_registry.py` 作豁免面对象、可造未跟踪的 `_` 探针作残留面对象），
不再往真 `scripts/` 树写探针——判据自证不许以别人的工作树为代价（R153 的 hermetic 律）。
仓根经**必填形参**注入（默认参流进 I/O 是本仓明文标注的判据漏红面，不走）。

用法：
  python scripts/cleanup_artifacts.py          # 清理 + 打印各文件
  python scripts/cleanup_artifacts.py --check  # 只报告残留数（可作 CI 守卫）
"""
import os, sys, shutil, subprocess, tempfile

# BUG-138（BUG-58 同族）：守卫的红必须是判据红。Windows 默认 cp936 控制台上打印中文结论里的
# ⇒ 等字符会让 print 当场 UnicodeEncodeError——拿到 traceback 而不是 verdict，而且崩在结论行之前
# 留下的 rc 会被读成「缺陷在场」（判据自己的崩不许冒用被测的退出码）。CI 在 Linux UTF-8 下是无损 no-op。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
KEEP = {"fist-mbt.db"}            # 唯一被 git 跟踪的交付数据库，绝不删
# fist-mbt.db 在 SQLite WAL 模式下的瞬时 sidecar，随下次打开必然重建，不算残留
KEEP_SIDECAR = {"fist-mbt.db-shm", "fist-mbt.db-wal"}
SUFFIXES = (".db", ".db-shm", ".db-wal")


def stray_root_dbs(root):
    """仓库根下应删的生成物（排除 KEEP）。返回相对路径列表。"""
    out = []
    for name in sorted(os.listdir(root)):
        full = os.path.join(root, name)
        if not os.path.isfile(full):
            continue
        if name in KEEP or name in KEEP_SIDECAR:
            continue
        if name.endswith(SUFFIXES):
            out.append(name)
    return out


def temp_files(root):
    """temp/ 下应清理的 scratch 生成物。返回相对路径列表。"""
    out = []
    tdir = os.path.join(root, "temp")
    if not os.path.isdir(tdir):
        return out
    for name in sorted(os.listdir(tdir)):
        full = os.path.join(tdir, name)
        if os.path.isfile(full) or os.path.islink(full):
            out.append(os.path.join("temp", name))
    return out


# 临时脚本的扩展名（任务完即清策略的对象）
_TMP_SCRIPT_EXT = (".py", ".ps1", ".sh")


def is_git_tracked(relpath, root):
    """relpath 是否被 git 跟踪。跟踪=正式资产，cleanup 一律不动（BUG-334）。"""
    try:
        r = subprocess.run(
            ["git", "ls-files", "--error-unmatch", "--", relpath],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=root,
        )
        return r.returncode == 0
    except OSError:
        return False


def stray_underscore_scripts(root):
    """scripts/ 下 `_` 前缀的**未跟踪**临时脚本（正式工具目录不应留）。返回绝对路径+相对名列表。

    BUG-334：git 跟踪的 `_` 脚本是正式资产（如 `scripts/_tool_registry.py` 工具注册单一真源，
    被 7 个守卫/生成器导入），移走即当场 ImportError 红一片。故此处只放行 untracked。
    """
    sdir = os.path.join(root, "scripts")
    out = []
    if not os.path.isdir(sdir):
        return out
    for name in sorted(os.listdir(sdir)):
        full = os.path.join(sdir, name)
        if not (
            name.startswith("_")
            and os.path.isfile(full)
            and name.endswith(_TMP_SCRIPT_EXT)
        ):
            continue
        rel = os.path.join("scripts", name)
        if is_git_tracked(rel, root):
            continue
        out.append((full, rel))
    return out


# 每档最多点名多少个（超过则折叠成「其余 N 件」——日志可读性与可核对性的折中）
MAX_NAMES = 20


def format_lines(root_stray, tfiles, uscripts, exempt):
    """把三档残留渲染成**逐条点名**的行（BUG-368：只报档数时无法核对「623」由什么构成）。

    返回 (lines, dirty)。dirty=有无应清理项。豁免项单独出行——它证明「跟踪真源不在此档」
    这条约定真的生效了，而不是被静默跳过（BUG-334 的豁免若失效，读数会退回虚报）。
    """
    lines = []
    dirty = bool(root_stray or tfiles or uscripts)
    if dirty:
        lines.append(
            "DIRTY: 仓库残留 %d 个根 .db + %d 个 temp/ 文件 + %d 个 scripts/ `_` 临时脚本（共 %d）"
            % (len(root_stray), len(tfiles), len(uscripts),
               len(root_stray) + len(tfiles) + len(uscripts))
        )
        buckets = (("根 .db", root_stray), ("temp/", tfiles), ("scripts/ `_` 临时脚本", [r for _a, r in uscripts]))
        for label, items in buckets:
            if not items:
                continue
            shown = items[:MAX_NAMES]
            for it in shown:
                lines.append("  - [%s] %s" % (label, it))
            if len(items) > MAX_NAMES:
                lines.append("  - [%s] … 其余 %d 件（上限 %d 件点名）" % (label, len(items) - MAX_NAMES, MAX_NAMES))
    if exempt:
        for it in exempt[:MAX_NAMES]:
            lines.append("  - [豁免·git 跟踪真源] %s" % it)
        if len(exempt) > MAX_NAMES:
            lines.append("  - [豁免·git 跟踪真源] … 其余 %d 件" % (len(exempt) - MAX_NAMES))
    return lines, dirty


def exempt_tracked_underscore(root):
    """scripts/ 下 `_` 前缀的**已跟踪**脚本（正式资产，BUG-334/BUG-368 的豁免面）。

    单独取出来只为把它印进读数：豁免必须可见，否则「1 个 `_` 临时脚本」这种虚报
    无法从输出上分辨是「真残留」还是「跟踪真源被误数」。"""
    sdir = os.path.join(root, "scripts")
    out = []
    if not os.path.isdir(sdir):
        return out
    for name in sorted(os.listdir(sdir)):
        full = os.path.join(sdir, name)
        if not (name.startswith("_") and os.path.isfile(full) and name.endswith(_TMP_SCRIPT_EXT)):
            continue
        rel = os.path.join("scripts", name)
        if is_git_tracked(rel, root):
            out.append(rel)
    return out


def _git_rc(dirpath, *args):
    p = subprocess.run(("git",) + args, cwd=dirpath, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE)
    return p.returncode, p.stderr.decode("utf-8", "replace").strip()[:120]


def _rmtree(path):
    """删合成仓根。git 把对象写成只读，Windows 上 rmtree 不处理只读会 PermissionError——
    夹具清不干净就是往别人机器上留垃圾，故清位重试而非吞掉异常。"""
    def _clear(func, p, _exc):
        try:
            os.chmod(p, 0o700)
            func(p)
        except OSError:
            pass
    shutil.rmtree(path, onerror=_clear)


TRACKED_PROBE = os.path.join("scripts", "_tool_registry.py")


def _sandbox(dirpath, stage=True):
    """temp 下的合成仓根：真 git 仓 + `scripts/` 目录 + 一份已跟踪的 `_tool_registry.py`。

    夹具必须是**真 git 仓**——S1/S2/S3 判的就是「跟踪 vs 未跟踪」这条线。非 git 目录里
    `git ls-files --error-unmatch` 恒失败，两个面塌成同一档，S2 会以内「豁免生效」的名义
    放行一个坏掉的跟踪探测。
    """
    rc, err = _git_rc(dirpath, "init", "-q")
    if rc != 0:
        raise RuntimeError("沙箱 git init 失败（rc=%d）：%s" % (rc, err))
    os.makedirs(os.path.join(dirpath, "scripts"))
    with open(os.path.join(dirpath, "scripts", "_tool_registry.py"), "w", encoding="utf-8") as fh:
        fh.write("# 夹具里的工具注册真源（BUG-334 豁免面的合成对应物）\n")
    with open(os.path.join(dirpath, "scripts", "keep.py"), "w", encoding="utf-8") as fh:
        fh.write("# 非 `_` 前缀的正式工具，作夹具的对照背景\n")
    if stage:
        rc, err = _git_rc(dirpath, "add", "-A")
        if rc != 0:
            raise RuntimeError("沙箱 git add 失败（rc=%d）：%s" % (rc, err))
        rc, err = _git_rc(dirpath, "-c", "user.name=selftest", "-c",
                          "user.email=selftest@sandbox.invalid", "commit", "-q", "-m", "夹具基线")
        if rc != 0:
            raise RuntimeError("沙箱 git commit 失败（rc=%d）：%s" % (rc, err))
    return dirpath


def _sandbox_ok(dirpath):
    """夹具形状自证：豁免面（tracked `_` 脚本）与残留面（untracked `_` 脚本）必须**分别**真在场。

    两档塌成一档时，「`_tool_registry.py` 不在候选里」这条断言就再也分辨不出是豁免生效
    还是跟踪探测坏了——绿色白给。
    """
    if not is_git_tracked(TRACKED_PROBE, dirpath):
        return False, "夹具里没有已跟踪的 `_` 脚本 ⇒ 豁免面无物可证，S2 的绿是白给的"
    witness = os.path.join("scripts", "_sandbox_witness.py")
    witness_abs = os.path.join(dirpath, witness)
    with open(witness_abs, "w", encoding="utf-8") as fh:
        fh.write("# 残留面见证件\n")
    try:
        if witness not in [rel for _abs, rel in stray_underscore_scripts(dirpath)]:
            return False, "夹具里的未跟踪 `_` 脚本没进候选 ⇒ 残留面无物可证，S3 的绿是白给的"
    finally:
        try:
            os.remove(witness_abs)
        except OSError:
            pass
    return True, ""


def selftest():
    """BUG-334 回归锁（判据无法自证绝不报绿）：`_`前缀规则必须豁免 git 跟踪资产、仍抓真临时脚本。

    - S0 夹具形状自证：temp 合成仓根里 tracked 面与 untracked 面各就各位（另配 M1 变异对照）。
    - S1 tracked 识别：`is_git_tracked("scripts/_tool_registry.py")` 必须为 True
      （夹具里它就是被 git add 过的真跟踪件，探测坏了则后续豁免全失效）。
    - S2 豁免生效：`stray_underscore_scripts()` 不得包含 `_tool_registry.py`。
    - S3 仍抓真临时脚本：在夹具里新建 untracked `_` 脚本，必须出现在候选中（否则规则被豁免规则误杀）。
    - S4/S5/S6 是纯函数格（`format_lines`），不碰盘。
    S1-S3 全打在 temp 合成仓根上，真 `scripts/` 树一字节不动（R153 的 hermetic 律）。
    """
    fails = []
    box = None
    try:
        try:
            box = _sandbox(os.path.abspath(tempfile.mkdtemp(prefix="ca-selftest-")))
        except (RuntimeError, OSError) as e:
            print("SELFTEST FAIL: 合成夹具起不来 ⇒ 判据看不见输入面，绝不报绿：%s" % e)
            sys.exit(1)  # NO_CALL_FACE J2
        # S0
        ok, why = _sandbox_ok(box)
        if not ok:
            fails.append("S0: %s" % why)
        # M1 变异对照：跟踪面抽空的夹具必被 S0 自拒（不配这格，S0 只是「一切正常时的顺手绿」）
        bad = os.path.abspath(tempfile.mkdtemp(prefix="ca-selftest-bad-"))
        try:
            _sandbox(bad, stage=False)
            bok, _bwhy = _sandbox_ok(bad)
        except (RuntimeError, OSError) as e:
            bok = False
            fails.append("M1: 变异夹具起不来（无法对照）：%s" % e)
        finally:
            _rmtree(bad)
        if bok:
            fails.append("M1: 跟踪面为空的夹具仍被 S0 放行 ⇒ 自证格是装饰")
        # S1
        if not is_git_tracked(TRACKED_PROBE, box):
            fails.append("S1: is_git_tracked('scripts/_tool_registry.py') 应为 True（git 探测失效）")
        # S2
        rels = [rel for _abs, rel in stray_underscore_scripts(box)]
        if TRACKED_PROBE in rels:
            fails.append("S2: _tool_registry.py 被误判为临时脚本（BUG-334 复现）")
        # S3
        tmp_rel = os.path.join("scripts", "_cleanup_selftest_tmp.py")
        tmp_abs = os.path.join(box, tmp_rel)
        created = False
        try:
            with open(tmp_abs, "w", encoding="utf-8") as fh:
                fh.write("# selftest probe\n")
            created = True
            rels2 = [rel for _abs, rel in stray_underscore_scripts(box)]
            if tmp_rel not in rels2:
                fails.append("S3: 真 `_` 临时脚本未被捕获（豁免规则误杀）")
        except OSError as e:
            fails.append(f"S3: 无法创建探针临时脚本：{e}")
        finally:
            if created:
                try:
                    os.remove(tmp_abs)
                except OSError:
                    pass
    finally:
        if box is not None:
            _rmtree(box)
            if os.path.exists(box):
                fails.append("夹具没清干净：%s" % box)
    # S4（BUG-368）：读数必须**逐条点名**，只给档数就无法核对构成
    lines4, dirty4 = format_lines(["a.db"], ["temp/x.db"], [], [])
    joined = "\n".join(lines4)
    if not dirty4 or "a.db" not in joined or "temp/x.db" not in joined:
        fails.append("S4: format_lines 未逐条点名（BUG-368：档数不可核对）")
    # S5：超过上限要折叠成「其余 N 件」，但总数仍如实给出
    many = ["d%d.db" % i for i in range(MAX_NAMES + 3)]
    lines5, _ = format_lines(many, [], [], [])
    j5 = "\n".join(lines5)
    if "其余 %d 件" % 3 not in j5:
        fails.append("S5: 超上限未折叠（应打印「其余 3 件」）")
    if ("共 %d）" % len(many)) not in lines5[0]:
        fails.append("S5: 折叠后总数未如实给出")
    # S6：豁免面必须可见（跟踪真源不进残留档、但要印出来证明豁免生效）
    lines6, dirty6 = format_lines([], [], [], ["scripts/_tool_registry.py"])
    if dirty6:
        fails.append("S6: 只有豁免项时不该判 dirty")
    if not any("豁免" in l and "_tool_registry.py" in l for l in lines6):
        fails.append("S6: 豁免项未印出（豁免不可见 ⇒ 虚报无法与真残留区分）")
    if fails:
        print("SELFTEST FAIL: " + "; ".join(fails))
        sys.exit(1)  # NO_CALL_FACE J2
    print("SELFTEST PASS: S0 夹具形状自证（含 M1 变异对照）/ S1 tracked 识别 / S2 `_tool_registry.py` 豁免 / "
          "S3 真临时脚本仍被抓（S0-S3 打在 temp 合成仓根）/ S4 逐条点名 / S5 超上限折叠且报总数 / S6 豁免面可见")
    sys.exit(0)  # NO_CALL_FACE J2


def main():
    if "--selftest" in sys.argv[1:]:
        sys.exit(selftest())
    check_only = "--check" in sys.argv[1:]
    root_stray = stray_root_dbs(ROOT)
    tfiles = temp_files(ROOT)
    uscripts = stray_underscore_scripts(ROOT)
    # 已跨到 temp/ 的临时脚本也算 temp 残留（一并清掉，幂等）
    for _abs, rel in uscripts:
        moved = os.path.join(ROOT, "temp", os.path.basename(rel))
        if moved not in tfiles:
            tfiles.append(moved)
    total = len(root_stray) + len(tfiles)
    if check_only:
        exempt = exempt_tracked_underscore(ROOT)
        lines, dirty = format_lines(root_stray, tfiles, uscripts, exempt)
        for line in lines:
            print(line)
        if dirty:
            sys.exit(1)
        print(
            "CLEAN: 仓库根仅 fist-mbt.db，temp/ 无残留，scripts/ 无 `_` 临时脚本 — 整洁"
            + ("（豁免 %d 件 git 跟踪的 `_` 真源：%s）" % (len(exempt), ", ".join(exempt)) if exempt else "")
        )
        return
    if total == 0 and not uscripts:
        print("CLEAN: 无需清理（仓库根仅 fist-mbt.db，temp/ 无残留，scripts/ 无临时脚本）")
        return
    removed = 0
    # 将 scripts/ 下 `_` 临时脚本移入 temp/（任务完即清，移走后正式工具目录干净）
    for abs_p, rel in uscripts:
        dst = os.path.join(ROOT, "temp", os.path.basename(rel))
        try:
            os.makedirs(os.path.join(ROOT, "temp"), exist_ok=True)
            os.replace(abs_p, dst)
            print(f"mv  {rel} → temp/")
            removed += 1
        except OSError as e:
            print(f"!! 移入失败 {rel}: {e}")
    # 移入后 temp/ 有了这些文件，走统一 temp 清理（若为临时脚本则一并删除）
    tfiles2 = temp_files(ROOT)
    for rel in tfiles2:
        p = os.path.join(ROOT, rel)
        try:
            os.remove(p)
            print(f"rm  {rel}")
            removed += 1
        except OSError as e:
            print(f"!! 删除失败 {rel}: {e}")
    for name in root_stray:
        p = os.path.join(ROOT, name)
        try:
            os.remove(p)
            print(f"rm  {name}")
            removed += 1
        except OSError as e:
            print(f"!! 删除失败 {name}: {e}")
    # 清空 temp 目录保留目录本身（若存在且已空）
    tdir = os.path.join(ROOT, "temp")
    try:
        if os.path.isdir(tdir) and not os.listdir(tdir):
            os.rmdir(tdir)
            print("rmdir temp/")
    except OSError:
        pass
    print(f"清理完成：共移除 {removed} 个生成物（保留交付库 fist-mbt.db）")


if __name__ == "__main__":
    main()