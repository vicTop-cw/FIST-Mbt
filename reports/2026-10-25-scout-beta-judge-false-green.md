# 判据自证面假绿抽查（侦察兵 · 司令-β）· 2026-10-25

> **角色**：侦察兵 —— **只找问题，不修**。本报告不含任何判据代码改动。
> **抽查面**：`reports/verify-guards-matrix.csv` 里 `真能红(变异抽查)=未抽查` 的 **35 把**，
> 按「正则/模式串密度」排序取**最危险的 5 把** + 同族追加 1 把（`check_doc_surface`）。

## 结果摘要

**6 把抽查，5 把真锁（PASS），1 把假绿（FAIL）** —— 假绿率 **1/6 ≈ 17%**。

| # | 判据 | 锁在盯什么 | 变异点 | 变异后 `--selftest` | 判定 |
|---|---|---|---|---|---|
| 1 | `check_model_auth_no_key.py` | `PREFIX_PATTERNS` 前缀形状 + `_prefix_hits`/`_key_value_hits` | `PREFIX_PATTERNS` 整表停用 | **rc=1**（S1 抓 `sk-` 那格红） | ✅ **真锁** |
| 2 | `check_desc_enum_sync.py` | `check_entry()` 的 `listed vs closure_set` 比对 | ①短路 `check_entry` ②`if v not in closure_set` → `if False` ③`parse_closure` 只回首值 | **rc=1 / 1 / 1**（三格全红） | ✅ **真锁** |
| 3 | `check_deprecated_site_list.py` | `site_list()` 的 fam×msg 归并 + 列切片 `line[c1-1:c2]` | ①去掉 `judge_marker` 精确匹配 ②列切片→整行 ③跨行判定短路 | **rc=1 / 1 / 1** | ✅ **真锁** |
| 4 | `check_plugin_sync.py` | ①`is_generated` 路径过滤 ②**J1 `gen_plugins --check` 漂移** | ①`is_generated` → 恒 `True` ②**J1 漂移分支 → `if False`** | ①rc=1 **红** ②**rc=0 仍然 SELFTEST OK** | ⚠️ **部分假绿（见下）** |
| 5 | `check_py_stdout_encoding.py` | `needs_gate` / `has_gate` / `evaluate` | ①`needs_gate`→False ②`has_gate`→True ③`evaluate` 里短路 | **rc=2 / 2 / 2** | ✅ **真锁** |
| 6 | `check_doc_surface.py`（J12/J14/J17） | `RE_REF_HEADS`、`j14` 的 `got != n`、`RE_J17_COUNT` | ①J17 判定短路 ②`RE_REF_HEADS` 改永不匹配 ③J14 `!=`→`==` | **rc=2 / 2 / 2** | ✅ **真锁** |

---

## 唯一假绿：`check_plugin_sync.py` 的 **J1 漂移判定无自检**

### 事实（代码级，可复现）

`scripts/check_plugin_sync.py:247-267` 的 `selftest()` **只断言 4 件事**，全部围绕 `is_generated` 与
生成文件枚举，**从不调用 `main()`，也从不触碰 `gen_plugins.py`**：

```
selftest 调 main() ?       False
selftest 调 gen_plugins ?  False
selftest 断言的行：
    BUG-70 仍在：克隆到 …/source/… 下时生成文件被判成局外
    成对反例失守：真源 plugins/source/ 被当成生成投影
    真实仓库上只枚举到 N 个生成文件（<40 ⇒ 枚举器空转）
    本仓真源 plugins/source/SKILL.md 被算进了生成集合
```

而 `main()` 里真正承担 **cl7 核心职责**的是 J1（第 160-173 行）：

```python
r = subprocess.run([sys.executable, str(ROOT / "scripts" / "gen_plugins.py"), "--check"], ...)
if r.returncode != 0:
    head = (r.stdout or r.stderr or "").strip().splitlines()
    problems.append("J1 插件态漂移：gen_plugins.py --check 退出码 ...")
```

### 变异证据

把上面那个 `if r.returncode != 0:` 改成 `if False:`（**改的是代码，不是注释**）：

```
baseline      --selftest rc = 0    "SELFTEST OK：合成克隆路径两判都对，真实生成集合 64 个文件"
M1-destructive --selftest rc = 0   "SELFTEST OK：合成克隆路径两判都对，真实生成集合 64 个文件"   ← 一字不差
```

**「插件漂移」这道 cl7 主判据被彻底停用，自检仍报 OK。**

同型第二发：把 J1 的子进程命令换成 `[sys.executable, "-c", "pass"]`（永不漂移）⇒ 同样 **rc=0 / STILL-GREEN**。

### 但这把尺**不是全假绿**（必须如实区分）

`is_generated` 那一格**是真锁**：把它改成恒 `True` ⇒ `--selftest` **rc=1**，并精确点名
`成对反例失守：真源 plugins/source/ 被当成生成投影` 与 `本仓真源 … 被算进了生成集合`。

⇒ **准确判定：`check_plugin_sync.py` 的自检覆盖了「路径分类器」，没覆盖「漂移判定」。**
按判例-29（机制格 ≠ 实现路径格）：自检测的是一个**辅助纯函数**，不是这把尺的**主判据**。

### 风险面（为什么这条值得修）

`check_plugin_sync` 是 **cl7（一源四态第四态）的唯一守卫**，管「四宿主插件目录是否等于生成器投影」。
J1 是它**唯一**的逐字节对表入口。J1 失效 = 四宿主插件漂移**全仓无人报警**，
而 `--selftest` 仍绿灯 ⇒ 这正是判例-29/30 描述的最毒形态：
**「所有门禁都绿」变成真的绿，但你不知道它到底在看什么。**

---

## 两次自我纠错（如实记录，不改写）

按纪律「自曝失败」，本轮侦察过程本身有两次误判，均已当场纠正：

1. **`check_model_auth_no_key` 首轮 M1 我判成「假绿」，是错的。**
   我的变异写成 `PREFIX_PATTERNS = []; _ORIG = [` 时语法上把原列表续接回去了，
   `len(PREFIX_PATTERNS)` 读回非空 ⇒ 变异根本没生效。改用真正的整表停用后 **rc=1 CAUGHT**，
   判定**反转**为真锁。**教训：变异后必须验证「变异真的改变了被测行为」，不能只看 rc。**
   （验证法：直接 `import` 判据模块，调 `scan_text` 对比变异前后命中数 `3 → 0`。）

2. **`check_plugin_sync` 首轮我把 M3（`is_generated` 断言短路）也读成假绿。**
   实际是我的变异写成 `not X and False` —— 对 `X=True` 的输入它**恰好仍是 True**，语义未被破坏。
   改为直接破坏 `is_generated` 本体（`return True`）后 **rc=1 红**。
   **教训同 1：`a and False` / `a or True` 这类变异会被原值掩盖，等于没变异。**

**这两次都是「变异未命中锁」而非「锁是假的」** —— 按任务书口径应记「变异未命中锁」，
但我先下了「假绿」结论再自我推翻，故如实记录过程。

---

## 给修复者的一页纸（我不修，只给处方）

**病灶**：`scripts/check_plugin_sync.py` 的 `selftest()`（L247-267）没有触碰 `main()` 的 J1 路径。

**处方（三选一，按代价递增）**：

1. **最小**：加一格——把 `gen_plugins.py --check` 的子进程调用抽成可注入的函数
   （如 `_run_gen_check(cmd=None)`），selftest 里传一个必然非零的假命令（`[sys.executable, "-c", "raise SystemExit(1)"]`），
   断言 `main()` 的 `problems` 里出现 `J1 插件态漂移`。
   ⇒ 这条直接钉「J1 分支还在不在」，代价最小。
2. **中等**：在 `temp/` 造一棵假的 plugins 树，让 `gen_plugins --check` 真漂移，断言 J1 红。
3. **结构性**：照判例-16 补「J 面覆盖面对表」——断言 `main()` 里每个 `J\d` 分支
   都至少被一格 selftest 命中（这把尺自己也要过判例-16）。

**顺带（不属本单，仅登记）**：`check_mbti_eol.py` 已在矩阵里由 `未抽查` 变健康（判例-16 已修），
但该文件的「只在 3 份 `.mbti` 上验」这一形状**建议顺手复验**是否真的扩到跟踪面 24 份。

---

## 未覆盖说明（诚实边界）

- 抽查 **6 / 35** 把，**不是全集**。剩余 29 把（含 `check_tools_sync` / `check_slave_task_list` /
  `check_host_installable` / `check_exit_code_contract` 等 regex 密集者）**仍未证**。
- 本报告只按「正则密度」排序取样，**不代表按风险排序的完整结论**。
- 变异只覆盖**可静态改坏**的分支；依赖真实 subprocess/git 现场的分支（如 J2 宿主入口检查）
  本轮未造违规树验证。

## 复现方法

每把尺的变异都是「备份 → 改一处代码 → 跑 `--selftest` → 逐字节还原」，
还原后 `git diff --numstat scripts/<尺>.py` 全部为空（6 把全验过）。
临时夹具 `temp/_scout_*.py` 已删除，未入库。
