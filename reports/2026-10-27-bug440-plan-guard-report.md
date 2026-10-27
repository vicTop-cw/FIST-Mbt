# BUG-440 修复报告 · `check_plan_location.py` 守卫落地

> **选择**：**(a) 创建守卫**（不是我推荐，是 README 已经承诺了 5 天）
> **执行人**：司令-γ · **边界**：改了 `scripts/`（新脚本 + 电池）、`docs/plans/`（1 份 frontmatter）

---

## 结论

| 项 | 结果 |
|---|---|
| **选 (a) 还是 (b)** | **(a)** —— 见 §分析 |
| **新增** | `scripts/check_plan_location.py`（387 行，16 格自检含 3 个变异对照） |
| **进电池** | `scripts/run_guards.py:167-168`（`--selftest` + 判据两格） |
| **修 4pools** | frontmatter 已补齐四字段；**AIGC 水印块保留为 HTML 注释**（不丢内容） |
| **验证** | `python scripts/check_plan_location.py` → **rc=0**（全部合规） |
| **判例-5 核对** | `check_battery_count_doc` → **PASS** `rulers=122 battery=81 missing=0` |

---

## 证据

### §1 README 承诺原文（`docs/plans/README.md:22`）

```
- **文件名**：`YYYY-MM-DD-<topic>-proposal.md`
- **头部强制字段**（缺一即红，`check_plan_location` 守卫）：
  ```yaml
  ---
  status: 提案中   # 提案中 | 已定案 | 已驳回 | 已推迟 | 已完成
  decided_by:      # 定案人（仅 human_steward）
  decided_at:      # 定案时间戳
  decision:        # approved | rejected | deferred
  ---
  ```
```

**而 `scripts/check_plan_location.py` 此前不存在** ⇒ README 硬规则 2
「未定案禁止发布任务（`plan_publish` 门禁）」的 `status` 字段**没有任何东西保证它存在**。

### §2 修前实测（守卫抓出的违例）

```
$ python scripts/check_plan_location.py
[扫描] docs/plans/ 下 4 份计划文档
[违例] 4 条：
  ✗ [P3] docs/plans/2026-10-26-4pools-rhop-roadmap-proposal.md — 缺强制字段 `status`
  ✗ [P3] ... — 缺强制字段 `decided_by`
  ✗ [P3] ... — 缺强制字段 `decided_at`
  ✗ [P3] ... — 缺强制字段 `decision`
rc=1
```

**4pools 修前头部**：
```yaml
---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_f991019ad13511f18460525400393706
    ReservedCode1: pC4ZdXEB8Gbp9/szeM+c3IuLw0nsYhDYrF3drfnn6LiNR/...
---
```
**⇒ 是 AIGC 水印块，不是 YAML frontmatter。**

### §3 修后

**`4pools` 新头部**：
```yaml
---
status: 提案中
decided_by:
decided_at:
decision:
---

<!-- 原文件头部的 AIGC 生成标记（不是 YAML frontmatter，已移到此处保留）：
  AIGC:
      Label: "1"
      ContentProducer: ...
-->
```
**AIGC 块内容原样保留**（只是从「被误当 frontmatter」变成「明确的 HTML 注释」）。

**守卫**：
```
$ python scripts/check_plan_location.py
[扫描] docs/plans/ 下 4 份计划文档
[结论] 全部合规：文件名 / frontmatter 位置 / 四字段 / status 闭集 / 已定案自洽
rc=0
```

### §4 判据设计（六条，窄口径只判 header 形状）

| 代号 | 判什么 | 判红？ |
|---|---|---|
| **P1** | 文件名 `YYYY-MM-DD-<topic>.md` | 是 |
| **P2** | frontmatter 必须**第 1 行**起 `---` | 是（AIGC 块占第 1 行即红） |
| **P3** | 四键**名**必须出现 | 是 |
| **P4** | `status` ∈ 闭集 `{提案中,已定案,已驳回,已推迟,已完成}` | 是 |
| **P5** | `已定案` ⇒ `decided_by==human_steward` + `decided_at` 非空 + `decision` 闭集 + `decisions/` 有同日记录 | 是 |
| **P6** | 终态计划应移到 `archived/` | **否（只告警）** |

**关键设计点（最容易写错的地方）**：**P3 只判键名，不判值。**
`status: 提案中` 时 `decided_by`/`decided_at`/`decision` **本来就该为空**（README 模板就是空的）。
若判「值必须非空」，会把所有合法提案判红 —— **那是又一种「判据把正常样本判坏」**。

### §5 rc 契约（与 `check_fmt_gate.py` / `check_two_faces.py` 同口径，不新造）

```
0 = 全部合规
1 = 有违例（逐条点名，带 P 代号）
2 = 判据无法自证（plans 目录不存在 / 一份提案都没扫到）
```
**`2` 那一档是本判据的「反幻影哨兵」**：空扫描面**绝不因「没找到」报绿**。

### §6 selftest 16 格（3 个变异对照）

```
[OK] valid-proposal-rc0
[OK] MUTATION-missing-key-rc1 / MUTATION-missing-key-named        ← 变异对照1：删字段
[OK] MUTATION-aigc-watermark-rc1 / MUTATION-aigc-detected-P3      ← 变异对照2：AIGC 伪 frontmatter
[OK] bad-status-rc1 / bad-status-code-P4
[OK] bad-filename-rc1 / bad-filename-code-P1
[OK] decided-with-record-rc0
[OK] MUTATION-decided-no-record-rc1 / MUTATION-decided-no-record-P5 ← 变异对照3：已定案缺 decisions 记录
[OK] empty-dir-self-reject-rc2 / empty-dir-says-FATAL
[OK] crlf-frontmatter-rc0            ← 本仓 2 份提案是 CRLF，必须容忍
[OK] readme-skipped-rc0
[selftest] 16/16 格通过
```

**判例-30 防护**：所有夹具用**真文件写入** `tempfile` 临时目录（`newline=""` 保留 CRLF），
不引用脚本内注释里的示例；变异格**真删真改**夹具文件后再跑判据。

### §7 判例-5（执行面）

```python
# scripts/run_guards.py:167-168
    # —— BUG-440：docs/plans/ frontmatter 守卫（README:22 承诺了 5 天，守卫文件此前不存在）——
    case("check_plan_location.py", "--selftest"),
    case("check_plan_location.py"),
```

```
$ python scripts/check_battery_count_doc.py
PASS 电池读数与 README 登记逐键一致：rulers=122 ci=46 battery=81 missing=0 gate=89 exempt=28
```
**⇒ `missing=0`（新增面已被登记）。**

---

## 分析：为什么选 (a) 而不是 (b)

**(b) 改 README 删掉承诺是「承认不守」，但 README 的硬规则 2 离不开 `status`：**

> 「**未定案（`status != 已定案`）禁止发布任务**（`plan_publish` 门禁）」

**若 `status` 字段本身可以缺失，这道门禁读什么？**
- 读不到 ⇒ 当成「已定案」放行 ⇒ **越权发布**
- 读不到 ⇒ 当成「提案中」拒绝 ⇒ 但没有任何规则说「缺失即视为提案中」

**⇒ 两种都不可接受 ⇒ 缺字段必须在**入库时**就红，不能在**消费时**猜。**

**选 (a) 的额外收获**：这条判据把「文档承诺的判据从未存在」这一类**变成可机械检查的**。
以后谁再写「XX 守卫」而没建文件，**只要进电池就会在第一次跑时红**（`2` 或 `1`）。

**为什么不选「只改 README 说这是自律」**：那等于承认「计划库可以随便放文件」，
而 `docs/plans/README.md` 的硬规则 1「计划只进 `docs/plans/`」也需要一个能**证明**它被遵守的东西。

---

## 缺口与风险

1. **AIGC 水印块现在是 HTML 注释，仍会出现在渲染后的文档里**（`<!-- -->` 在 Markdown 渲染时不可见，
   但在 `git diff` / 纯文本读时可见）。**这是有意的**——不丢生成标记。
   若你希望**彻底删掉**，请指示（那是内容决策，不是判据决策）。
2. **P6（终态应归档）只告警** —— 本轮扫到的 4 份里 `已定案` 2 份仍在 `plans/` 根。
   **它们该不该移到 `archived/`** 取决于「已定案但未执行完」算不算终态 ⇒ **需你裁**。
3. **`decisions/` 匹配是「日期前缀包含」**，不是严格一一对应。
   若将来出现同一天两份定案，可能误判为「已满足」。**当前 2 份定案日期不同 ⇒ 未触发。**
4. **未核 `docs/proposals/`** —— `check_plan_landing.py` 的 docstring 提到过 `docs/proposals/`，
   若那个目录也存在同类的计划文档，**本守卫不管它**（只管 `docs/plans/`）。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-27-bug440-plan-guard-report.md` |
| 判据 | `scripts/check_plan_location.py`（16 格自检） |
| 执行面 | `scripts/run_guards.py:167-168` |
| 修好的样本 | `docs/plans/2026-10-26-4pools-rhop-roadmap-proposal.md` |
| **未做** | **未调 `bug_fix`**（BUG-440 的关闭需你终审后再标）· **未移动** `已定案` 提案到 `archived/`（等裁） |
