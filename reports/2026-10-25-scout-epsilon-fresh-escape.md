# 侦察报告：`--fresh` 逃生口覆盖验证（判例-33 落地核查）

- **侦察兵**：司令-ε
- **日期**：2026-10-25
- **任务**：验证「检查逃生口是否合格」的规则（判例-33）本身是否被遵守
- **纪律**：只报不修、不改判据源码、不 commit

---

## 一、结论（先给判断）

**判例-33 的落地是合格的 —— 零 🔴 高危。**

`--fresh` 逃生口只有 **1 个真入口**（`FIST_BADGE_FRESH=0`），它作用于 **2 个电池格**；
关掉时输出**完整的 SKIP 说明**（逐字包含判例-33 要求的「只证明了文档==快照，未证明文档==现实」）。

**但侦察中发现一个判例-33 没覆盖的结构性事实（非高危，⚠️ 见 §5）**：
CI **从不跑完整电池**，它跑的是这两把尺的**独立步骤**（不带 `--fresh`，因为 CI 自己先真跑
`moon test` 生成日志）。⇒ `--fresh` 这个逃生口**在 CI 侧根本不存在**，它只活在本地电池里。

**含义是双面的**：
- **好消息**：CI 无 `--fresh` 可关（实测 `.github/` 下零引用 `FIST_BADGE_FRESH`），
  也不存在被误设的风险；且本地那 2 格即使被关，**源码面锚点仍是最后防线**（§3.2）。
- **需知悉**：`--fresh` 这两格**只在本地电池里执行**。本地关掉后，唯一还站着的防线是
  「快照源码面 == 现在」的锚点检查；CI 侧则由「当次真跑日志」保证，二者互补而非重复。

---

## 二、全量枚举：谁真的消费 `--fresh`

普查命令：
```bash
grep -rn '"--fresh"|--fresh' scripts/ --include='*.py'
```

10 个文件提到 `fresh`，但**真定义/消费 `--fresh` 参数的只有 3 处**（其余是 `refresh_dist`
的 refresh、`run_light_wt` 的 `fresh` 状态机、e2e 的「重装」语义——同名不同义）：

| # | 位置 | 角色 |
|---|---|---|
| 1 | `scripts/check_badge.py:358` | **消费者**：`--fresh` ⇒ `run_fresh()` 真跑全仓后重写快照+锚点 |
| 2 | `scripts/check_test_sync.py:765` | **消费者**：同上（两把共用 `_badge_anchor.py`） |
| 3 | `scripts/run_guards.py:441` | **开关**：`fresh_enabled()` = `FIST_BADGE_FRESH != "0"`（默认开） |
| 4 | `scripts/_badge_anchor.py:150,157` | **被引用**：锚点失败时提示「用 --fresh 重跑」 |

**电池里带 `--fresh` 的格（实读 `CASES`）**：

```
name: check_badge.py temp/pt27.log README.md --fresh   expect=0  kind=gate
name: check_test_sync.py temp/pt27.log --fresh         expect=0  kind=gate
```

---

## 三、覆盖矩阵

| 判据 | `--fresh` 跳过什么 | 返回什么 | 说明完整性 | 风险等级 |
|---|---|---|---|---|
| `check_badge.py` | 跳过「判前真跑全仓 `moon test --target js` 并重写快照+源码面锚点」；改读**既有** `temp/pt27.log` | **照常判定**（用旧快照判）— 但有**锚点守卫**兜底：快照源码面 ≠ 现在 ⇒ `rc=2` REJECT | 电池层 SKIP 说明**完整**（见下）；判据层锚点失败文案**完整** | 🟢 **安全** |
| `check_test_sync.py` | 同上 | 同上 | 同上 | 🟢 **安全** |
| （`run_guards` 跳过分支） | 整格跳过，`continue` | 不执行判据，记入 `skips` | ✅ 逐字含判例-33 要求 | 🟢 **安全** |

### 3.1 电池层 SKIP 的实际输出（实测，非读代码）

```bash
FIST_BADGE_FRESH=0 python -c "..."   # 复刻 run_battery 913-921 段，逐行相同
```
```
SKIP  check_badge.py temp/pt27.log README.md --fresh
      SKIP 新鲜度检验（FIST_BADGE_FRESH=0）：本格只证明了「文档 == 快照」，
      未证明「文档 == 现实」——快照可能比代码旧（判例-25）
SKIP  check_test_sync.py temp/pt27.log --fresh
      （同上）
```

**判定**：说明中**同时包含**「只证明了什么」与「未证明什么」——这正是判例-33 的合格形态。

### 3.2 判据层自身（不经 `run_guards`，直接调用）

`check_badge.py`：
```python
if fresh:
    ok, tail = run_fresh(log_path)
    print("FRESH 真跑全仓：%s" % ("成功" if ok else "失败"))
    if not ok:
        print("REJECT --fresh 跑不出真值（rc≠0）⇒ rc=2，不拿旧快照冒充现实")
        return 2
```
⇒ **`--fresh` 失败 ⇒ `rc=2`，绝不冒充 PASS。** 与判例-33 同口径。

`_badge_anchor.py` 的锚点守卫（`--fresh` 缺席时的**唯一防线**）：
```
REJECT SNAPSHOT-STALE: 快照源码面 <stored> ≠ 现在 <now>
 ⇒ 本判据只能证明「文档 == 快照」，不能证明「文档 == 现实」⇒ rc=2，拒绝出绿。
```

### 3.3 实测：当前快照新鲜时的行为

```
$ python scripts/check_badge.py temp/pt27.log README.md
PASS 徽章一致：README tests-1457%2F1457 == 快照 @ 2026-10-25 06:02:56（源码面 09e2466000b3）
PASS 快照同源：源码面 09e2466000b3… == 现在（文档改动不影响该锚点）
rc=0

$ python scripts/check_test_sync.py temp/pt27.log
PASS 测试总数单一真源一致：实测 1457；扫描现状面 141 份文档，17 条声明全部等于实测
rc=0
```
⇒ **锚点机制在工作**，不是空转。

---

## 四、`fresh_enabled()` 语义核对

```python
def fresh_enabled():
    return os.environ.get("FIST_BADGE_FRESH", "").strip() != "0"
```

实测三种取值：

| 环境变量 | `fresh_enabled()` | 语义 |
|---|---|---|
| `FIST_BADGE_FRESH=0` | **False**（关） | 只有显式 0 才关 |
| 未设 | **True**（开） | **默认开** ✅ |
| `FIST_BADGE_FRESH=1` | **True**（开） | |
| `FIST_BADGE_FRESH=false` | **True**（开） | 只认字面 `"0"`，不认 `false` |

**判定**：方向正确（**默认开**，必须显式 `=0` 才关）。`false` 不生效属小瑕疵但**方向安全**
（fail-safe：写错时偏向真跑）。

---

## 五、⚠️ 侦察发现的结构性缺口（非 🔴 高危，但判例-33 未覆盖）

### 5.1 CI 从不跑完整电池 ⇒ `--fresh` 逃生口在 CI 侧不存在

```bash
grep -rn 'run_guards\.py' .github/workflows/*.yml
# ci.yml:208  python3 scripts/run_guards.py --selftest
# ci.yml:209  python3 scripts/run_guards.py --list
# ⇒ 零裸跑
```

**双面含义**：

- **好的一面**：CI 无 `--fresh` 可关，也不存在 `FIST_BADGE_FRESH=0` 被误设的风险
  （实测 `.github/` 下**零引用**该变量）。
- **坏的一面**：`--fresh` 这 2 格**只在本地电池里跑**。若有人在本地用
  `FIST_BADGE_FRESH=0` 跑完电池就看到「全绿」，那份绿**没有 CI 兜底**。

### 5.2 但 CI 有等价替代面（**这就是为什么不是高危**）

CI 里有这两把尺的**独立步骤**，且它们**天然新鲜**——CI 自己先真跑测试再喂给判据：

```yaml
# ci.yml:172-181
- name: Test (js)
  run: set -o pipefail; moon test --target js 2>&1 | tee /tmp/moon_test.log
- name: Badge consistency guard
  run: python3 scripts/check_badge.py /tmp/moon_test.log README.md      # ← 不带 --fresh
- name: Test-count single-source guard
  run: python3 scripts/check_test_sync.py /tmp/moon_test.log            # ← 不带 --fresh
```

⇒ **CI 侧「文档 == 现实」由「刚刚真跑的日志」保证**，根本不需要 `--fresh`。
**逃生口只影响本地，而本地那一面的最后防线是源码面锚点（§3.2）** —— 两条防线互补。

### 5.3 缺一条守卫（建议，非本次修）

**没有任何判据检查「CI 不得设置 `FIST_BADGE_FRESH=0`」**。

实测：
```bash
grep -rln 'FIST_BADGE_FRESH' scripts/check_*.py   # → 零命中
```

**风险形状**：若将来有人在 CI 加 `env: FIST_BADGE_FRESH: "0"`（比如为省 7~9 分钟），
那两格会 SKIP。SKIP 说明本身是完整的，但这仍是判例-33 想防的「又一种假绿」的**上游形态**：
**说明写对了，但没有任何机制阻止「在权威面上关掉它」。**

**建议**（由统帅派工，非本次执行）：
造一格 `check_fresh_escape_not_disabled_in_ci.py`：扫 `.github/workflows/*.yml`，
出现 `FIST_BADGE_FRESH` 即红（带理由豁免表，锚点须成立）。

### 5.4 ✅ 一处我原本以为缺、实测**已经做对**的（自查纠错）

写本报告时我一度打算建议「汇总行应强制显形 skips 数」。**实测推翻了这个判断**——
`run_battery` 的汇总**已经**同时做了两件事：

```python
# run_guards.py:953
print("格数 %d（手写 %d + 自动 %d）/ 失败 %d / SKIP %d / 缺执行面 %d" % ...)
# run_guards.py:964
if skips:
    print("  SKIP 明细（不计失败，但也不构成'这格过了'的证据）：")
    for name, why in skips:
        print("  - %s：%s" % (name, why))
```

⇒ **SKIP 数在汇总行显形 + 明细逐条列出 + 明确写「不构成'这格过了'的证据」**。
判例-33 的「下游读法」这一环**已经闭环**，无需再改。

**这条留档的理由**：我是在读代码前就写下了「汇总行没显示 skips」的判断，
读了 953 行才发现是错的。**侦察兵的结论同样必须先读后写。**

---

## 六、其他提到 `fresh` 但**不属于逃生口**的（排除性核查）

| 文件 | 为何不是逃生口 |
|---|---|
| `scripts/refresh_dist.py` | `refresh` 是「刷新 dist 快照」的业务动词，无 `--fresh` 参数 |
| `scripts/run_light_wt.py` | `fresh` 是沙箱状态机的一个枚举态（`fresh` / `merged`），与新鲜度无关 |
| `scripts/blackbox/e2e_mirror_install.py` | 「全新安装」语义 |
| `scripts/blackbox/e2e_upgrade_mirror.py` | 同上 |
| `scripts/fist.py` | 提到 fresh 但无参数消费 |

---

## 七、判例-33 落地结论

> **判例-33 原文**：`SKIP 必须带完整说明：「本格只证明了『文档 == 快照』，未证明『文档 == 现实』」`

| 检查项 | 结果 |
|---|---|
| 逃生口数量 | **1 个**（`FIST_BADGE_FRESH=0`），作用于 2 格 |
| SKIP 说明是否含「只证明了什么」 | ✅ 有 |
| SKIP 说明是否含「未证明什么」 | ✅ 有 |
| SKIP 数是否在汇总行显形 | ✅ **有**（`/ SKIP %d /`） |
| SKIP 明细是否逐条列出 | ✅ **有**（含「不构成『这格过了』的证据」） |
| `--fresh` 失败是否冒充 PASS | ❌ **不会**（`rc=2` REJECT） |
| 默认开 / 显式关 | ✅ **默认开**，只认字面 `"0"` |
| 快照陈旧是否有防线 | ✅ **有**（源码面锚点 `rc=2`） |
| CI 是否有兜底 | ✅ CI 独立步骤用当次真跑日志（**不需要**逃生口） |
| 是否有守卫防 CI 误设 `=0` | ❌ **无**（§5.3 唯一建议） |

**总判定：判例-33 已**完整**落地 —— 零 🔴 高危、零 🟡 中危。**
上游（说明文案）、中游（SKIP 显形与明细）、下游（读者不被误导）**三环全部闭环**。
唯一缺口是**未来风险**：没有守卫阻止「有人在 CI 上把这个逃生口关掉」（§5.3）。

---

## 八、可复现命令

```bash
# ① 全量枚举
grep -rn -- '--fresh' scripts/ --include='*.py'

# ② 电池里哪两格带 --fresh
python -c "import importlib.util;s=importlib.util.spec_from_file_location('rg','scripts/run_guards.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m);[print(c['name'],c['argv']) for c in m.CASES if '--fresh' in c['argv']]"

# ③ 实测 SKIP 输出（复刻 run_battery 913-921）
FIST_BADGE_FRESH=0 python -c "..."

# ④ 实测锚点守卫（当前快照新鲜 ⇒ PASS）
python scripts/check_badge.py temp/pt27.log README.md

# ⑤ CI 面核查
grep -rn 'run_guards\.py\|FIST_BADGE_FRESH' .github/workflows/
```

## 来源

| 项 | 来源 |
|---|---|
| 任务 | 统帅（侦察兵模式派工，2026-10-25） |
| 判例-33 | 本会话统帅所立（SKIP 必须带完整说明） |
| 判例-25 | 源码面锚点（`_badge_anchor.py` 的由来） |
| 现场读数 | `temp/pt27.log` @ 2026-10-25 06:02:56，源码面 `09e2466000b3` |
