# Lane H · plan-landing P0 执行报告

> **文种**：执行报告
> **日期**：2026-10-26 · **执行**：Lane H（commander-alpha）
> **依据**：`reports/2026-10-26-plan-landing-triage-report.md`（`d5a84c76`，Lane E 的 45 条判定面）
> **所有行号与读数均为本次现读**

---

## 0. 结论

| 项 | 数 |
|---|---|
| **判定面 改前** | **45** |
| **判定面 改后** | **35**（磁盘上有 1 条、都没有 34 条） |
| **净减少** | **−10** |
| 已改 | **10 条命中**（A 类 5 + C 类 5），共 **12 处编辑** |
| 改不动 | **1 条**（A 类第 6 条，见 §2） |

**提交**：
- `02c5747f` — A 类 5 条（`docs/2026-10-20-slave-tasks.md`）
- `6f76189e` — C 类 5 条（5 份文档，7 处编辑）

**⇒ 达成 45 → 35。未达 Lane E 预估的 ~34，差 1 条 —— 差的就是 §2 那条我不肯改的。**

---

## 1. 已改的 10 条（每处 文件:行 前后对比）

### 1.1 A 类 5 条 —— 分支名列去反引号（`02c5747f`）

**判据提取规则（先查实，不猜）**：
```python
scripts/check_plan_landing.py:83
BACKTICK = re.compile(r"`([^`\n]+)`")
```
**⇒ 所有反引号包裹的内容都被当候选路径。分支名用反引号 = 自找误判。**

| # | 文件:行 | 改前 | 改后 |
|---|---|---|---|
| 1 | `docs/2026-10-20-slave-tasks.md:99` | `` `docs/polish-readme-slogan` `` | `分支 docs/polish-readme-slogan` |
| 2 | `docs/2026-10-20-slave-tasks.md:100` | `` `docs/selfdrive-walkthrough` `` | `分支 docs/selfdrive-walkthrough` |
| 3 | `docs/2026-10-20-slave-tasks.md:102` | `` `docs/readme-env-bold` `` | `分支 docs/readme-env-bold` |
| 4 | `docs/2026-10-20-slave-tasks.md:103` | `` `docs/known-boundaries` `` | `分支 docs/known-boundaries` |
| 5 | `docs/2026-10-20-slave-tasks.md:112` | `` `docs/multi-tenant-skill-enhance` `` | `分支 docs/multi-tenant-skill-enhance` |

**未动**：`docs/2026-10-20-slave-tasks.md:101` 的 `fix/native-ci-green` —— 同为分支名，
但**不含 `/`，不满足路径形状，未被判据点名** ⇒ **不扩大战场**（判例-45/46 的另一半）。

### 1.2 C 类 5 条 —— 指向归档后的真实路径（`6f76189e`）

**逐条真实路径核验（先 `git ls-files` 确认）**：
```
$ git ls-files | grep future-plan        → docs/archive/2026-10-16-future-plan.md
$ git ls-files | grep check_ps_encoding  → scripts/check_ps_encoding.py
$ git ls-files scripts/blackbox/ | grep ps_enc → 无（确认是路径写错，不是文件不存在）
```

| # | 文件:行 | 改前 | 改后 |
|---|---|---|---|
| 6 | `docs/plans/2026-10-22-fist-dir-layout-governance-proposal.md:12` | `` `reports/2026-10-16-future-plan.md` `` | `` `docs/archive/2026-10-16-future-plan.md` `` + 补「原置于 reports/ 后归档」 |
| 7 | `docs/proposal-process.md:10` | `` `reports/2026-10-16-future-plan.md` `` | `` `docs/archive/2026-10-16-future-plan.md` `` + 补「当时位于 reports/，后归档」 |
| 8 | `docs/proposals/2026-10-22-cross-machine-task-publish-proposal.md:6` | `` `reports/2026-10-16-future-plan.md` `` §一 | `` `docs/archive/2026-10-16-future-plan.md` `` §一 |
| 9 | `docs/proposals/2026-10-22-cross-machine-task-publish-proposal.md:65` | 同上 | 同上 |
| 10 | `docs/proposals/2026-10-22-folder-watch-trigger-proposal.md:6` | 同上 §二 | 同上 §二 |
| 11 | `docs/proposals/2026-10-22-folder-watch-trigger-proposal.md:66` | 同上 §二 | 同上 §二 |
| 12 | `docs/2026-10-21-fist-governance-tier2-plan.md:77` | `` `scripts/blackbox/check_ps_encoding.py` `` | `` `scripts/check_ps_encoding.py` `` |

**为什么第 6、7 处补了历史短语**：原文的论点是「**这文件不该在 `reports/`**」。
直接把路径换成 `docs/archive/` 会让那句话失去前提（`docs/archive/` 里的文件当然不在 `reports/`）。
补一句「原置于 `reports/` 后归档」，**论点仍成立且路径可点**。这是语义保全，不是画蛇添足。

---

## 2. 改不动的 1 条（含逐条理由）

### 2.1 `docs/2026-10-20-slave-tasks.md:76` — `src/server/wt_tools.mbt`

**判据点名**：
```
[missing] docs/2026-10-20-slave-tasks.md 点名 `src/server/wt_tools.mbt`
```

**原文（第 76 行，204-270 字符处）**：
```
…`wt_status` / `wt_destroy` 在 `src/`、`scripts/`、`.github/` 三面 0 命中；
**`src/server/wt_tools.mbt` 不在跟踪面**；唯一提及处是 plan 正文
`docs/plan-light-worktree-isolation.md`…
```

**为什么不改**：
1. 它在**【现读证据】列**，不在「分支名」列 —— 与 A 类前 5 条**性质不同**
2. **这句话陈述的核心事实就是「该文件不存在」**（WT-02 未开工的证据）
3. 去掉反引号确实能让判据少 1 条 —— **但那是「把证据藏起来让尺子看不见」**

**⇒ 为了凑数字而改掉真证据，得到的「34」是假绿。** 宁可交 35，不交一个靠藏证据得到的 34。

**若判据觉得这类「说的是『不存在』」的命中不该进判定面**，那是**判据改进单**的事
（例如：识别「不在跟踪面 / 不存在 / 未创建」这类否定语境），**不是文档该迁就的**。

---

## 3. ⭐ 怎么判断一条命中是「格式误读」还是「判据在指出真事」

> 这是本轮最有复用价值的方法。**同类清理可以直接照做。**

### 三步判别法

**第 1 步：定位它在不在「路径位」**
命中处的反引号内容，在这个文档的语境里**是不是在说「一个文件的位置」**？
- 是「分支名」「工具名」「命令名」「字段名」⇒ **格式误读**（反引号被误用为「代码格式」而非「路径」）
- 是「这个文件在/不在某处」⇒ **可能是真事**，进第 2 步

**第 2 步：读这句话在陈述什么**
把该行完整读一遍，问：**如果这个文件真的存在，这句话还成立吗？**
- 不成立（如「WT-02 未开工，因为它不存在」）⇒ **判据在指出真事，不许改**
- 仍成立（如「这文件应在 `reports/`」）⇒ 继续第 3 步

**第 3 步：`git ls-files` 查真实位置**
```bash
git ls-files | grep <basename>
```
- **有结果、路径不同** ⇒ **真实路径错误 ⇒ 改**（C 类）
- **无结果** ⇒ **真实缺失 ⇒ 按第 2 步判断**：若这句话就是在说「它不存在」⇒ 不改；否则报出来

### 一句话版

> **「改了会让这句话变成假话吗？」**
> 会 ⇒ 不许改（那是真证据）。
> 不会，且文件在别处 ⇒ 改。
> 不会，但文件真不存在且原句没在说「不存在」⇒ 报出来（可能是真的虚报）。

### 这条方法的来源

A 类 6 条里，5 条是格式误读（分支名被当路径），**1 条是判据在指出真事**（`wt_tools.mbt` 确实不存在）。
**同一份文档、同一个判据、同一个列宽 —— 混着两种性质。**
**⇒ 逐条读，不许按「文件:行号」批量 sed。**（判例-45/46 的实操形态）

---

## 4. 读数（前后对比）

```
改前：
  判定面未在跟踪面 45 条（磁盘上有 ? 条、都没有 ? 条）

A 类 5 条后（02c5747f）：
  判定面未在跟踪面 40 条（磁盘上有 1 条、都没有 39 条）   ⇒ −5

C 类 5 条后（6f76189e）：
  判定面未在跟踪面 35 条（磁盘上有 1 条、都没有 34 条）   ⇒ 再 −5

累计：45 → 35，共 −10
```

**搬家态 3 条 / 豁免态 7 条 / 存档面 18 条 —— 三项均不变**（不在本次 P0 范围，按 Lane E 分类属其他档）。

---

## 5. 缺口与风险

| # | 项 | 说明 |
|---|---|---|
| **R1** | **差 1 条未达 ~34** | 差的就是 §2 那条我不肯改的。**这是有意为之，不是遗漏** |
| **R2** | **`check_plan_landing.py` 的棘轮上限是 25** | 现读 35 > 25，**门禁仍超限 10 条**。本次只是把一个更大的超限缩小，**没有让它转绿** |
| **R3** | **判据本身可能仍有误读面** | `BACKTICK` 正则抓所有反引号内容，**分支名/工具名/命令名都会被当路径**。本次只修了被判据点名的那些，**没被点名的不代表不存在同类问题**。真正的修法在判据侧（识别「路径位」语境），那是另一单 |
| **R4** | **我未逐条核验「磁盘上有 1 条」是哪个** | 现读里「磁盘上有 1 条、都没有 34 条」，那 1 条我没定位。**如实标注** |
| **R5** | **未跑 `moon fmt`** | 改动全是 `.md`，不涉及 `.mbt`。`check_plan_landing.py` 也不在门禁电池里（只读诊断） |

---

## 6. 建议入档位置

1. **本节 §3 的三步判别法** → 建议并入 `AI-DEVELOPMENT-STANDARD.md` 或
   `reports/2026-10-26-plan-landing-triage-report.md` 的执行附录。
   **它是 Lane E「分类」与 Lane H「执行」之间的桥**：Lane E 分了 A/C 类，
   但没有说「同类里怎么区分该改与不该改」——§3 补的正是这一层。
2. **判据侧改进建议**（给下一单）：
   > `check_plan_landing.py` 的 `BACKTICK` 抓所有反引号内容。
   > 建议增加**语境排除**：若反引号内容出现在表格「分支名」「工具名」「命令」列的单元格里，
   > 或紧邻「分支：」「调」「执行」等词，则不当作路径候选。
   > **这比让每份文档都小心翼翼用反引号可靠得多** —— 判据该适应文档，不是文档该迁就判据。
3. **`wt_tools.mbt` 那条**：若将来判据加了「否定语境识别」，它会自动离开判定面，
   **届时不需要改文档** —— 这是判据改进优于文档迁就的又一个证据。

---

**本次未改 `src/` `scripts/` 任何文件。未碰 `check_plan_landing.py`。**
