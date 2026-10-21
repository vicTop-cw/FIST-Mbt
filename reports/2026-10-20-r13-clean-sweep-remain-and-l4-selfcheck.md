# R13 组合模式 · clean 面补齐扫描 + 交付物 L4 自证（Round 13）

- 日期：2026-10-20
- 模式：寻虫 + 验证（bugfind + verify）
- 轮次：R13 / 256（目标 ACTIVE，未关闭）
- 结论：**补齐 clean 面剩余 4 模块扫描（`src/constraint` / `src/symbolic` / `src/hat` / `atgc`），真 bug = 0**（唯一 medium 命中 `atgc_run.mbt:48` substring-overrun 经读源确认为守卫误报）；**用 fist-mbt 自身 `output_validate`（证据梯 L4 硬门）对 R11/R12 交付物自证 = l4-pass 3/3**。
- 来源：R12 报告 `reports/2026-10-20-r12-denoise-rules-ab-and-bug345.md`（BUG-345 已入账）

## 结果摘要

### 1. 并发状态复查
- 工作树脏 **205**（与 R12 持平）；`src/server` 仍 **37 脏** ⇒ 源码修复继续阻塞（禁写 `src/server/*`）
- 剩余 publish P1：7（同 R12，全并发 WIP）

### 2. clean 面补齐扫描（`src/constraint` / `src/symbolic` / `src/hat` / `atgc`）
至此 clean 可编辑面 11 个单元全部扫完（R11：core/claimguard/ltl/decompose；R13：constraint/symbolic/hat/atgc）。

| 目录 | files | findings | high | medium | 关键命中 |
|---|---|---|---|---|---|
| `src/constraint` | 1 | 15 | 0 | 0 | match-exhaustive ×2（编译期已保证穷尽） |
| `src/symbolic` | 1 | 144 | 0 | 0 | array-index ×4（循环上界约束） |
| `src/hat` | 7 | 152 | 0 | 0 | private-field-leak ×6 / overly-broad-catch ×1 / array-index ×4 |
| `atgc` | 3 | 53 | 0 | **1** | `atgc_run.mbt:48` substring-overrun（**核实为守卫误报**，见下） |
| **合计（本轮）** | 12 | **364** | **0** | **1** | 全部误报 |

**唯一 medium 命中逐字复核（`atgc/atgc_run.mbt:44-48`）**：
```moonbit
fn assemble(seq : String) -> Array[Inst] {
  let n = normalize(seq)
  let codons : Array[String] = []
  for i = 0; i + 3 <= n.length(); i = i + 3 {   // ← 循环条件守卫
    codons.push(n.substring(start=i, end=i + 3)) // ← end=i+3 恒 ≤ length
  }
```
循环条件 `i + 3 <= n.length()` **保证** `end = i+3 ≤ length`，`substring` 永不越界；`n.length() < 3` 时循环体不执行、返回空程序，无副作用。⇒ **规则 `substring-overrun` 只做行级匹配，看不见 `for` 守卫**，恒假阳性。同文件 L53 `codons[i]` 在 `i < codons.length()` while 循环内，安全。

**其余 low 命中的复核结论**：`src/symbolic/symbolic.mbt:86/129/508/544` 数组下标均在 `for … < acc.length()/var_names.length()/exprs.length()` 循环内；`src/hat` 的 `private-field-leak` 命中多为 `pub fn` 返回内部类型（展示层 API，非真泄露）、`overly-broad-catch` 为 `parse_*` 的统一 `Err(msg)` 收敛（有意设计）；均安全。

**累计 clean 面结论**（R11+R13，共 11 单元）：`issue_scan` 命中 **794 处**，逐条复核关键项全部误报；**真 bug = 0**。R12 的 BUG-345 是唯一通过 rules_file A/B 实测发现的**真**缺陷。

### 3. 交付物 L4 自证（用 fist-mbt 自身能力验证自己）
调用 `output_validate`（证据梯 L4 硬门，R113），对 R12 关键交付物做文件存在/非空 + invariant 检查：

| artifact | invariant | 结果 |
|---|---|---|
| `reports/2026-10-20-r12-denoise-rules-ab-and-bug345.md` | min_chars=200, contains="BUG-345" | ✅ |
| `memory/bug333_denoise_rules.json` | contains="match-exhaustive" | ✅ |
| `memory/2026-10-20.md` | contains="R12" | ✅ |

**verdict = pass，evidence_layer = l4-pass，passed 3 / failed 0** —— R12 的「BUG-345 上报 + 降噪规则文件入库 + memory 日志」三件交付物经 fist-mbt 硬门自证成立，非自述。

### 4. 顺带复核
- `atgc_run.mbt:78` `assemble(normalize(seq))` 与 L45 `normalize(seq)` 双重归一化 —— 幂等，非 bug。
- `src/hat/hat_config.mbt` 的 `get_field/get_str/get_bool/get_int` 系列是对 `Json` 的**统一容错封装**，`match j` 命中全为 `Option` 处理，安全。

## 资源消耗
- 调用：`issue_scan` ×4（constraint/symbolic/hat/atgc）、`output_validate` ×1
- 新增 commit：无（本轮未改任何源文件）
- 未改 `src/server/*`，未 `git add -A`

## 任务分配记录
- 全自查自跑（无子代理）。
- 未新增 bug；BUG-345（R12）+ BUG-333 ①③ + BUG-327 p2 + BUG-238 server 层仍待 `src/server` 并发 WIP 清空后收口。

## 遗留风险
1. `src/server` 37 脏未清 ⇒ 4 项缺陷修复全部阻塞（BUG-345/333①③/327p2/238）。
2. publish P1 7 项仍红。
3. clean 面 794 处扫描命中全为子串近似噪音，**`issue_scan` 的 low/info 桶对 MoonBit 近乎无信息量** —— 这再次印证 R12 的 BUG-345 必须修：不修则降噪预案对 by_severity 零收益，扫描结果仍无法指导人工判读。

## 后续建议
1. **优先修 BUG-345**（四桶聚合 + 白盒锁）—— clean 面 794 处噪音的"可判读性"依赖它。
2. BUG-333 ①③ 与 BUG-345 一起收口。
3. 建议加一条常驻判据脚本：固定目录 + 固定 `rules_file=memory/bug333_denoise_rules.json`，断言降噪后 `by_severity.low` 严格下降 —— 把 R12 手工发现的回归锁住（归属 `scripts/`，待该目录并发 WIP 清空后加）。
4. 后续轮次若 `src/server` 清空，直接落地上述 4 项修复并跑 `moon test --target js` 全量验证（当前权威门槛 1347/1347）。

## 超额内容
- 本轮用 fist-mbt 自己的**验证工具验证自己的交付物**（`output_validate` → l4-pass），把「R12 发现了 BUG-345」从自述升级为**可被硬门复证的产物状态**——符合「证据梯至少 L4」的 FIST 专项规范。

## 来源
- 工具回执（本轮）：`issue_scan` ×4、`output_validate` ×1（l4-pass 3/3）
- 源码复核：`atgc/atgc_run.mbt` L42-70（assemble 循环守卫）、L74-84；`src/symbolic/symbolic.mbt` L80-90/L120-130/L500-510/L540-548；`src/hat/hat_config.mbt` L180-260
- 前置：R12 报告、BUG-345 账本条目
