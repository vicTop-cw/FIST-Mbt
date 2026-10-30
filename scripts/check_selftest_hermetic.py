#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""自检 hermetic 守卫（R153）：`--selftest` 只许读合成夹具，不许读仓库现状面。

为什么需要它（R151 的根因面）：`--selftest` 的语义是「这把尺还能不能自证」，输入必须可控。
一旦自检里混了一格读真源（真 README / `run_guards.py --list` / 真仓 git），账一落后尺子就红：
`check_battery_count_doc.py` 的 `R1-real-readme-vs-real-list-green` 正是把「README 锚点落后」
判成「夹具坏了」——同因两格红，还连带 `check_selftest_inventory_doc.py` 的 X4 把它记成失联（rc=1→rc=2）。
R151 只治了那一把尺，**没有任何常驻判据扫这个形状** ⇒ 下一位再往自检里塞一格真源读，没人拦。

判据口径（两条形，机械可定，不做全量数据流）：
  H1 自检体的**调用闭包**里，I/O 原语（读：`open` / `io.open` / `os.listdir` / `os.walk` / `glob.glob`
     / `os.path.exists|isfile|isdir` / `subprocess.run|Popen|check_output|check_call` / `read_text`
     / `read_bytes`；写：`shutil.copy|copytree|rmtree` / `os.makedirs|mkdir|remove|unlink|replace`
     / `Path.write_text|write_bytes|mkdir|touch` / open 的 'w'/'a' 模式）的参数子树里，流进了
     「仓根派生锚点」或它的派生局部名。
     锚点种子 = 模块级常量的值表达式引用 `__file__`（`ROOT = os.path.dirname(os.path.dirname(
     os.path.abspath(__file__)))` 这一族），沿模块级常量之间的引用传播到不动点；
     函数内 `p = os.path.join(ROOT, DOC)` 这类局部派生名同样算污点——R151 那一格走的是
     自检 → `read_counts()` → `path = os.path.join(root or ROOT, RUN_GUARDS)` → `subprocess.run([…, path])`，
     只看「函数体提到过 ROOT」会漏、只看「读原语直参是 ROOT」也会漏，必须带一层局部污点传递。
     **锚点经形参流进同文件 helper 的 I/O 原语同样判**（调用点级一跳）：实测反证是
     `check_memory_log_dup.py` 的 S9——`find_logs(os.path.join(REPO_ROOT, "memory"))` 把锚点交给
     形参，helper 体内 `os.listdir(d)` 直接读它；这一格在 master 上**正红着**（788c5823 把日报移出
     跟踪面 ⇒ `memory/` 枚举不到日志），而只判直参的版本看不见。保守面：只在「实参被污染」的那处
     调用点判，同一 helper 被别处用 temp 目录调用不受影响。
     **只判「流进 I/O 原语」，不判「提到过锚点」**：第一版按后者判，现读 67 处里一大半是
     `os.path.relpath(p, ROOT)` / `cwd=ROOT` / 纯字符串拼接这类不读盘的引用——假红比漏红更坏。
  H2 自检体里 open 族调用的**整个首参是相对路径字面量**，且该路径在本仓存在
     （`open("scripts/README.md")` 只有 CWD=仓根时才成立 ⇒ 读的必然是现状面）。
     `os.path.join(tmp, "README.md")` 拼出来的夹具路径不判。

分档（红档 W/R/G 判红，记账档 S/T 只点名）——每一档都被一条实测形状逼出来，见 `CLASS_LABEL`：
  W 写探针进真树 / R 读现状面 / G 打真仓 / S 隔离 spawn 跑真尺子 / T 读写约定的 gitignored `temp/`。

退出码：0=全绿 / 1=违例逐条点名 / 2=判据无法自证（扫描面为空）/ 4=尺子自己坏了。
扫描面：`<root>/scripts/**/*.py` **递归**（R55/R82 的律逼出：普查只扫顶层 ⇒ 落在 `scripts/blackbox/`
里的尺天然漏出判定面，而「零执行面的尺=坏着的尺」那条对子目录正是盲的）。
漏红面（诚实标注，不冒充已覆盖）：锚点经函数**默认参**流进读原语不判
（`def git(args, cwd=ROOT)` 里 `subprocess.run(…, cwd=cwd)` 放过——判它会先把「自检显式传 temp cwd」
的合法用法判红）；**形参只判一跳**——helper 体内再把这个值交给**第二个** helper 不判；
`cwd`/`env` 给**字符串常量**（如 `cwd='.'`）算隔离——值里不含锚点，本尺看不到它
指向 temp 还是仓根（要看穿这一格得做常量求值，先把实测形状攒够再说）；跨模块 import 的 helper 不判；
三跳以上字符串拼装不判；子进程内部再读盘不判；`temp` 段只有落成**锚点常量**（或其一层局部派生）
才给 T 档豁免，内联 `os.path.join(ROOT, "temp", …)` 仍按 W/R 判红——这一手故意保守，
宁可不豁免也不白送豁免口。要扩必须先拿实测形状。
"""

import ast
import io
import os
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SELFTEST_FUNCS = ("selftest", "_selftest", "run_selftest", "self_test")
PATH_SUFFIXES = (".md", ".py", ".json", ".ps1", ".sh", ".yaml", ".yml", ".mbt", ".txt")

READ_PRIMITIVES = {
    "open", "io.open", "codecs.open", "os.listdir", "os.walk", "glob.glob", "glob.iglob",
    "os.path.exists", "os.path.isfile", "os.path.isdir", "os.stat", "os.getcwd",
    "subprocess.run", "subprocess.Popen", "subprocess.check_output", "subprocess.check_call",
    "shutil.copy", "shutil.copytree", "shutil.rmtree",
}
READ_METHODS = ("read_text", "read_bytes", "read_json")
WRITE_METHODS = ("write_text", "write_bytes", "mkdir", "touch")
WRITE_PRIMITIVES = {"os.makedirs", "os.mkdir", "os.remove", "os.unlink", "os.replace"}
# 本仓约定的临时区（AGENTS/电池律「临时件放 gitignored temp/」）：锚点派生且落在这一段的读写
# 不算「现状面」，记 T 档（与 S 同列，只记账不判红）。判据依据是这条明文约定，不是按名字猜。
SCRATCH_SEGMENTS = ("temp",)
SKIP_DIRS = {"__pycache__"}


def fatal(msg):
    print("FATAL: %s" % msg)
    return 2


def dotted(node):
    """调用目标的全名：`open` / `io.open` / `subprocess.run`；取不到返回 None。"""
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name):
        return "%s.%s" % (node.value.id, node.attr)
    return None


def names_in(node):
    return {n.id for n in ast.walk(node) if isinstance(n, ast.Name)}


def local_names(fn):
    """函数内局部名（形参 + 绑定目标）——挡住「局部遮蔽被误当锚点引用」的假红。"""
    loc = {a.arg for a in fn.args.args} | {a.arg for a in fn.args.kwonlyargs}
    if fn.args.vararg:
        loc.add(fn.args.vararg.arg)
    if fn.args.kwarg:
        loc.add(fn.args.kwarg.arg)
    for sub in ast.walk(fn):
        if isinstance(sub, ast.Assign):
            loc |= {t.id for t in sub.targets if isinstance(t, ast.Name)}
        elif isinstance(sub, (ast.AugAssign, ast.AnnAssign)) and isinstance(sub.target, ast.Name):
            loc.add(sub.target.id)
        elif isinstance(sub, (ast.For, ast.comprehension)):
            loc |= {t.id for t in ast.walk(sub.target) if isinstance(t, ast.Name)}
        elif isinstance(sub, ast.withitem) and sub.optional_vars is not None:
            loc |= {t.id for t in ast.walk(sub.optional_vars) if isinstance(t, ast.Name)}
        elif isinstance(sub, ast.ExceptHandler) and sub.name:
            loc.add(sub.name)
    return loc


def module_level_assigns(tree):
    consts = {}
    for st in tree.body:
        if isinstance(st, ast.Assign):
            targets = [t.id for t in st.targets if isinstance(t, ast.Name)]
        elif isinstance(st, ast.AnnAssign) and isinstance(st.target, ast.Name):
            targets = [st.target.id]
        else:
            continue
        if st.value is None:
            continue
        refs = names_in(st.value)
        for t in targets:
            consts[t] = refs
    return consts


def module_anchors(tree):
    """仓根派生锚点：种子=模块级常量的值引用 `__file__`，沿常量间引用传播到不动点。"""
    consts = module_level_assigns(tree)
    anchors = {n for n, r in consts.items() if "__file__" in r}
    changed = True
    while changed:
        changed = False
        for n, r in consts.items():
            if n not in anchors and r & anchors:
                anchors.add(n)
                changed = True
    return anchors


def module_functions(tree):
    return {f.name: f for f in tree.body if isinstance(f, ast.FunctionDef)}


def has_scratch_segment(node):
    return any(isinstance(c, ast.Constant) and isinstance(c.value, str)
               and c.value.strip("/\\") in SCRATCH_SEGMENTS for c in ast.walk(node))


def scratch_names(tree, anchors):
    """锚点派生、且值里带 `temp` 段的模块级常量 ⇒ 本仓约定的临时区名（读写它不算现状面）。
    沿常量互引传播：`SELF_SUB = SELFTEST_DIR / "x"` 同样是临时区。"""
    nodes = {}
    for st in tree.body:
        if isinstance(st, ast.Assign):
            targets = [t.id for t in st.targets if isinstance(t, ast.Name)]
        elif isinstance(st, ast.AnnAssign) and isinstance(st.target, ast.Name):
            targets = [st.target.id]
        else:
            continue
        if st.value is None:
            continue
        for t in targets:
            nodes[t] = st.value
    out = set()
    changed = True
    while changed:
        changed = False
        for n, val in nodes.items():
            if n in out or n not in anchors:
                continue
            if has_scratch_segment(val) or any(r in out for r in names_in(val)):
                out.add(n)
                changed = True
    return out


def selftest_fns(tree):
    fns = module_functions(tree)
    return [fns[n] for n in SELFTEST_FUNCS if n in fns]


def is_open_call(node):
    f = node.func
    if isinstance(f, ast.Name):
        return f.id == "open"
    if isinstance(f, ast.Attribute):
        base = f.value.id if isinstance(f.value, ast.Name) else ""
        if base in ("io", "codecs") and f.attr == "open":
            return True
        return f.attr in READ_METHODS
    return False


def bare_literal_reads(fn, root):
    hits = []
    for sub in ast.walk(fn):
        if not isinstance(sub, ast.Call) or not is_open_call(sub) or not sub.args:
            continue
        first = sub.args[0]
        if not (isinstance(first, ast.Constant) and isinstance(first.value, str)):
            continue
        norm = first.value.replace("\\", "/")
        if os.path.isabs(first.value) or norm.startswith("/") or "$" in norm:
            continue
        if norm.endswith(PATH_SUFFIXES) and os.path.exists(os.path.join(root, norm)):
            hits.append((norm, sub.lineno))
    return hits


def closure(fn, funcs):
    """自检体的调用闭包 [(FunctionDef, 调用链)]，环安全。"""
    out = [(fn, [fn.name])]
    seen = {id(fn)}
    stack = [(fn, [fn.name])]
    while stack:
        cur, chain = stack.pop()
        for sub in ast.walk(cur):
            if isinstance(sub, ast.Call) and isinstance(sub.func, ast.Name):
                callee = funcs.get(sub.func.id)
                if callee is not None and id(callee) not in seen:
                    seen.add(id(callee))
                    out.append((callee, chain + [callee.name]))
                    stack.append((callee, chain + [callee.name]))
    return out


def tainted_locals(fn, anchors):
    """一层（迭代到不动点）局部污点：`= <含锚点或已污名> 的表达式` 的目标名算污点。
    只认单目标裸赋值；形参/默认参永不污点（防「自检显式传 temp 路径」被误判）。"""
    shadowed = local_names(fn)
    tainted = set()
    changed = True
    while changed:
        changed = False
        for sub in ast.walk(fn):
            if isinstance(sub, ast.Assign) and len(sub.targets) == 1 and isinstance(sub.targets[0], ast.Name):
                name = sub.targets[0].id
                if name in tainted:
                    continue
                src = names_in(sub.value) - shadowed
                if src & (anchors | tainted):
                    tainted.add(name)
                    changed = True
    return tainted


def mode_of(call):
    mode = ""
    if len(call.args) > 1 and isinstance(call.args[1], ast.Constant):
        mode = str(call.args[1].value)
    for kw in call.keywords:
        if kw.arg == "mode" and isinstance(kw.value, ast.Constant):
            mode = str(kw.value.value)
    return mode


def classify_primitive(call, prim_name, sources, scratch, hit):
    """把「锚点流进原语」的调用分五档，形状由实测逼出（不按名字硬猜）：
      W 写：open 带 'w'/'a' 模式，或 shutil / `Path.write_text` / `os.makedirs` 这类写删原语
         ⇒ 自检往**真树**里落件（实测：check_publish_payload.py 的 M1/M2/M3 三格就是往仓根写探针
         再删——电池契约「只读且快」被破）。写原语这一面第一版完全看不见：实测
         `scripts/blackbox/e2e_native_heap_probe.py` 用 `Path(...).write_text(...)` 落盘，
         旧判据一条都不报（漏红面比假红更坏，故本版补上）。
      R 读：读仓库现状面（open / glob / listdir / walk / exists / read_text…）⇒ R151 那一格的形状。
      G 打真仓：subprocess 的 `cwd`/`env` **值里带锚点**（或干脆没给）⇒ 子进程看见的就是现状面。
         第一版只认「带没带 cwd= 旗」，实测 11 处里 9 处写的是 `cwd=ROOT` / `cwd=cwd or ROOT`
         （`git ls-files` 打真仓）——白名单反成豁免口，把本尺要抓的形状全洗成不判红，故必须看值。
      S 隔离 spawn：`cwd`/`env` 的值不来自锚点 ⇒ 「跑真尺子、打合成输入」是本仓认可的可测形状
         （实测：check_exit_code_contract.py 用 cwd=temp 目录 + GIT_DIR=<temp>/not-a-repo.git 起自己）。
      T 临时区：命中的锚点名**全部**是「锚点派生 + 值里带 `temp` 段」的模块级常量（含其一层局部派生）
         ⇒ 读写落在 AGENTS/电池律明文约定的 gitignored `temp/`，属可控夹具，只记账不判红
         （实测逼出：`e2e_native_heap_probe.py` 的 `SELFTEST_DIR = ROOT / "temp" / …` + `shutil.rmtree`
         被上一版判成 W 假红——那条写的正是本仓自己的临时区，不是现状面）。
      W/R/G 是红档，S/T 只记账。内联拼的 `"temp"` 字面量段不豁免（只有落成锚点常量才认），
      这一手是**保守**：宁可漏豁免也不白送一次豁免口。
    """
    attr = call.func.attr if isinstance(call.func, ast.Attribute) else ""
    if hit and all(h in scratch for h in hit):
        return "T"
    # R115：**copy 类原语的源是读面、目标是写面**。原实现对所有 `shutil.*` 一律判 W，
    # 于是 `shutil.copy(ROOT/x, td/y)` 这种「只读真仓、写临时目录」的合规夹具被记成
    # 「写探针进真树」（实测 check_push_guard.py 3 处即此类假红）。
    # `shutil.move` 的源会被**删除** ⇒ 不列入 copy 类，仍按写面算。
    _COPY_FAMILY = ("shutil.copy", "shutil.copy2", "shutil.copyfile", "shutil.copytree")
    if prim_name in _COPY_FAMILY and len(call.args) >= 2:
        _dst = names_in(call.args[1]) & sources
        _src = names_in(call.args[0]) & sources
        if _dst:
            return "T" if all(h in scratch for h in _dst) else "W"
        if _src:
            return "T" if all(h in scratch for h in _src) else "R"
        return "S"
    # R118：`write_text` / `write_bytes` 的**内容是数据、不是落点** —— 只看 receiver。
    # 实测：`check_plugin_sync.py` 的 `(tmp/p.json).write_text('{"version": "%s"}' % version)`
    # 写进的是 tempdir 的 p.json，`version` 只是写进去的值，却被原实现记成 W。
    if attr in ("write_text", "write_bytes"):
        _recv = names_in(call.func.value) & sources if isinstance(call.func, ast.Attribute) else set()
        if _recv:
            return "T" if all(h in scratch for h in _recv) else "W"
        return "S"
    is_write = (prim_name.startswith("shutil.") or prim_name in WRITE_PRIMITIVES
                or attr in WRITE_METHODS)
    if prim_name in ("open", "io.open", "codecs.open") and any(c in mode_of(call) for c in "wa"):
        is_write = True
    if is_write:
        return "W"
    if prim_name.startswith("subprocess."):
        kws = [kw for kw in call.keywords if kw.arg in ("cwd", "env")]
        # 污染优先：任何一个 cwd/env 的值吃进锚点就是打真仓（实测 whisperer.py L26
        # `cwd=cwd or ROOT … env=moon_env()`——只看「带没带隔离旗」会被无关的 env= 白送一次豁免）。
        contaminated = any(names_in(kw.value) & sources for kw in kws)
        return "G" if (contaminated or not kws) else "S"
    return "R"


def io_primitive_hits(fn, anchors, taint, scratch):
    """I/O 原语（读 + 写两面）调用里，参数子树命中锚点/污点名的位置。
    锚点要被局部遮蔽检查挡住（防「自检里 `ROOT = temp` 重新赋值」被误判），
    但污点名本来就是局部变量——再减一次局部集会把 `p = os.path.join(ROOT, …)` 这条链自己抹掉。"""
    out = []
    shadowed = local_names(fn)
    sources = (anchors - shadowed) | taint
    for sub in ast.walk(fn):
        if not isinstance(sub, ast.Call):
            continue
        name = dotted(sub.func)
        attr = sub.func.attr if isinstance(sub.func, ast.Attribute) else ""
        is_io = (name in READ_PRIMITIVES or name in WRITE_PRIMITIVES
                 or attr in READ_METHODS or attr in WRITE_METHODS)
        if not is_io:
            continue
        arg_nodes = list(sub.args) + [kw.value for kw in sub.keywords]
        if isinstance(sub.func, ast.Attribute):
            # 方法调用的锚点常挂在**受体**上而不是实参里：`Path(p).write_text(...)` /
            # `(ROOT / "x").read_text()` —— 只收集实参会把这一族整面漏掉（实测漏红面）。
            arg_nodes.append(sub.func.value)
        arg_names = set()
        for a in arg_nodes:
            arg_names |= names_in(a)
        hit = sorted(arg_names & sources)
        if hit:
            out.append((name or attr or "?", sub.lineno, hit,
                        classify_primitive(sub, name or attr or "?", sources, scratch, hit)))
    return out


def callee_params(fn):
    ps = [a.arg for a in fn.args.args]
    if fn.args.vararg:
        ps.append(fn.args.vararg.arg)
    return ps


def param_flow_hits(fn, funcs, anchors, taint, scratch, chain):
    """调用点级的一跳判定：本函数体把锚点表达式交给**同文件 helper 的形参**，而那个形参在 helper
    体内被直接喂给 I/O 原语 ⇒ 判违例。
    实测反证（第五轮定形）：`check_memory_log_dup.py` 的 S9 走
    `find_logs(os.path.join(REPO_ROOT, "memory"))` → helper 体内 `os.listdir(d)`——锚点经形参流进
    读原语。原判据把「形参永不污点」写成漏红面，于是**这一格在 master 上正红着**（788c5823 把日报
    移出跟踪面 ⇒ `memory/` 枚举不到日志 ⇒ S9 报「仓库内一份日志都没读到」），本尺却看不见它。
    保守面：**只在这处调用点判**——同一 helper 被别处用 temp 目录调用不受影响；两跳以上（helper 再调
    helper）不判。
    """
    out = []
    shadowed = local_names(fn)
    sources = (anchors - shadowed) | taint
    for sub in ast.walk(fn):
        if not (isinstance(sub, ast.Call) and isinstance(sub.func, ast.Name)):
            continue
        callee = funcs.get(sub.func.id)
        if callee is None or callee is fn:
            continue
        params = callee_params(callee)
        bound = {}
        for i, a in enumerate(sub.args):
            if i < len(params):
                bound[params[i]] = a
        for kw in sub.keywords:
            if kw.arg in params:
                bound[kw.arg] = kw.value
        for pname, argn in bound.items():
            arg_src = names_in(argn) & sources
            if not arg_src:
                continue
            # helper **体内**再派生一层（`q = d + "/x"` 之后读 q）同样算——污点跟着形参走
            inner = {pname} | tainted_locals(callee, {pname})
            # 实参只吃进临时区名 ⇒ 这一跳连同它在 helper 内的派生都留在 T，别升级成红档
            local_scratch = scratch | inner if arg_src <= scratch else scratch
            for prim, lineno, _hit, cls in io_primitive_hits(callee, set(), inner, local_scratch):
                out.append((cls,
                            "%s L%d 把 %s 经形参 `%s` 交给 %s()（其体内 L%d `%s(...)` 直接读写它；链：%s）"
                            % (fn.name, sub.lineno, ",".join(sorted(arg_src)), pname,
                               callee.name, lineno, prim, chain)))
    return out


def violations_of(tree, root):
    anchors = module_anchors(tree)
    scratch = scratch_names(tree, anchors)
    funcs = module_functions(tree)
    out = []
    for fn in selftest_fns(tree):
        for body, chain in closure(fn, funcs):
            taint = tainted_locals(body, anchors)
            # 临时区名也要走同一层局部污点：`p = SELFTEST_DIR / "x"` 之后写 p 仍是临时区
            scratch |= tainted_locals(body, scratch) if scratch else set()
            for prim, lineno, hit, cls in io_primitive_hits(body, anchors, taint, scratch):
                out.append((cls, fn.name,
                            "%s L%d `%s(...)` 的参数吃进 %s（链：%s）"
                            % (body.name, lineno, prim, ",".join(hit), "→".join(chain))))
            for path, lineno in bare_literal_reads(body, root):
                out.append(("R", fn.name,
                            "%s L%d 裸相对字面量真源读 `%s`（链：%s）"
                            % (body.name, lineno, path, "→".join(chain))))
            for cls, note in param_flow_hits(body, funcs, anchors, taint, scratch,
                                             "→".join(chain)):
                out.append((cls, fn.name, note))
    return out


def scan(root):
    """扫描面从 <root>/scripts/**/*.py **递归**派生（不手写尺子清单）。
    递归这条由 R55/R82 的律逼出：普查只扫 `scripts/` 顶层 ⇒ 落在 `scripts/blackbox/` 的尺
    天然漏出判定面，而「零执行面的尺=坏着的尺」那一条对子目录里的尺正是盲的。"""
    sdir = os.path.join(root, "scripts")
    if not os.path.isdir(sdir):
        return [], [], []
    files = []
    for dirpath, dirnames, filenames in os.walk(sdir):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for f in sorted(filenames):
            if f.endswith(".py"):
                rel = os.path.relpath(os.path.join(dirpath, f), sdir)
                files.append(rel.replace(os.sep, "/"))
    files.sort()
    viol, unreadable = [], []
    for rel in files:
        path = os.path.join(sdir, *rel.split("/"))
        try:
            with io.open(path, encoding="utf-8-sig", errors="replace") as fh:
                tree = ast.parse(fh.read())
        except (SyntaxError, ValueError, OSError) as e:
            unreadable.append("%s（%s）" % (rel, type(e).__name__))
            continue
        if not selftest_fns(tree):
            continue
        for cls, fn, note in violations_of(tree, root):
            viol.append((rel, cls, fn, note))
    return files, viol, unreadable


def fixture(path, text):
    with io.open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


CLASS_LABEL = {
    "W": "自检写探针进真树（违电池契约「只读」）",
    "R": "自检读仓库现状面（R151 那一格的形状）",
    "G": "自检用 git/subprocess 打真仓",
    "S": "自 spawn 跑真尺子（合成输入可接受，但仍要点名——子进程内写盘本尺看不到）",
    "T": "读写落在本仓约定的 gitignored temp/ 临时区（可控夹具，只记账不判红）",
}
RED_CLASSES = ("W", "R", "G")
DIAG_CLASSES = ("S", "T")

# ══════════════════════════════════════════════════════════════════════
# ★★ 棘轮基线（R218 / Lane EC）—— **本判据原本是「无条件红」**
# ══════════════════════════════════════════════════════════════════════
#
# ## 病历
# R153 立尺时只写了「有 W/R/G 类违例 ⇒ return 1」，**没有上限、没有基线**。
# ⇒ 它从上线起**一直红着**，`known-red` 的 `blame` 挂了很久是 `unknown`。
# ⇒ **「无条件红」比「没有判据」更糟 —— 它训练人忽略红色。**（R50 已立此判例）
#
# ## 为什么「清零」不是合理终态（这是我判 `blame="judge"` 的依据）
# 实测 100 处 / 43 个文件，而**大多数是校准/标定性质**：
#   · `check_bug_refs.py` 自检里明写「**校准格**：真实语料上的注释面 ORPHAN 必须恰好等于
#     棘轮上限——降了就说明该收紧上限，升了就说明悬空引用变多」
#   · 判例-32 要求「**探针必须先在新鲜样本上标定**」—— 标定必然读真仓
# ⇒ **要求清零，等于要求所有标定格放弃标定能力。那不是「更严」，是「更假」。**
#
# ## 所以改成：**钉基线，只许降不许升**
# 与 `check_scripts_naming` / `check_selftest_call_face` 同构（本仓既有棘轮惯例）。
# **上升 ⇒ FAIL**（新增没有该性质的自检要自己负责）；**下降 ⇒ 更新基线**（还债）。
#
# ## ⚠️ 基线是实测值，不是理想值
# 它钉住的是「**当前实际欠多少**」，不是「应该欠多少」。
# **⇒ 它不是标准，是账。**（标准是「只许降」这条规则本身。）
# ⚠️ **基线取「HEAD 已提交态」的实测值**（不是工作树瞬时值）：
#    测得时 `check_scripts_naming.py` 正被另一 lane 在途修改（R 档 68→70→75 实时涨），
#    若按工作树瞬时值定，它一提交就「overshoot」误红。
#    ⇒ **基线是账，钉的是「已落盘欠多少」，在途改动由那一方自己同批更新。**
#
# ══ R56 上调 R 70 → 73（**唯一一次「上调」，依据与反证都写在下面**）══
# 原因：`check_scripts_naming.py` 新增 4 格准入条件机核，其中 5 处读真仓。
#   §1 先**真的**降了 2 处（改 temp 合成树，规则强度不变，18 格仍全 PASS）：
#       · 格13「零引用被拒」`_fake13`  → temp 树（不需要真仓任何文件）
#       · 格16「假名不被误认」`_r16b`  → temp 树（同上）
#   §2 剩 3 处**经判例-32 认定必须真仓**，是「新增判据的标定成本」而非「债没还」：
#       · 格14「电池登记的必须拒」→ 要**真的** `run_guards.py`
#       · 格15「真白名单全过」    → 要**真的** `NAMING.md` + 真引用面
#       · 格16「真共享件被认出」  → 传空树等于没标定
# ⇒ 净 +3（实测 75 → 73，**不是 75 → 73 → 为了让基线算准而编的数**）。
# **为什么这不是「为了变绿改常量」**（R52 立的头号失效路径）：
#   ① 上调量 == 「经判例-32 论证不可降的格数」，不是「还差多少就到 0」；
#   ② 同批真的降了 2 处（不是只调基线）；
#   ③ 3 处每一处都点名到具体格与具体理由，可被下一人复核。
BASELINE = {"W": 1, "R": 73, "G": 31}


def selftest():
    fails, executed = [], []
    made = []

    def cell(name, ok, detail=""):
        executed.append(name)
        if not ok:
            fails.append((name, detail))

    d = tempfile.mkdtemp(prefix="sth-")
    sdir = os.path.join(d, "scripts")
    os.makedirs(sdir, exist_ok=True)
    fixture(os.path.join(sdir, "README.md"), "让 scripts/README.md 在夹具根下存在\n")
    head = "import io, os, subprocess, sys, tempfile\nROOT = os.path.dirname(os.path.abspath(__file__))\n"

    def run(fname, src):
        made.append(fname)
        fixture(os.path.join(sdir, fname), src)
        with io.open(os.path.join(sdir, fname), encoding="utf-8") as fh:
            tree = ast.parse(fh.read())
        return violations_of(tree, d)

    def run_sub(fname, src):
        """同一份判据跑在 `scripts/blackbox/` 子目录里——扫描面递归这条只由这一族格钉住。"""
        made.append("blackbox/" + fname)
        bdir = os.path.join(sdir, "blackbox")
        if not os.path.isdir(bdir):
            os.makedirs(bdir)
        fixture(os.path.join(bdir, fname), src)
        with io.open(os.path.join(bdir, fname), encoding="utf-8") as fh:
            tree = ast.parse(fh.read())
        return violations_of(tree, d)

    def cls_of(v, needle):
        return [x[0] for x in v if needle in x[2]]

    v = run("w_probe.py", head + "PROBE = os.path.join(ROOT, 'probe.txt')\n"
            'def selftest():\n    io.open(PROBE, "w").write("x")\n    return 0\n')
    cell("W1-anchor-derived-path-written-by-selftest", cls_of(v, 'PROBE') == ["W"], repr(v))

    # R115/R116：`shutil.copy*` 的**源是读面(R)、目标是写面(W)**。原实现对所有 `shutil.*`
    # 一律判 W，把「只读真仓、写临时目录」的合规夹具记成「写探针进真树」
    # （实测 check_push_guard.py 3 处假写）。夹具写进**独立目录**，不进影数面。
    def run_iso(fname, src_text):
        idir = os.path.join(d, "iso")
        if not os.path.isdir(idir):
            os.makedirs(idir)
        fixture(os.path.join(idir, fname), src_text)
        with io.open(os.path.join(idir, fname), encoding="utf-8") as fh:
            return violations_of(ast.parse(fh.read()), idir)

    v = run_iso("copy_src_read.py", head + "import shutil\nSRC = os.path.join(ROOT, 'a.txt')\n"
                    "def selftest():\n    shutil.copy(SRC, os.path.join(tempfile.mkdtemp(), 'b.txt'))\n"
                    "    return 0\n")
    cell("R115-copy-source-is-read-not-write", cls_of(v, "SRC") == ["R"], repr(v))

    v = run_iso("copy_dst_write.py", head + "import shutil\nDST = os.path.join(ROOT, 'b.txt')\n"
                    "def selftest():\n    shutil.copy(os.path.join(tempfile.mkdtemp(), 'a.txt'), DST)\n"
                    "    return 0\n")
    cell("R115-copy-dest-is-write", cls_of(v, "DST") == ["W"], repr(v))

    # 写原语的 Path 面：第一版只认 open 的 w 模式与 shutil，实测 `e2e_native_heap_probe.py` 用
    # `Path(SELFTEST_DIR / "x").write_text(...)` 落盘，一条都不报 ⇒ 漏红面。摘掉 WRITE_METHODS 这格必红。
    v = run("w_pathtext.py", head + "import pathlib\nPX = os.path.join(ROOT, 'px.txt')\n"
            "def selftest():\n    pathlib.Path(PX).write_text('y')\n    return 0\n")
    cell("W2-method-anchor-on-receiver_pathlib-write_text", cls_of(v, "PX") == ["W"], repr(v))

    # T 档：本仓明文约定「临时件放 gitignored temp/」——锚点常量带 temp 段的读写是可控夹具，不是现状面
    # （实测逼出：`SELFTEST_DIR = ROOT / "temp" / "native_heap_probe_selftest"` 上一版判成 W 假红）。
    v = run("t_scratch.py", head + 'TMPD = os.path.join(ROOT, "temp", "probe_selftest")\n'
            "def selftest():\n    io.open(TMPD, 'w').write('x')\n"
            "    import shutil\n    shutil.rmtree(TMPD)\n    return 0\n")
    cell("T1-temp-derived-anchor-write-is-diag-not-red",
         cls_of(v, "TMPD") == ["T", "T"], repr(v))

    # 局部派生也要跟着豁免：`q = TMPD + '.log'` 之后写 q 仍是临时区
    v = run("t_local.py", head + 'TMPD = os.path.join(ROOT, "temp", "probe_selftest")\n'
            "def selftest():\n    q = TMPD + '.log'\n    io.open(q, 'w').write('x')\n    return 0\n")
    cell("T2-local-derivation-of-scratch-still-diag", cls_of(v, "q") == ["T"], repr(v))

    # 豁免只认「落成锚点常量」的 temp 段；内联拼的不给（宁保守也不白送豁免口）
    v = run("w_inline_temp_literal.py", head + "def selftest():\n"
            "    io.open(os.path.join(ROOT, 'temp', 'x.txt'), 'w').write('y')\n    return 0\n")
    cell("W3-inline-temp-literal-segment-buys-no-exemption", cls_of(v, "ROOT") == ["W"], repr(v))

    # os 族写删面（实测 cleanup_artifacts.py L194 `os.remove` 落进真 scripts/ 树）
    v = run("w_makedirs.py", head + "SUB = os.path.join(ROOT, 'sub')\n"
            "def selftest():\n    os.makedirs(SUB, exist_ok=True)\n    return 0\n")
    cell("W4-os-family-write-primitive-anchor-is-red", cls_of(v, "SUB") == ["W"], repr(v))

    v = run("r_anchor.py", head + 'DOC = "README.md"\ndef selftest():\n'
            "    return open(os.path.join(ROOT, DOC)).read()\n")
    cell("R1-anchor-flows-into-open", cls_of(v, "ROOT") == ["R"], repr(v))

    v = run("r_chain.py", head + 'RUN = os.path.join(ROOT, "run_guards.py")\n'
            "def read_counts():\n    p = os.path.join(ROOT, RUN)\n"
            "    return subprocess.run([p])\ndef selftest():\n    return read_counts()\n")
    cell("R2-transitive-helper-local-taint", cls_of(v, "p") == ["G"], repr(v))

    v = run("s_selfspawn.py", head + "SELF_PATH = os.path.join(ROOT, 'scripts', 'me.py')\n"
            "def selftest():\n    return subprocess.run((sys.executable, SELF_PATH), cwd='.')\n")
    cell("S1-self-spawn-classified-separately-not-dropped", cls_of(v, "SELF_PATH") == ["S"], repr(v))

    # 隔离与否看**值**不看旗名：`cwd=ROOT` 只是把仓根交给子进程，不是隔离（实测 11 处 S 里 9 处这形状）
    v = run("g_cwd_anchor.py", head + "def selftest():\n"
            "    return subprocess.run(['git', 'ls-files'], cwd=ROOT, capture_output=True)\n")
    cell("G1-anchor-derived-cwd-is-not-isolation", cls_of(v, "ROOT") == ["G"], repr(v))

    # 无关的 env= 不许替被污染的 cwd= 买豁免（实测 whisperer.py L26 正是 `cwd=cwd or ROOT … env=moon_env()`）
    v = run("g_env_cover.py", head + "def selftest():\n"
            "    return subprocess.run(['git'], cwd=ROOT, env=os.environ)\n")
    cell("G2-unrelated-env-does-not-buy-isolation", cls_of(v, "ROOT") == ["G"], repr(v))

    v = run("mention_only.py", head + "def rel(p):\n    return os.path.relpath(p, ROOT)\n"
            "def selftest():\n    return rel('a')\n")
    cell("R3-anchor-mentioned-but-never-read-not-flagged", v == [], repr(v))

    v = run("param_cwd.py", head + "def git(args, cwd=ROOT):\n"
            "    return subprocess.run(args, cwd=cwd)\ndef selftest():\n"
            "    return git(['x'], cwd=tempfile.mkdtemp())\n")
    cell("R4-explicit-temp-cwd-via-param-not-flagged", v == [], repr(v))

    v = run("bare_literal.py", "import io\ndef selftest():\n"
            '    with io.open("scripts/README.md") as f:\n        return f.read()\n')
    cell("R5-bare-relative-literal-read-flagged", cls_of(v, "README.md") == ["R"], repr(v))

    v = run("clean_fixture.py", "import os, tempfile\nD = os.path.join(tempfile.mkdtemp(), 'x')\n"
            "def selftest():\n    p = os.path.join(D, 'README.md')\n"
            "    open(p, 'w').write('x')\n    return open(p).read()\n")
    cell("R6-clean-synthetic-fixture-not-flagged", v == [], repr(v))

    v = run("shadow_rebind.py", head + "def selftest():\n    ROOT = tempfile.mkdtemp()\n"
            '    return open(os.path.join(ROOT, "x")).read()\n')
    cell("R8-local-rebind-of-anchor-name-not-flagged", v == [], repr(v))

    v = run("bare_literal_absent.py", "import io\ndef selftest():\n"
            '    with io.open("scripts/NOPE-9d2f.md") as f:\n        return f.read()\n')
    cell("R9-relative-literal-that-does-not-exist-in-root-not-flagged", v == [], repr(v))

    v = run("main_face_only.py", head + "def main_face():\n    return open(os.path.join(ROOT, 'x'))\n"
            "def selftest():\n    return 0\n")
    cell("R7-main-face-read-does-not-taint-selftest", v == [], repr(v))

    v = run_sub("b_realread.py", head + 'DOC = "README.md"\ndef selftest():\n'
                "    return open(os.path.join(ROOT, DOC)).read()\n")
    cell("F3-blackbox-fixture-judged-by-same-rule", cls_of(v, "ROOT") == ["R"], repr(v))

    # 一跳形参流（第五轮定形：master 上 check_memory_log_dup.py 的 S9 正红着，原判据看不见）
    v = run("p_paramflow.py", head + "def logs(d):\n    return os.listdir(d)\n"
            "def selftest():\n    return logs(ROOT)\n")
    cell("P1-anchor-flows-through-helper-param", cls_of(v, "经形参") == ["R"], repr(v))

    v = run("p_temp_arg.py", head + "def logs(d):\n    return os.listdir(d)\n"
            "def selftest():\n    return logs(tempfile.mkdtemp())\n")
    cell("P2-same-helper-called-with-temp-arg-not-flagged", v == [], repr(v))

    v = run("p_param_noio.py", head + "def rel(d):\n    return os.path.relpath('x', d)\n"
            "def selftest():\n    return rel(ROOT)\n")
    cell("P3-param-never-fed-into-io-primitive-not-flagged", v == [], repr(v))

    v = run("p_scratch_arg.py", head + 'TMPD = os.path.join(ROOT, "temp", "logs")\n'
            "def logs(d):\n    return os.listdir(d)\n"
            "def selftest():\n    return logs(TMPD)\n")
    cell("P4-scratch-arg-through-param-stays-diag", cls_of(v, "经形参") == ["T"], repr(v))

    files, viol, unread = scan(os.path.join(d, "no-such-dir"))
    cell("F0-empty-scan-face-yields-no-face", (files, viol, unread) == ([], [], []), repr((files, viol, unread)))

    planted = sorted(["w_probe.py", "w_pathtext.py", "w_makedirs.py",
                      "w_inline_temp_literal.py", "t_scratch.py", "t_local.py",
                      "r_anchor.py", "r_chain.py", "s_selfspawn.py",
                      "g_cwd_anchor.py", "g_env_cover.py", "bare_literal.py",
                      "p_paramflow.py", "p_scratch_arg.py",
                      "blackbox/b_realread.py"])

    files, viol, unread = scan(d)
    offenders = sorted({f for f, _c, _fn, _note in viol})
    cell("F2-face-derived-from-disk-and-offenders-are-planted",
         len(files) == len(made) and offenders == planted,
         repr((len(files), len(made), offenders, planted)))
    # 递归这条只能由「面里真有子目录件」钉住：把 scan 退回 listdir 顶层，F2/F5 一起红
    cell("F5-face-recurses-into-blackbox-subdir",
         "blackbox/b_realread.py" in files and "blackbox/b_realread.py" in offenders,
         repr(files))

    rc1, reds, diags, _rt1 = verdict(viol)
    red_offenders = sorted({f for f, c, _fn, _n in viol if c in RED_CLASSES})
    classes = {c for _f, c, _fn, _n in viol}
    diag_only = {"s_selfspawn.py", "t_scratch.py", "t_local.py", "p_scratch_arg.py"}
    # 断言按语义写不写死条数：红档恰是「除记账夹具外的全部违例件」，记账档不进取红面；
    # 下一档变更（或冒出第五档）时这一格不会假红，但 `reds+diags==len(viol)` 会抓住「有条目两头不算」。
    cell("F1-red-face-counts-only-WRG-and-S-T-listed-as-diag",
         rc1 == 1 and classes <= set(RED_CLASSES + DIAG_CLASSES)
         and reds == len([v for v in viol if v[1] in RED_CLASSES])
         and reds + diags == len(viol)
         and red_offenders == [f for f in planted if f not in diag_only],
         repr((rc1, reds, diags, sorted(classes), red_offenders)))

    # S 档单独成面时必须判绿：否则「跑真尺子打合成输入」这一认可形状会被本尺当红（假红比漏红更坏）
    d2 = tempfile.mkdtemp(prefix="sth-s-")
    os.makedirs(os.path.join(d2, "scripts"), exist_ok=True)
    fixture(os.path.join(d2, "scripts", "s_selfspawn.py"),
            head + "SELF_PATH = os.path.join(ROOT, 'scripts', 'me.py')\n"
                   "def selftest():\n    return subprocess.run((sys.executable, SELF_PATH), cwd='.')\n")
    _f2, viol2, _u2 = scan(d2)
    rc2, reds2, diags2, _rt2 = verdict(viol2)
    cell("F4-self-spawn-alone-is-not-red", (rc2, reds2, diags2) == (0, 0, 1), repr((rc2, reds2, diags2, viol2)))

    # T 档单独成面同样必须判绿（这一条是 T 档存在的全部理由：不绿就是把约定临时区判成债）
    d3 = tempfile.mkdtemp(prefix="sth-t-")
    os.makedirs(os.path.join(d3, "scripts"), exist_ok=True)
    fixture(os.path.join(d3, "scripts", "t_scratch.py"),
            head + 'TMPD = os.path.join(ROOT, "temp", "probe_selftest")\n'
                   "def selftest():\n    io.open(TMPD, 'w').write('x')\n    return 0\n")
    _f3, viol3, _u3 = scan(d3)
    rc3, reds3, diags3, _rat3 = verdict(viol3)
    cell("F6-scratch-temp-alone-is-not-red", (rc3, reds3, diags3) == (0, 0, 1)
         and {v[1] for v in viol3} == {"T"}, repr((rc3, reds3, diags3, viol3)))

    # ══════════════════════════════════════════════════════════════════
    # ★★ R218 / Lane EC：**棘轮**的两支变异对照
    #    改造前的 `verdict` 是「有 reds 就 rc=1」⇒ **无条件红**。
    #    改造后按 BASELINE 分档比。下面两格锁住「棘轮真的在看」。
    # ══════════════════════════════════════════════════════════════════
    _v = [("a.py", "R", "selftest", "x"), ("b.py", "R", "selftest", "y")]

    # 变异 1：现读**超过**基线 ⇒ 必红（证明棘轮在看，不是恒绿）
    _rc4, _r4, _d4, _rat4 = verdict(_v, {"W": 0, "R": 1, "G": 0})
    cell("T1-ratchet-exceeded-goes-red", _rc4 == 1 and _rat4["over"].get("R") == (2, 1),
         repr((_rc4, _rat4.get("over"))))

    # 变异 2：现读**等于**基线 ⇒ 绿（证明它是「不许更差」而非「必须更少」）
    _rc5, _r5, _d5, _rat5 = verdict(_v, {"W": 0, "R": 2, "G": 0})
    cell("T2-ratchet-at-baseline-is-green", _rc5 == 0 and not _rat5["over"],
         repr((_rc5, _rat5.get("over"))))

    # 反证 3：现读**低于**基线 ⇒ 仍绿，但必须报「还了债、请下调基线」
    _rc6, _r6, _d6, _rat6 = verdict(_v, {"W": 0, "R": 5, "G": 0})
    cell("T3-ratchet-under-baseline-green-but-notes-debt",
         _rc6 == 0 and _rat6["under"].get("R") == (2, 5),
         repr((_rc6, _rat6.get("under"))))

    return print_selftest(fails, executed)


def verdict(viol, baseline=None):
    """(rc, 红档条数, 记账档条数, 棘轮读数)

    **R218 / Lane EC 改造**：原版 `1 if reds else 0` ⇒ **无条件红**（有 1 处就红）。
    现在按 `BASELINE` 分档比：
      · 某档 **超过** 基线 ⇒ rc=1（新增没有该性质的自检要自己负责）
      · 某档 **低于** 基线 ⇒ rc=0，但**报 NOTE 要求更新基线**（还了债）
      · 全部 == 基线 ⇒ rc=0（这就是「合理终态」）
    S/T 只记账不判红——口径见 CLASS_LABEL 与 §漏红面。
    """
    if baseline is None:
        baseline = BASELINE
    reds = [v for v in viol if v[1] in RED_CLASSES]
    diags = [v for v in viol if v[1] in DIAG_CLASSES]
    counts = {}
    for cls in RED_CLASSES:
        counts[cls] = sum(1 for v in reds if v[1] == cls)
    over = {c: (counts[c], baseline.get(c, 0)) for c in RED_CLASSES
            if counts[c] > baseline.get(c, 0)}
    under = {c: (counts[c], baseline.get(c, 0)) for c in RED_CLASSES
             if counts[c] < baseline.get(c, 0)}
    return (1 if over else 0), len(reds), len(diags), {
        "counts": counts, "over": over, "under": under, "baseline": baseline,
    }


def print_selftest(fails, executed):
    if fails:
        print("SELFTEST FAIL: %d/%d 格红" % (len(fails), len(executed)))
        for n, det in fails:
            print("  - %s%s" % (n, ("：%s" % det)[:400] if det else ""))
        return 1
    fams = {}
    for n in executed:
        # 族名 = 格子名首段里的字母（`R7-main-face-…` → `R`）：留序号在族名里，反解就退化成
        # 「一格一族」，那份清单就不再是覆盖面视图（实测首版打的是 R1×1 / R2×1 … 十五族）。
        head = n.split("-")[0].rstrip("0123456789")
        fams[head] = fams.get(head, 0) + 1
    desc = " / ".join("%s×%d" % (k, v) for k, v in sorted(fams.items()))
    print("SELFTEST OK: %d 格（反解：%s，族名取自已执行格子名首段的字母，不手写计数）" % (len(executed), desc))
    return 0


def main():
    argv = sys.argv[1:]
    if "--selftest" in argv:
        return selftest()
    root = ROOT
    if "--root" in argv:
        i = argv.index("--root")
        if i + 1 >= len(argv):
            return fatal("--root 后面没给路径")
        root = argv[i + 1]
    files, viol, unread = scan(root)
    if not files:
        return fatal("扫描面为空（%s 下 scripts/*.py 一份都没枚举到）⇒ 缺样本＝没测" % root)
    if unread:
        print("DIAG 解析不了（不计失败，也不构成『这格过了』的证据）：%s" % ", ".join(unread))
    rc, reds, diags, rat = verdict(viol)
    c, b = rat["counts"], rat["baseline"]
    print("[棘轮] W=%d/%d  R=%d/%d  G=%d/%d   （现读/基线；基线只许降）"
          % (c["W"], b.get("W", 0), c["R"], b.get("R", 0), c["G"], b.get("G", 0)))
    if rat["over"]:
        print("FAIL **棘轮越线**：这些档超过基线 = 新增了没有该性质的自检：")
        for k, (got, want) in sorted(rat["over"].items()):
            print("  ✗ %s 档 %d > 基线 %d" % (k, got, want))
        print("  （新增 selftest 的一方请自己把那段移出 `--selftest` 归主面，或改用 temp 合成夹具；"
              "不要为了变绿抬高基线。）")
    if rat["under"]:
        print("NOTE **还了债**：这些档低于基线 —— 请把 `BASELINE` 下调到现读，别让账虚高：")
        for k, (got, want) in sorted(rat["under"].items()):
            print("  ↓ %s 档 %d < 基线 %d ⇒ BASELINE[%r] 应改为 %d" % (k, got, want, k, got))
    if rc:
        print()
        print("自检体读/写仓库现状面 %d 处（W=写探针进真树 / R=读现状面 / G=打真仓）："
              "（`--selftest` 只许合成夹具；现状对表归主面）" % reds)
        for f, cls, fn, note in viol:
            if cls in RED_CLASSES:
                print("  - [%s] scripts/%s :: %s() %s" % (cls, f, fn, note))
    if diags:
        print("DIAG 记账不判红 %d 处（S=自 spawn 跑真尺子 / T=读写落在约定的 gitignored temp/）：" % diags)
        for f, cls, fn, note in viol:
            if cls in DIAG_CLASSES:
                print("  - [%s] scripts/%s :: %s() %s" % (cls, f, fn, note))
    if rc:
        print("处置：把那一段移出 `--selftest` 归主面，或改用 temp 合成夹具（写探针的改成写 temp 树）。")
        return 1
    print("PASS 自检 hermetic：%d 份带自检的脚本、W/R/G 三档**都在棘轮基线内**"
          "（W=%d R=%d G=%d，记账档 %d 处已点名）——**这不是「零违例」，是「没比基线更差」**"
          % (len(files), c["W"], c["R"], c["G"], diags))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001 — 尺子自己坏了走 4 号档，绝不冒用 1
        print("FATAL 尺子自己坏了：%r" % e)
        sys.exit(4)
