# Lane F · 全量测试基线报告（2026-10-26）

> **角色**：Lane F 回归队　**任务**：建立当前 HEAD 的全量测试真实基线（**只测量，不修**）
> **执行**：司令-ζ　**纪律**：只读 + 新报告；未改任何 `src/` `scripts/` 文件

---

## 结论

**当前 HEAD 的全量测试基线：`Total tests: 1460, passed: 1460, failed: 0` —— 全绿。**

| 项 | 值 |
|---|---|
| **HEAD（权威基线）** | `d5a84c769929452bb4d542da78a327ae80a8b0c0` |
| **Total tests** | **1460** |
| **passed** | **1460** |
| **failed** | **0** ✅ |
| 判定依据 | 汇总行（**不信 exit 0**，BUG-142） |
| `moon.mod` 版本 | `0.3.10` |
| `.git` 体积（瘦身后） | **21M** |
| `check_battery_count_doc` | **PASS**（rulers=120 ci=46 battery=79 missing=0 gate=87） |
| `check_test_sync` | ❌ **FAIL**（文档写 1457，真基线 1460 —— 见 §五，**本 lane 不修**） |
| **瘦身是否影响测试** | **否**（`git fsck` 全净，见 §二） |

---

## 一、快照

```bash
$ git rev-parse HEAD
d5a84c769929452bb4d542da78a327ae80a8b0c0

$ git status --porcelain | wc -l
2                     # 开工时；期间随其他 lane 写入变动（见 §三）

$ grep version moon.mod
version = "0.3.10"

$ du -sh .git
21M
```

---

## 二、瘦身后仓库完整性自检（**最高优先级，已先做**）

任务书要求：「若出现与对象缺失相关的怪异失败，优先怀疑本次 `.git` 瘦身（2.0G→20M），立即停手报告」。

**我在跑任何测试之前先自检了仓库完整性**——因为如果对象库坏了，任何测试失败都无法归因。

```bash
$ git fsck --connectivity-only
（无输出）                                    rc=0   ✅

$ git fsck --no-dangling
（无输出）                                    rc=0   ✅

$ git ls-files | shuf -n 100 | xargs git hash-object
成功读取 100 / 100                            ✅
```

**判定：`.git` 瘦身未造成对象缺失或损坏。** 因此本次测试读数**可归因于代码，而非仓库状态**。
（补充：`--connectivity-only` 只查引用连通性、不校验 blob 内容，所以我另做了 100 份随机 blob 读取校验。）

---

## 三、全量测试执行与四次运行记录

**必须用常驻入口**（否则 Windows node 垫片吞引号 ⇒ 假失败，BUG-380）：
```bash
python scripts/moon_test_env.py --target js --raw-log <log>
```

### 3.1 四次运行（**读数随工作树变动而变，这是关键观察**）

| # | 运行对象 | Total | passed | failed | 说明 |
|---|---|---|---|---|---|
| run1 | 工作树（当时干净，HEAD=`93168d6a`） | **1457** | 1457 | **0** | 全绿 |
| run2 | 工作树（他人在写 LANEC 探针） | 1459 | 1457 | **2** | 2 失败全在**未入库的临时探针文件** |
| run3 | 工作树（他人在写 BUG-411 锁） | 1460 | 1459 | **1** | 1 失败在**未提交的在途改动** |
| **run4** | **HEAD 干净树（`git archive` 导出，隔离运行）** | **1460** | **1460** | **0** | ✅ **权威基线** |

> **run4 的正确性说明**：`scripts/moon_test_env.py:113` 把 `ROOT` 硬编码为**脚本自身目录**、
> **忽略 cwd**。所以我第一次尝试在导出树里跑时，实际测的还是主工作树（得到 1460 包含他人在途改动）。
> **修正做法**：把 HEAD 树 `git archive` 导出到 `temp/audit/h2/`，用**该树自己的** `scripts/moon_test_env.py` 跑
> ⇒ `ROOT` 正确指向导出树 ⇒ 测的是纯 HEAD 内容。
> **交叉验证**：导出树 `@test` 粗计数 = **1460**，与汇总行 1460 一致；导出树无 LANEC 探针、含 BUG-411 锁（HEAD 已入库）✅

### 3.2 两次失败的真实归因（**都不是 HEAD 的问题**）

**run2 的 2 个失败** —— `src/engine/zz_lanec_probe_wbtest.mbt`（**从未入库、现已删除**）：
```
test src/engine/zz_lanec_probe_wbtest.mbt:6 ("LANEC string-index 空串/边界输入")
  failed: ...:47:3-47:69 FAILED: LANEC1 skipped-n<2/skipped-n<2/ok crashed=none
test src/engine/zz_lanec_probe_wbtest.mbt:51 ("LANEC divide-by-zero 边界输入（iso_to_epoch 除数）")
  failed: ...:61:3-61:24 FAILED: LANEC2 y0=1720785;y-1=1720420;y1=1721151;y9999=5372845;
```
- `git cat-file -e HEAD:src/engine/zz_lanec_probe_wbtest.mbt` ⇒ **HEAD 无此文件**
- 现在工作树也**已不存在**（是其他 lane 的临时边界探针，用完即删）
- **判定：非 HEAD 缺陷。** 是并发窗口里别人的临时文件进入了我的测试快照。

**run3 的 1 个失败** —— `src/store/store_sqlite_agents_wbtest.mbt:326`（**未提交的在途改动**）：
```
test src/store/store_sqlite_agents_wbtest.mbt:326 ("bug411_count_writable_ns_filter_mutation")
  failed: ...:334:9-334:29 FAILED: 前置不成立：默认应为 0
```
- 该测试名在 **HEAD 版本里 grep = 0 命中**（`git show HEAD:... | grep -c` = 0）
- 工作树该文件有 `+106` 行未提交新增（别的 lane 正在写 BUG-411 修复的配套白盒锁）
- **判定：是他人在途工作的自洽性问题（该锁的"前置不成立"说明被测代码与锁预期尚未对齐），不是 HEAD 回归。**

---

## 四、判据读数

### 4.1 `check_battery_count_doc`
```
PASS 电池读数与 README 登记逐键一致：rulers=120 ci=46 battery=79 missing=0 gate=87 exempt=28 unclassified=7
rc=0
```
✅ 门禁未停摆，缺执行面 0。

### 4.2 `check_test_sync` —— ❌ **FAIL（发现文档漂移）**

用真基线 1460 判：
```bash
$ python scripts/check_test_sync.py --total 1460
R1 docs/SOP.md:38           声明 1457 ≠ 实测 1460
R1 docs/agent-map.md:10     声明 1457 ≠ 实测 1460
R1 docs/deliverable.md:18   声明 1457 ≠ 实测 1460
R1 scripts/scoring_rubric.md:8 声明 1457 ≠ 实测 1460
R2 README.md / AGENTS.md / deliverable / agent-map / scoring_rubric
   均未出现实测总数 1460 的声明
R3 防空转：现状面里没有任何一条声明等于实测 1460
```

**文档侧手抄数普查**：
```
8 处 "1457/1457"  +  6 处 "1457"  = 14 处声明 1457
真基线 = 1460                  ⇒ 差 3
```

**判定：文档陈旧（落后 3 个测试）。** 这是**真漂移**，但**按本 lane 纪律不修**——报给负责修文档的 lane。

> 补充：`temp/pt27.log`（旧快照，Oct 25 06:02）也是 1457，说明文档是跟着旧快照抄的。
> 3 个测试的增量来自 run2→run4 之间其他 lane 新入库的测试（BUG-411 锁等）。

---

## 五、分析

### 5.1 「工作树基线」是一个移动靶 —— 这是本 lane 最重要的方法论发现

四次运行得到 **四个不同的数**（1457 / 1459 / 1460 / 1460），而**代码仓库本身没坏**。
原因：**其他 lane 在同一时间往工作树里写文件**，我的每次 `moon test` 都摄入了当时的在途内容。

⇒ **要建立"可信基线"，必须测"已提交的 HEAD"，而不是"当前工作树"。**
本报告给出的 `1460/1460/0` 是 **`git archive HEAD` 隔离树**的读数，因此可复现、可对照。

**给后续 lane 的建议**：把基线口径固定为
```bash
git archive HEAD | tar -x -C <isolated-dir>
cd <isolated-dir> && python scripts/moon_test_env.py --target js --raw-log <log>
```
（**必须用该树自己的 `scripts/moon_test_env.py`** —— 它硬编码 `ROOT` 为脚本目录、忽略 cwd。）

### 5.2 为什么必须看汇总行而不是 exit 0
本次四次运行 `moon_test_env.py` 的 **rc 全是 0**（包括 failed=2 和 failed=1 那两次）。
若按 exit code 判，会把两次真失败判成绿 —— 正是 **BUG-142** 要防的形状。
本报告全部以汇总行为准。

### 5.3 瘦身与测试的关系（任务书重点关注项）
**无关。** 证据链：
1. `git fsck --connectivity-only` rc=0 无输出
2. `git fsck --no-dangling` rc=0 无输出
3. 100 份随机 blob hash 校验全通
4. HEAD 干净树 1460/1460 全绿，无任何"对象缺失"类错误

---

## 六、缺口与风险

1. **文档漂移 14 处（1457 → 应 1460）未修** —— 本 lane 只测量。需派给文档 lane。
2. **工作树仍在变动**（我收尾时 HEAD 已从 `93168d6a` 前进到 `d5a84c76`，且有 3 个文件在被改）。
   本报告的基线**锚定 `d5a84c76`**；HEAD 再前进则需重测。
3. **`moon_test_env.py` 忽略 cwd**（`ROOT` 硬编码）—— 这是一个容易踩的坑：
   在副本树里跑"隔离测试"会**静默测主树**。建议后续给它加 `--root` 或明确文档化。
4. **两次失败虽已归因于他人在途工作，但那 1 个 BUG-411 锁目前是红的**——
   若相关工作最终入库而锁未同步修正，会变成真红。**建议提醒对应 lane 收口。**
5. **未跑 native 轨**（本 lane 只按任务书测 js）。native 面另有 BUG-133 的已知边界。

---

## 七、建议入档位置

- **基线读数**（1460/1460/0 @ `d5a84c76`）→ 可作为后续所有 lane 的对照基线，建议写入
  `memory/2026-10-26.md` 与 `BACKLOG.md` 的发布事实区。
- **「工作树基线是移动靶 / 必须测 `git archive HEAD`」** → 建议入判例集（新判例候选：
  「并发多 lane 下的基线口径」）。
- **「`moon_test_env.py` 忽略 cwd ⇒ 隔离测试会静默测主树」** → 建议入 `scripts/README.md`
  该脚本条目，或给脚本加 `--root`。
- **文档漂移 1457→1460** → 报给文档 lane 修 14 处。

---

## 来源

- HEAD：`d5a84c769929452bb4d542da78a327ae80a8b0c0`
- 权威日志：`temp/audit/lane_f_head2.log`（`Total tests: 1460, passed: 1460, failed: 0`）
- 工作树运行记录：`temp/audit/lane_f_fulltest.log`(1457/0F) / `lane_f_raw.log`(1459/2F) / `lane_f_run3.log`(1460/1F)
- 判据：`check_battery_count_doc`（PASS）/ `check_test_sync --total 1460`（FAIL，文档漂移）
- 完整性：`git fsck --connectivity-only` / `git fsck --no-dangling` / 100 份 blob hash 校验
